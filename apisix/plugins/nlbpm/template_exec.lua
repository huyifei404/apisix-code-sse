local core = require("apisix.core")
local nlbpm_util = require("apisix.plugins.nlbpm.nlbpm_util")
local service_call = require("apisix.plugins.ability-route.service_call")
local ngx = ngx
local get_header_tab = ngx.req.get_headers
local json_encode = core.json.encode
local json_decode = core.json.decode
local sys_build=require("apisix.plugins.nlbpm.sys")
local ffi = require("ffi")
local clone_tab = core.table.clone
local pairs = pairs

local _M = {version = 0.1}

-- ========================私有方法==============================
-- @param ctx table: apisix上下文
---@param template_content string: 模板内容
---@param template_name string: 模板名称（ID)
---@param version_code number: 模板版本号
---@param in_body string: 模板输入报文
---@param encoding string: 输入报文的编码(可选GBK/UTF-8)
local function invoke(ctx, process_code,template_type, template_content, template_name,
                      version_code, in_body, encoding)
    local req_info = ctx.req_info
    -- 释放旧session,获取sys
    sys_build.release_session(req_info.sys)
    local in_sys = nlbpm_util.release(req_info.session, false)
    req_info.session = nil

    -- 声明异常信息缓存
    local error_msg = ffi.new("char[1024]")
    -- 解析模板
    core.log.info("解析模板")
    local parse_out, err_tab = nlbpm_util.parse_template(template_type,
                                                         template_name,
                                                         version_code,
                                                         template_content,
                                                         in_sys,
                                                         error_msg)
    if not parse_out then
        return nil, err_tab
    end
    if in_sys==nil then
        nlbpm_util.set_sys_val(parse_out.session,"___ballase__","")
    end
    core.log.info("xxxxxxxxxxxxxx解析模板完成xxxxxxx")
    -- 新的session存入上下文
    local session = parse_out.session
    req_info.session = session
    sys_build.set_session(req_info.sys,session)

    -- 将上下文数据同步到session
    nlbpm_util.sync_session(ctx)

    -- 配置模板服务
    core.log.info("配置模板服务信息")
    local ok, err_tab = nlbpm_util.set_service_task(session,
                                                    parse_out.service_ctx,
                                                    parse_out.size, error_msg)
    if not ok then
        return nil, err_tab
    end

    -- 获取请求header_tab
    local header_tab = ngx.req.get_headers(nil,req_info.sys.transfer_raw_header == "1")
    -- 首次执行模板
    core.log.info("首次执行模板")
    core.log.info("执行模板输入的请求头:",core.json.delay_encode(header_tab))
    local exe_out, err_tab = nlbpm_util.execute(process_code,session, in_body,
                                                encoding, json_encode(header_tab), error_msg)
    if not exe_out then
        return nil, err_tab
    end
    if exe_out.ret == nlbpm_util.CTL_END then
        return exe_out
    end

    local base_num = 1
    local separator = "."
    local call_num = 0
    while (true) do
        core.log.info("service_name:",exe_out.service_name)
        -- 头部参数注入
        local req_headers = clone_tab(header_tab)
        local service_header = json_decode(exe_out.headers)
        for k,v in pairs(service_header) do
            req_headers[k] = v
        end
        call_num = call_num + 1
        local span_node = tostring(base_num) .. separator .. tostring(call_num)
        -- 调用服务
        local res, err_tab = service_call.template_call(req_info,
                                                        exe_out.service_name,
                                                        span_node,
                                                        req_info.sys.app_id,
                                                        req_info.sys.route_value,
                                                        exe_out.body, req_headers,ctx)
        if not res then
            return nil, err_tab
        end

        -- 模板循环执行
        core.log.info("重复执行模板")
        exe_out, err_tab = nlbpm_util.resume_execute(process_code,session, res.body,
                                                     exe_out.service_id,
                                                     json_encode(res.header), error_msg)
        if not exe_out then
            return nil, err_tab
        end
        
        if exe_out.ret == nlbpm_util.CTL_END then
            return exe_out
        end
    end
end

-- ========================模块方法=============================
-- 执行sfdl模板
function _M.sfdl_exec(ctx, process_code,template_content, template_name, version_code,in_body, encoding)
    return invoke(ctx, process_code,nlbpm_util.TEMPLATE_TYPE_SFDL, template_content,
                  template_name, version_code, in_body, encoding)
end

-- 执行bpmn模板
function _M.bpmn_exec(ctx, process_code,template_content, template_name, version_code,in_body, encoding)
    return invoke(ctx, process_code,nlbpm_util.TEMPLATE_TYPE_BPMN, template_content,
                  template_name, version_code, in_body, encoding)
end

return _M
