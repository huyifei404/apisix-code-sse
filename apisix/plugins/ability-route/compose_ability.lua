local core                  = require("apisix.core")
local service_call          = require("apisix.plugins.ability-route.service_call")
local template_query        = require("apisix.plugins.dag-datasource.query_process.template_query")
local exception             = require("apisix.plugins.exception")
local template_exec         = require("apisix.plugins.nlbpm.template_exec")
local json_encode           = core.json.encode
local log                   = core.log
local ngx                   = ngx
local emergency_log         = require("apisix.plugins.emergency-log")
-- 编排能力调用
local _M = {}

function _M.ability_call(ctx, conf)
    -- 根据模板id查找模板
    local req_info = ctx.req_info
    local template_id = conf.template_id
    local process_template, err = template_query.get_template_info(template_id)
    if not process_template then
        return exception.throw(ctx.req_info, exception.type.EXCEPT_DAG,
                               exception.code.DAG_ERR_TEMPLATE_NOT_FOUND_TPLID, err)
    end
    local in_body=json_encode(ctx.req_info.req_tab)
    -- 执行编排模板，获取返回的body
    emergency_log.g_log(ctx,"请求id:",ctx.req_id,",开始执行编排模板......")
    emergency_log.g_log(ctx,"编排模板输入报文:",in_body)
    local exe_out, err_tab = template_exec.bpmn_exec(ctx,
                                                      req_info.sys.process_code,
                                                      process_template.content,
                                                      process_template.template_name,
                                                      process_template.version_code,
                                                      in_body,"UTF-8")
    if not exe_out then
        log.error("编排能力调用失败:",err_tab.msg)
        log.error("外围请求方法:",ngx.req.get_method())
        log.error("外围请求报文:",core.request.get_body())
        return exception.throw(req_info, err_tab.type, err_tab.code,
                               err_tab.msg)
    end
    -- 打印sys系统参数
    emergency_log.sys_log(ctx)
    if req_info.sys.ex_class then
        local ex_class = req_info.sys.ex_class
        local ex_code = req_info.sys.ex_code or ""
        local ex_msg = req_info.sys.ex_msg or ""
        core.log.error("编排模板返回业务错误:",ex_msg)
        return exception.throw(req_info, ex_class, ex_code, ex_msg,nil,true)
    end
    emergency_log.g_log(ctx,"请求id:",ctx.req_id,",执行编排模板成功......")
    return 200,exe_out.body
end

return _M