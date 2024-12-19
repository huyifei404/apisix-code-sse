local core                      = require("apisix.core")
local ngx                       = ngx
local req                       = core.request
local log                       = core.log
local query_template            = require("apisix.plugins.dag-datasource.query_process.template_query")
local exception                 = require("apisix.plugins.exception")
local new_tab                   = require("table.new")
local string_util               = require("apisix.plugins.utils.string_util")
local fetch_fmt_encode          = require("apisix.plugins.uig-route.fetch_fmt_encode").invoke
local fetch_process_appid       = require("apisix.plugins.uig-route.fetch_process_appid").invoke
-- local template_exec             = require("apisix.plugins.nlbpm.template_exec")
local json_decode               = core.json.decode
local json_encode               = core.json.encode
local sys_build                 = require("apisix.plugins.nlbpm.sys")
local get_method                = ngx.req.get_method
local get_req_headers           = req.headers
local get_uri_args              = ngx.req.get_uri_args
local get_req_body              = req.get_body
local sub_str                   = string.sub
-- local amg_req_handler           = require("apisix.plugins.amg.req_handler")
local failed_req_record         = require("apisix.plugins.failed-req-record")
local emergency_log             = require("apisix.plugins.emergency-log")
local json_delay_encode         = core.json.delay_encode
local sw8                       = require("apisix.plugins.sw-prefix")
local form_data_util            = require("apisix.plugins.utils.form_data_util")
local snowflake_util            = require("apisix.plugins.utils.snowflake_util")
local switch_query              = require("apisix.plugins.dag-datasource.query_process.switch_query")
local business_switch_code      = require("apisix.plugins.utils.redis_util.business_switch")
local set_req_header            = ngx.req.set_header
local pairs                     = pairs

local _M = {}
-- ================================常量=====================================
local REQ_INFO_HASH_NUM=30

local GET_PROCESS_CODE_HEADER="NL_PROCESS_CODE"
local GET_PROCESS_CODE_HEADER_LOWER="nl_process_code"

-- =================================私有方法=================================
-- 从请求协议模板中获取返回的header，作为能力的请求头
local function set_ability_header(exe_out_headers)
    local tab = json_decode(exe_out_headers)
    for k,v in pairs(tab) do
        set_req_header(k,v)
    end
end

local function get_zipkintrace_switch(ctx)

    if ctx.business_switch == nil then
        ctx.business_switch=new_tab(0, 30)
        ctx.business_switch.ZIPKINTRACE_SWITCH = business_switch_code.SWITCH_CLOSE
    end

    local res,err = switch_query.get_switch(business_switch_code.ZIPKINTRACE_SWITCH)
	core.log.info("res : ",res)

    if err then
        core.log.error("查询redis中的业务开关失败:",err)
    else
        if res ~= nil then
            if res == business_switch_code.SWITCH_OPEN and ctx.business_switch.ZIPKINTRACE_SWITCH == business_switch_code.SWITCH_CLOSE then
                ctx.business_switch.ZIPKINTRACE_SWITCH = business_switch_code.SWITCH_OPEN
            elseif res == business_switch_code.SWITCH_CLOSE and ctx.business_switch.ZIPKINTRACE_SWITCH == business_switch_code.SWITCH_OPEN then
                ctx.business_switch.ZIPKINTRACE_SWITCH = business_switch_code.SWITCH_CLOSE
            end
        end
    end
    core.log.info("business_switch : ",ctx.business_switch.ZIPKINTRACE_SWITCH)
end


-- 协议模板处理
local function protocol_process(conf,ctx,req_body)
    -- ===skywalking===
    --local trace_id = sw8.ability_start(ctx)
    sw8.ability_start(ctx)
    -- ===skywalking===

    log.info("拦截 uri:", ngx.var.uri)
    -- req_info,sys初始化
    local req_info=ctx.req_info
    local req_headers = ngx.req.get_headers(nil,true)
    -- 判断是否接入服务amg标准的请求
    -- if req_headers["server-type"] == "amg" then
    --     return amg_req_handler.execute_amg_process(ctx)
    -- end

    local trace_id = req_headers["traceid"]
    -- core.log.warn("trace_id:",trace_id)
	log.info("客户端传入的trace_id:",trace_id)
    if trace_id ~= nil then
        ctx.req_id = trace_id
    else
        if ctx.business_switch and ctx.business_switch.ZIPKINTRACE_SWITCH == business_switch_code.SWITCH_OPEN then
            ctx.req_id = snowflake_util.next_trace_id()
        end
    end
	log.info("设置后的ctx.req_id:",ctx.req_id)

    -- 执行aoc的预处理流程
    req_info.sys=sys_build.new()

    emergency_log.g_log(ctx,"客户端请求报文:",req_body)
    log.info("客户端请求头:",core.json.delay_encode(req_headers))
    log.info("客户端请求报文:",req_body)
    -- 获取报文的格式和编码
    req_body = string_util.check_xml_declaration(req_body,1)
    local app_format, app_encoding, err = fetch_fmt_encode(req_body)
    if not app_format or not app_encoding then
        -- if amg_req_handler.check_header(req_headers) then
        --     return amg_req_handler.execute_amg_process(ctx,nil,true)
        -- end
        req_info.app_format="XML"
        req_info.app_encoding="UTF-8"
        core.log.error("获取请求格式和编码失败:",err)
        return exception.throw(req_info, exception.type.EXCEPT_FORMAT,
                                exception.code.DAG_ERR_ROUTE_XML_FORMAT_ERR, err)
    end
    req_info.app_format = app_format
    req_info.app_encoding = app_encoding
    log.debug("req_info:", core.json.delay_encode(req_info))

    -- 从报文获取process_code，app_id
    local process_code, app_id,err = fetch_process_appid(req_body, app_format)
    if err then
        core.log.error("请求报文格式错误:",err)
        return exception.throw(req_info, exception.type.EXCEPT_REQUEST,
                                exception.code.DAG_ERR_REQ_BODY,
                                "报文格式错误:"..err)
    end
    -- 若当前请求为GET请求，则从请求头获取process_code
    if get_method() == "GET" then
        core.log.info("headers:",core.json.delay_encode(req_headers))
        process_code = req_headers[GET_PROCESS_CODE_HEADER] or req_headers[GET_PROCESS_CODE_HEADER_LOWER] or process_code
        log.info("get请求，从请求头获取process_code:",process_code)
    end
    core.log.info("process_code:", process_code or "nil", ",app_id:",
                    app_id or "nil")

    -- 匹配协议模板
    -- 测试: 缓存模板关系信息
    local protocol_info, err = query_template.get_protocol_relation(
                                    process_code, app_id)
    if protocol_info == nil then
        core.log.error("匹配协议模板失败，redis连接出错:", err)
        return exception.throw(req_info, exception.type.EXCEPT_MEMDB,
                                exception.code.DAG_ERR_REDIS_INIT,
                                "【NY】内存数据库连接失败:"..err)
    elseif protocol_info == false then
        -- if amg_req_handler.check_header(req_headers) then
        --     return amg_req_handler.execute_amg_process(ctx,nil,true)
        -- end
        core.log.error("请求无法匹配协议模板,process_code:",
                        process_code, ",app_id:", app_id)
        return exception.throw(req_info, exception.type.EXCEPT_BUSINESS,
                                exception.code.DAG_ERR_TEMPLATE_MATCH_ERR,
                                "【NY】协议模板匹配失败")

    end
    emergency_log.g_log(ctx,"请求模板信息",json_delay_encode(protocol_info))
    local req_template_info, err = query_template.get_template_info(
                                        protocol_info[query_template.TEMPLATY_TYPE_REQ])
    if not req_template_info then
        core.log.error("获取请求模板失败:" .. err)
        return exception.throw(req_info, exception.type.EXCEPT_DAG,
                                exception.code.DAG_ERR_TEMPLATE_GET_TPL_ERR,
                                "【NY】未找到对应的请求模板:" .. err)
    end
    emergency_log.g_log(ctx,"请求模板执行")
    -- local exe_out, err_tab = template_exec.sfdl_exec(ctx,process_code,
    --                                                     req_template_info.content,
    --                                                     req_template_info.template_name,
    --                                                     req_template_info.version_code,
    --                                                     req_body, app_encoding)
    -- if not exe_out then
    --     core.log.error("请求模板执行失败:", err_tab.msg)
    --     return exception.throw(req_info, err_tab.type, err_tab.code,
    --                             err_tab.msg)
    -- end
    if req_info.sys.ex_class then
        local ex_class = req_info.sys.ex_class
        local ex_code = req_info.sys.ex_code or ""
        local ex_msg = req_info.sys.ex_msg or ""
        core.log.error("模板返回业务错误:",ex_msg)
        return exception.throw(req_info, ex_class, ex_code, ex_msg)
    end
    -- emergency_log.g_log(ctx,"请求模板处理完成返回headers:",exe_out.headers)
    -- emergency_log.g_log(ctx,"请求模板处理完成返回body:",exe_out.body)
    req_info.protocol_info = protocol_info
    -- req_info.req_tab = json_decode(exe_out.body)
    emergency_log.g_log(ctx,"请求模板执行成功")
    -- 打印sys系统参数
    emergency_log.sys_log(ctx)

    -- 设置能力请求头
    -- set_ability_header(exe_out.headers)

    -- 重写uri
    local ability_code=req_info.sys.process_code
    if ability_code == nil then
        return exception.throw(req_info,exception.type.EXCEPT_DAG,
                            exception.code.DAG_ERR_ROUTE_NOT_FOUND_APICODE,
                            "【NY】系统错误，请求缺少能力编码")
    end
    local new_uri = "/" .. ability_code
    log.info("new_uri:", new_uri)
    ngx.req.set_uri(new_uri)
    ctx.var.uri = new_uri

    -- ===skywalking===
    sw8.set_ability_code(ctx,ability_code)
    -- ===skywalking===
end

-- 通用uig请求接入
local function uig_process(conf,ctx)
    log.info("通用uig请求接入")
    return protocol_process(conf,ctx,ctx.req_info.raw_req_body)
    -- if ngx.var.uri == conf.uig_uri then
    --     return protocol_process(conf,ctx,ctx.req_info.raw_req_body)
    -- else
    --     log.error("请求拒绝，无效uri，通用uig仅支持uri为:",conf.uig_uri,"当前uri:",ngx.var.uri)
    --     return exception.throw(ctx.req_info,exception.type.EXCEPT_REQUEST,
    --                             exception.code.DAG_ERR_INVALID_URI,"无效请求uri")
    -- end
end


-- 一级能开请求接入
local function open_process(conf,ctx)
    log.info("一级能开请求接入")
    if ngx.var.uri == conf.open_uri then
        return protocol_process(conf,ctx,ctx.req_info.raw_req_body)
    else
        log.error("请求拒绝，无效uri，一级能开仅支持uri为:",conf.open_uri,"当前uri:",ngx.var.uri)
        return exception.throw(ctx.req_info,exception.type.EXCEPT_REQUEST,
                                exception.code.DAG_ERR_INVALID_URI,"【NY】无效请求uri")
    end
end

-- 一级商城请求接入
local function shop_process(conf,ctx)
    log.info("一级商城请求接入")
    local process_code = conf.shop_uris[ngx.var.uri]
    if process_code then
        -- 解析请求报文转为table
        local req_tab,err=json_decode(ctx.req_info.raw_req_body)
        if not req_tab then
            return exception.throw(ctx.req_info,exception.type.REQUEST,
            exception.code.DAG_ERR_REQ_BODY,"一级商城请求报文格式错误"..err)
        end
        req_tab.process_code=process_code
        return protocol_process(conf,ctx,json_encode(req_tab))
    else
        log.error("请求拒绝，无效uri，一级商城不支持当前uri:",ngx.var.uri)
        return exception.throw(ctx.req_info,exception.type.EXCEPT_REQUEST,
                                exception.code.DAG_ERR_INVALID_URI,
                                "无效请求uri")
    end
end

-- GET请求处理
local function get_process(conf,ctx)
    -- 获取url参数，转为请求body
    local args_tab,err=get_uri_args()
    if err == "truncated" then
        log.error("get请求参数超出限制")
        return exception.throw(ctx.req_info,exception.type.EXCEPT_REQUEST,
                                exception.code.DAG_ERR_ROUTE_PARAM_TOO_LONG,
                                "【NY】请求参数超出限制")
    end
    -- url参数解码处理
    -- for k,v in pairs(args_tab) do
    --     args_tab[k] = ngx.unescape_uri(v)
    -- end
    return protocol_process(conf,ctx,json_encode(args_tab))
end

-- FORM-DATA请求处理
local function form_data_process(conf,ctx)
    -- core.log.warn("req_body:",core.json.delay_encode(get_req_body()))
    -- TODO: 设置文件大小和数量限制
    local args,err = form_data_util.decode(ctx)
    if not args then
        log.error("form-data报文解析失败,err:",err)
        return exception.throw(ctx.req_info,exception.type.EXCEPT_REQUEST,
                                exception.code.DAG_ERR_SERVICE_FORM_DATA_PARSE,"【NY】请求报文错误，form-data内容无法解析:"..(err or "nil"))
    end
    core.log.info("file_temp:",core.json.delay_encode(ctx.file_temp))

    return protocol_process(conf,ctx,json_encode(args))
end

local funcs={
    uig=uig_process,
    open=open_process,
    shop=shop_process
}
-- ==================================模块方法=================================
function _M.invoke(conf, ctx)
    ctx.req_info=new_tab(0, REQ_INFO_HASH_NUM)
    --ctx.req_id = uuid()
    failed_req_record.check_enable(ctx)
    -- 校验系统释放开启crit紧急日志，是则将信息存入上下文
    emergency_log.check_enable(ctx)
    failed_req_record.create_req_record(ctx)

    local method = ngx.req.get_method()
    get_zipkintrace_switch(ctx)

    -- ========GET请求适配========
    if method == "GET" then
        return get_process(conf,ctx)
    end
    -- ========POST请求适配=========
    if method == "POST" then
        -- ========FORM-DATA类型请求处理========
        if sub_str(ngx.var.content_type or "",1,19) == "multipart/form-data" then
            log.info("接入form-data请求")
            return form_data_process(conf,ctx)
        end
        -- ========普通post请求处理========
        log.info("接入普通post请求")
        local req_body=get_req_body()
        core.log.info("req_body:",req_body)
        if req_body == nil or #req_body==0 then
            log.error("POST请求拒绝,请求body为空,无法解析请求信息")
            return exception.throw(ctx.req_info,exception.type.EXCEPT_REQUEST,
                                    exception.code.DAG_ERR_ROUTE_BODY_EMPTY,
                                    "【NY】body为空,无法解析请求信息")
        end
        ctx.req_info.raw_req_body=req_body
        local process_fun=funcs[conf.type]
        return process_fun(conf,ctx)
    end
    return exception.throw(ctx.req_info,exception.type.EXCEPT_REQUEST,
                                    exception.code.DAG_ERR_INVALID_URI,"【NY】不支持的请求方法:"..method)

end

return _M
