local core                      = require("apisix.core")
local upper_str                 = string.upper
local ngx                       = ngx
local exception                 = require("apisix.plugins.exception")
local exception_catch           = require("apisix.plugins.exception.catch").invoke
local convert_util              = require("apisix.plugins.utils.convert_util")
local query_template            = require("apisix.plugins.dag-datasource.query_process.template_query")
local read_conf_util            = require("apisix.plugins.utils.read_conf_util")
local template_exec             = require("apisix.plugins.nlbpm.template_exec")
local json_decode               = core.json.decode
local log                       = core.log
local emergency_log             = require("apisix.plugins.emergency-log")

local _M={}

-- 响应报文处理（执行响应模板，格式转换,编码转换未实现）
local function process_resp_body(ctx, resp_body)
    local req_info = ctx.req_info
    local protocol_info = req_info.protocol_info
    local service_info = req_info.service_info
    if not service_info then
        core.log.info("系统未调用后端服务,服务信息使用默认值,用于解析响应报文")
        service_info = {
            ENCODING = "UTF-8";
            FORMAT = "JSON"
        }
    end
    local last_service_encoding = service_info.ENCODING
    -- 获取响应模板
    local resp_template_info, err = query_template.get_template_info(
                                        protocol_info[query_template.TEMPLATE_TYPE_RESP])
    if not resp_template_info then
        core.log.error("获取响应模板失败,", err)
        return nil, err
    end
    -- 执行响应模板
    emergency_log.g_log(ctx,"执行响应模板")

    if ctx.req_info.is_process_template then
        last_service_encoding = "UTF-8"
    end

    emergency_log.g_log(ctx,"process_code:",req_info.sys.process_code,
                        ",template_name:",resp_template_info.template_name,
                        ",version_code:",resp_template_info.version_code,
                        ",resp_body:",resp_body,
                        ",encoding:",last_service_encoding)

    local exe_out, err_tab = template_exec.sfdl_exec(ctx,
                                req_info.sys.process_code,
                                resp_template_info.content,
                                resp_template_info.template_name,
                                resp_template_info.version_code,resp_body,last_service_encoding)
    if not exe_out then
        core.log.error("响应模板执行失败:" .. err_tab.msg)
        return nil, err_tab.msg
    end
    emergency_log.g_log(ctx,"执行响应模板成功......")
    emergency_log.g_log(ctx,"响应模板输出报文:",exe_out.body)
    return json_decode(exe_out.body)
end

local function print_log(ctx)
    core.log.warn("客户端请求头:",core.json.delay_encode(ngx.req.get_headers()))
    core.log.warn("客户端请求体:",ctx.req_info.raw_req_body)
    core.log.warn("服务端响应头:",core.json.delay_encode(ctx.req_info.svc_resp_header))
    core.log.warn("服务端响应体:",ctx.req_info.ab_resp_body)
    core.log.warn("网关响应头:",core.json.delay_encode(ngx.resp.get_headers()))
end

function _M.invoke(conf,ctx)
    core.log.info("能力调用返回状态码:",ngx.status)
    local req_info = ctx.req_info
    local resp_body = req_info.ab_resp_body or ""
    if ngx.status == 404 then
        core.log.error("未注册能力:",req_info.sys.process_code)
        exception.throw(req_info, exception.type.EXCEPT_REQUEST,
                        exception.code.DAG_ERR_ROUTE_UNREGISTER,
                        "【NY】未注册该能力:" .. req_info.sys.process_code)
    elseif ngx.status == 500 then
        core.log.error("系统未知错误")
        exception.throw(req_info, exception.type.EXCEPT_DAG,
                        exception.code.DAG_ERR_UNKNOWN, "【NY】系统错误")
    end
    core.log.info("ex_class:",req_info.sys.ex_class)
    core.log.info("ex_code:",req_info.sys.ex_code)
    core.log.info("ex_msg:",req_info.sys.ex_msg)
    emergency_log.g_log(ctx,"响应模板输入报文:",resp_body)
    local resp_tab, err
    if not req_info.is_sys_err and req_info.sys.ex_class==nil then
        -- 执行响应模板
        resp_tab, err = process_resp_body(ctx, resp_body)
        -- 打印sys系统参数
        emergency_log.sys_log(ctx)
        if not resp_tab then
            core.log.error("响应模板执行错误:", err)
            
            exception.throw(req_info, exception.type.EXCEPT_DAG,
                            exception.code.DAG_ERR_SERVICE_ERR, err)
        end
    end
    if req_info.is_sys_err == true or req_info.sys.ex_class then
        -- 执行异常模板
        resp_tab, err = exception_catch(ctx, resp_body)
        if not resp_body then
            core.log.error("异常模板执行错误:", err)
            return -- TODO 异常模板处理失败的情况
        end
    end
    -- 如果请求未调用能力，直接生成响应报文
    if not req_info.ability_route_flag then
        core.log.info("客户端报文格式:", req_info.app_format)
        core.log.info("客户端报文编码:",req_info.app_encoding)
        -- 未成功调用服务，系统默认编码为UTF-8
        local dag_resp_body= convert_util.tab_to_body(resp_tab, "UTF-8",
                                              req_info.app_encoding or "UTF-8",
                                              req_info.app_format or "XML")
        req_info.dag_resp_body = dag_resp_body
        ngx.header["Content-Length"]=#dag_resp_body
        ngx.header["Transfer-Encoding"]=nil
    end
    req_info.resp_tab = resp_tab
    local req_info=ctx.req_info
    -- 应用默认格式XML
    req_info.app_format=req_info.sys.dag_resp_format or req_info.app_format or "XML"
    -- 应用与客户端请求编码一致，若模板变量sys.dag_resp_encoding有配置值，以这个值为准，若都为空默认UTF-8
    req_info.app_encoding=req_info.sys.dag_resp_encoding or req_info.app_encoding or "UTF-8"
    local format=ctx.req_info.app_format
    if format=="json" or format == "JSON" then
        ngx.header["Content-Type"]="application/json;charset="..upper_str(req_info.app_encoding)
    elseif format=="xml" or format == "XML" then
        ngx.header["Content-Type"]="text/xml;charset="..upper_str(req_info.app_encoding)
    end

    -- print_log(ctx)
end

return _M