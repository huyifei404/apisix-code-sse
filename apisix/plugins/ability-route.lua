local core = require("apisix.core")
local ngx = ngx
local log = core.log
local simple_ability = require("apisix.plugins.ability-route.simple_ability")
-- local compose_ability = require("apisix.plugins.ability-route.compose_ability")
local exception = require("apisix.plugins.exception")
local convert_util = require("apisix.plugins.utils.convert_util")
local read_conf_util = require("apisix.plugins.utils.read_conf_util")
-- local nlbpm_util = require("apisix.plugins.nlbpm.nlbpm_util")
-- local amg_req_handler = require("apisix.plugins.amg.req_handler")
local emergency_log = require("apisix.plugins.emergency-log").g_log
local form_data_util    = require("apisix.plugins.utils.form_data_util")
local authorization_query   = require("apisix.plugins.dag-datasource.query_process.authorization_query")
local switch_query          = require("apisix.plugins.dag-datasource.query_process.switch_query")
local business_switch_code  = require("apisix.plugins.utils.redis_util.business_switch")
local return_code_query     = require("apisix.plugins.dag-datasource.query_process.return_code_query")
local util = require("apisix.cli.util")

-- ====================================插件定义====================================
local plugin_name = "ability-route"

local schema = {
    type = "object",
    properties = {
        -- 1 透传能力,2 编排能力
        type = {type = "integer", enum = {1, 2, 3, 4}},
        template_id={
            type = "string", minLength = 1, maxLength = 64
        },
        service_code={
            type = "string", minLength = 1, maxLength = 64
        },
        amg_flag={
            type = "integer", enum = {0, 1}
        }
    },
    additionalProperties = false,
    anyOf={
        {required = {"type"}},
        {required = {"amg_flag"}}
    }
}

local _M = {version = 0.1, priority = 500, schema = schema, name = plugin_name}

function _M.check_schema(conf)
    local ok, err = core.schema.check(schema, conf)
    if not ok then
        return false, err
    end
    if conf.amg_flag == 1 then
        return true
    else
        conf.amg_flag = 0
    end
    if conf.type==1 and conf.service_code == nil then
        return false,"透传能力必须指定服务code"
    end
    -- if conf.type==2 and conf.template_id==nil then
    --     return false,"编排能力必须指定编排模板id"
    -- end
    return true
end

-- ===================================私有方法=====================================

local function checkAgain(ctx)

    -- 业务开关判断
    local check_switch=business_switch_code.SWITCH_CLOSE
    local res,err = switch_query.get_switch(business_switch_code.ABILITY_AUTHORIZATION)
    if err then
        core.log.error("查询redis中的业务开关失败:",err)
    else
        if res ~= nil then
            if res == business_switch_code.SWITCH_OPEN then
                check_switch = business_switch_code.SWITCH_OPEN
            end
        end
    end
    -- 默认关闭，无需判断
    if check_switch == business_switch_code.SWITCH_CLOSE then
        return true;
    end

    -- 获取能力编码
    local req_info = ctx.req_info
    local ability_code = req_info.sys.process_code

    local ability_authorization,err2 = authorization_query.get_ability_authorization(ability_code)
    if err2 ~=nil then
        core.log.error("查询需要二次确认的能力失败:",err2)
    end
    -- 该能力不在需要判断的列表之中
    if ability_authorization == nil then
        return true
    end

    local now        = os.date("%Y%m%d%H%M%S");
    local ability_status     = ability_authorization.STATUS
    local ability_start_time = ability_authorization.START_TIME
    local ability_end_time   = ability_authorization.END_TIME
    -- 该能力不需要做判断
    if ability_status == 0 then
        return true
    end
    --该规则已经失效
    if ability_start_time>now or ability_end_time<now then
        return true
    end

    local app_id = req_info.sys.app_id

    local req_headers = ngx.req.get_headers(nil,true)
    --------------此处需要修改 属性名称 -----------------
    -------------参考 apisix.plugins.uig-route.fetch_process_appid 修改,
    -------------可放入uig-route/phase_func/rewrite的 protocol_process 中
    local group_id_attr = "x-sg-group-id"
    local group_id = req_headers[group_id_attr] or ""
    if group_id == "" then
        local bodys,err3 = core.request.get_body();
        if err3 ~=nil then
            core.log.error("获取body失败:",err3)
            return false
        end

        if bodys == nil then
            core.log.error("body为空:")
            return false
        end

        group_id = bodys[group_id_attr] or ""
    end

    if group_id == "" then
        core.log.error("未能获取到group_id")
        return false
    end

    local authorization_api_group,err3 = authorization_query.get_authorization_api_group(app_id,group_id)
    if err3 ~=nil then
        core.log.error("查询二次确认白名单失败:",err3)
    end

    -- 未查找到白名单
    if authorization_api_group == nil then
        return false
    end
    local api_group_status     = authorization_api_group.STATUS
    local api_group_start_time = authorization_api_group.START_TIME
    local api_group_end_time   = authorization_api_group.END_TIME

    -- 白名单状态为失效
    if api_group_status == 0 then
        return false
    end
    -- 白名单不在生效时间内
    if api_group_start_time>now or api_group_end_time<now then
        return false
    end
    -- 所有检查通过
    return true
end

-- ===================================模块方法=====================================
function _M.access(conf, ctx)
    core.log.info("ability-route access phase start......")
    local req_info = ctx.req_info
    -- 该请求已经过能力路由,开始进入能力调用流程
    req_info.ability_route_flag = true
    if conf.amg_flag == 1 then
        core.log.warn("能力判定为集团服务，执行amg请求流程")
        local aoc_req_param = {}
        aoc_req_param.process_code = req_info.sys.process_code
        aoc_req_param.app_id = req_info.sys.app_id
        -- return amg_req_handler.execute_amg_process(ctx,aoc_req_param)
    end

    -- 判断redis中是否有返回码配置
    --local res,err = return_code_query.get_config(req_info.sys.process_code)
    --if err then
    --    core.log.error("查询redis中的返回码配置失败:",err)
    --else
    --    if res ~= nil then
    --        ctx.return_code=res
    --    end
    --end

    --二次校验
    -- local check_result = checkAgain(ctx)
    -- if check_result == false then
    --     log.error("二次校验不通过")
    --     return
    -- end

    -- 透传能力
    if conf.type == 1 then
        log.info("调用透传能力.....")
        req_info.ability_type = 1
        local res, err_tab = simple_ability.ability_call(ctx,conf)
        if not res then
            log.error("透传能力调用失败:",err_tab.msg)
            log.error("外围请求方法:",ngx.req.get_method())
            log.error("外围请求报文:",core.request.get_body())
            return exception.throw(req_info, err_tab.type, err_tab.code,
                    err_tab.msg)
        end
        -- for k, v in pairs(res.headers) do ngx.header[k] = v end
        ctx.req_info.svc_resp_header=res.headers
        ngx.header["Content-Length"] = nil
        ctx.req_info.ab_resp_body=res.body
        log.debug("能力响应报文:",res.body)
        return res.status, res.body
        -- 编排能力
    elseif conf.type == 2 then
        log.info("调用编排能力.....")
        -- local status,body=compose_ability.ability_call(ctx,conf)
        -- ctx.req_info.ab_resp_body=body
        -- ctx.req_info.is_process_template=true
        -- log.debug("能力响应报文:",body)
        -- return status,body
        --长链接：SSE/WebSocket
    elseif conf.type == 3 then
         ctx.conn_protocol = "sse"
        local res, err_tab = simple_ability.sse_protocol_call(ctx,conf)
        if not res then
            log.error("透传能力调用失败:",err_tab.msg)
            log.error("外围请求方法:",ngx.req.get_method())
            log.error("外围请求报文:",core.request.get_body())
            return exception.throw(req_info, err_tab.type, err_tab.code,
                    err_tab.msg)
        end
        ctx.req_info.svc_resp_header=res.headers
        ngx.header["Content-Length"] = nil
        ctx.req_info.ab_resp_body=res.body        
        return res.status, res.body
    elseif conf.type == 4 then
        ctx.conn_protocol = "websocket"
        log.info("调用websocket能力")
        simple_ability.wb_protocol_call(ctx, conf)
    end 
end

local function find_field_value(obj, field_path)
    local fields = util.split(field_path, ".")
    local value = obj
    -- 按照点符号分割字段路径，并逐级访问 JSON 对象
    for _, field in ipairs(fields) do
        if type(value) ~= "table" then
            return nil
        end
        value = value[field]
    end
    return value
end

function _M.header_filter(conf, ctx)
    if ctx.amg_req_flag then
        return
    end
    if ctx.conn_protocol then
        return
    end
    core.log.info("ability-route header_filter phase start......")
    local req_info = ctx.req_info
    local resp_tab = req_info.resp_tab
    if not resp_tab then
        core.log.error("无法从上下文获取响应table")
        return
    end
    
    local resp_body
    if req_info.sys.transfer_raw_body == "1" and conf.type == 1 then
        -- 透传情况下将服务的返回报文透传给外围
        resp_body = req_info.ab_resp_body
    elseif conf.type == 3 then
        core.log.info("req_info.ab_resp_body:", core.json.delay_encode(req_info.ab_resp_body))
        resp_body = req_info.ab_resp_body
    else
        -- 经响应模板处理后，编码必定为UTF-8
        resp_body = convert_util.tab_to_body(req_info.resp_tab,
                "UTF-8",
                req_info.app_encoding,
                req_info.app_format)
    end

    if resp_body then
        ctx.req_info.dag_resp_body=resp_body
        --if ctx.return_code and resp_tab then
        --    core.log.debug("返回码配置:",core.json.delay_encode(ctx.return_code))
        --    -- redis存储的结构是 字段名:匹配内容
        --    for k, v in pairs(ctx.return_code) do
        --        -- 取出此字段
        --        local matchParam = find_field_value(resp_tab, k)
        --        if matchParam and string.find(matchParam, v) then
        --            core.log.debug("字段匹配成功:",k)
        --            req_info.sys.ex_class = exception.type.EXCEPT_DAG
        --            req_info.sys.ex_code = exception.code.DAG_ERR_CONFIGURED
        --            break
        --        end
        --    end
        --end
    else
        log.error("请求信息解码失败")
        req_info.dag_resp_body = convert_util.tab_to_body(resp_tab, "UTF-8",
                req_info.app_encoding or "UTF-8",
                req_info.app_format or "XML") or "请求信息解码失败"
    end
    ngx.header["Content-Length"]=resp_body and #resp_body
    ngx.header["Transfer-Encoding"]=nil
end

function _M.log(conf,ctx)
    emergency_log(ctx,"释放文件缓存(已匹配能力)")
    form_data_util.release_file_temp(ctx)
    core.log.info("ability-route log phase start......")
    emergency_log(ctx,"释放模板引擎内存(已匹配能力)")
    -- nlbpm_util.finally_release(ctx)
end

return _M
