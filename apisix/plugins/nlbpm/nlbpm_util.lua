local ffi = require("ffi")
local core = require("apisix.core")
local bpm = ffi.load("exnlbpm")
local service_query = require(
                          "apisix.plugins.dag-datasource.query_process.service_query")
local exception = require("apisix.plugins.exception")
local read_conf_util = require("apisix.plugins.utils.read_conf_util")
local new_tab=require("table.new")

local _M = {version = 0.1}

-- ==========================常量定义===================================
_M.CTL_BREAK = 1 -- 服务调用中断跳出
_M.CTL_END = 2 -- 模板执行结束

_M.TEMPLATE_TYPE_BPMN = 1;
_M.TEMPLATE_TYPE_SFDL = 2;

-- ==========================FFI定义=====================================
ffi.cdef [[
    struct Service_Context
    {
        int pluginType;
        char dataformatName[32 + 1];
        char encoding[16 + 1];
        char serviceName[64 + 1];
    };
    int bpm_init(const char * cfgContext, char * errorMsg);
    int bpm_getServiceTask(void * inSys, int templateType, const char * templateName, int versionCode, const char * templateXml, void ** session, struct Service_Context ** retService, int * size, char * errorMsg);
    int bpm_setServiceTask(void * session, struct Service_Context ** retService, int size, char * errorMsg);
    int bpm_execute(void * session, const char * startRequest, const char * startRequestEncoding, const char * headerMsg, char * curServiceId, char * curServiceName,char** reqHeaders, char **request, char * errorMsg);
    int bpm_resumeExecute(void * session, const char *response, const char * preServiceId, const char * headerMsg, char * curServiceId, char * curServiceName, char** reqHeaders, char ** request, char * errorMsg);
    int bpm_terminateExecute(void * session, bool releaseSys, void ** outSys, char * errorMsg);
    int bpm_getSysValue(void * session, const char * key, char * retValue, int * valueLength, char * errorMsg);
    int bpm_setSysValue(void * session, const char * key, const char * value, char * errorMsg);
]]

-- ===========================初始化=======================================
do
    local init = function()
        local bpmn_cfg = read_conf_util.get_conf("bpmn")
        core.log.warn("bpmn_cfg:", core.json.delay_encode(bpmn_cfg))
        local cfg_str = core.json.encode(bpmn_cfg)
        local error_msg = ffi.new("char[1024]")
        local ret = bpm.bpm_init(cfg_str, error_msg)
        if ret ~= 0 then
            core.log.error("模板执行引擎初始化错误:",
                           ffi.string(error_msg))
        end
    end
    if read_conf_util.get_conf("ffi_enable") == 1 then init() end
end

-- ===============================模块方法===================================
-- 获取模板上下文sys变量
-- @param session cdata: 模板session
-- @param key string: sys的key
-- @return string,string: 返回指定的变量值,错误返回nil和错误信息
function _M.get_sys_val(session, key)
    local ret_value = ffi.new("char[256]") -- TODO:报文长度超出有概率导致进程退出
    local val_len_ref = ffi.new("int[1]")
    val_len_ref[0] = 256
    local error_msg = ffi.new("char[256]")
    local ret = bpm.bpm_getSysValue(session, key, ret_value, val_len_ref, error_msg)
    if ret == 0 then
        local val = ffi.string(ret_value)
        if #val == 0 then
            return nil
        else
            return val
        end
    else
        if val_len_ref[0] ~= 256 then
            val_len_ref[0] = val_len_ref[0] + 1
            ret_value = ffi.new("char[?]",val_len_ref[0])
            ret = bpm.bpm_getSysValue(session, key, ret_value, val_len_ref, error_msg)
            if ret == 0 then
                local val = ffi.string(ret_value)
                if #val == 0 then
                    return nil
                else
                    return val
                end
            end
        end
        core.log.error("获取sys数据失败:",ffi.string(error_msg))
        return nil
    end
end

-- 配置模板sys变量
-- @param session cdata: 模板session
-- @param key string: key
-- @param value string: value
-- @return boolean,string: 配置成功返回true,否则返回nil和错误信息
function _M.set_sys_val(session, key, value)
    local error_msg = ffi.new("char[256]")
    local ret = bpm.bpm_setSysValue(session, key, value, error_msg)
    if ret == 0 then
        return true
    else
        core.log.error("配置sys数据失败:",ffi.string(error_msg))
        return nil
    end
end

-- int bpm_getServiceTask(int templateType, const char * templateName, int versionCode, const char * templateXml, void ** session, struct Service_Context ** retService, int & size, char * errorMsg);

-- 解析模板，返回session,service_ctx,size,错误返回nil,err
-- @param type string: 解析的模板类型,1 BPMN, 2 SFDL
-- @param template_name string: 模板名称（ID）
-- @param version_code number: 模板版本号，根据版本号更新缓存
-- @param template_content string: 模板内容
-- @param in_sys cdata: session中的sys
-- @param error_msg cdata: 异常信息
-- @return out_info table: 包含session(cdata),service_ctx(cdata),size(number)
-- @return err string: 异常信息，当返回异常信息时，out_info为nil
function _M.parse_template(type, template_name,version_code, template_content, in_sys, error_msg)
    local session_ref = ffi.new("void*[1]")
    local service_ctx_ref = ffi.new("struct Service_Context*[1]")
    local size_ref = ffi.new("int[1]")
    local ret = bpm.bpm_getServiceTask(in_sys,type,template_name,version_code, template_content, session_ref,
                                       service_ctx_ref, size_ref, error_msg)
    if ret == 0 then
        local out_info=new_tab(0,3)
        out_info.session=session_ref[0]
        out_info.service_ctx=service_ctx_ref
        out_info.size=size_ref[0]
        return out_info
    else
        local err="【NY】模板配置错误，导致解析失败:".. ffi.string(error_msg)
        core.log.error(err ..",模板内容:" .. template_content)
        return nil, exception.build_err_tab(exception.type.EXCEPT_DAG,
                                            exception.code.DAG_ERR_TEMPLATE_PARSE_ERR, 
                                            err)
    end
end

-- 配置模板服务信息,成功返回true,失败返回nil,err
function _M.set_service_task(session, service_ctx, size, error_msg)
    local ret
    if size == 0 then
        ret = bpm.bpm_setServiceTask(session, service_ctx, size, error_msg)
    else
        -- 根据服务名查询服务信息
        local service_arr = service_ctx[0]

        local cur_service_code, ok, err = service_query.set_service_info(service_arr, size)
        if not ok then
            bpm.bpm_setServiceTask(session, service_ctx, 0, error_msg)
            core.log.error("模板服务信息配置错误:", err)

            return nil, exception.build_err_tab(exception.type.EXCEPT_DAG,
                            exception.code.DAG_ERR_TEMPLATE_QUREY_SERVICE_ERR, 
                            "【NY】模板服务信息配置错误,"..cur_service_code.."服务信息查询失败:" .. err)
        end
        ret = bpm.bpm_setServiceTask(session, service_ctx, size, error_msg)
    end
    if ret ~= 0 then
        local err="【NY】会话初始化错误:".. ffi.string(error_msg)
        core.log.error(err)
        return nil, exception.build_err_tab(exception.type.EXCEPT_DAG,
                                            exception.code.DAG_ERR_TEMPLATE_CONFIG_SERVICE_ERR, err)
    end
    return true
end

-- 执行模板
-- @param session cdata: 模板session
-- @param in_body_str string: 模板输入报文
-- @param encoding string: 输入报文的编码，可选GBK/UTF-8
-- @param header_msg string: 请求header的json字符串
-- @param error_msg cdata: 异常信息存储
-- @return table out_info: 包含ret,body,service_id,service_name
-- @return table err_tab: 错误信息，table中包含err_type,err_code,err_msg(当返回err_tab时out_info为nil)
function _M.execute(process_code,session, in_body_str, encoding, header_msg, error_msg)
    local cur_service_id = ffi.new("char[65]")
    local cur_service_name = ffi.new("char[65]")
    local out_headers = ffi.new("char*[1]")
    local out_body = ffi.new("char*[1]")
    local ret = bpm.bpm_execute(session, in_body_str, encoding,
                                header_msg, cur_service_id, cur_service_name,
                                out_headers,out_body, error_msg)
    if ret == _M.CTL_END then
        -- if _M.get_sys_val(session,"ex_class") then
        --     local ex_class = _M.get_sys_val(session,"ex_class")
        --     local ex_code = _M.get_sys_val(session,"ex_code")
        --     local ex_msg = _M.get_sys_val(session,"ex_msg")
        --     core.log.error("模型执行返回业务错误:",ex_msg)
        --     return nil,exception.build_err_tab(ex_class,ex_code,ex_msg)
        -- end
        return {ret = ret, body = ffi.string(out_body[0]),headers = ffi.string(out_headers[0])}
    elseif ret == _M.CTL_BREAK then
        return {
            ret = ret,
            headers = ffi.string(out_headers[0]),
            body = ffi.string(out_body[0]),
            service_id = ffi.string(cur_service_id),
            service_name = ffi.string(cur_service_name)
        }
    else
        -- 异常
        local ability_code
        if process_code == nil then
            ability_code = ""
        else
            ability_code = process_code
        end

        local service_name = ffi.string(cur_service_name)

        local err = "【NY】" .. ability_code .. "能力编排执行错误,"
        if service_name ~=nil and #service_name>0 then
            err = err ..ffi.string(cur_service_name).."服务无"..ffi.string(cur_service_id).."节点,"
        end
        err = err .. ffi.string(error_msg)
        
        core.log.error(err)
        return nil, exception.build_err_tab(exception.type.EXCEPT_DAG,
                                            exception.code.DAG_ERR_TEMPLATE_EXC_ERR,
                                            err)
    end
end

-- 模板服务调用后重复执行
-- @param session cdata: 模板session
-- @param in_body_str string: 服务调用后返回的报文作为模板输入报文
-- @param service_id string: 当前调用的服务id
-- @param header_msg string: 请求header的json字符串
-- @param error_msg cdata: 异常信息
-- @return table out_info: 包含ret,body,service_id,service_name
-- @return table err_tab: 错误信息，err_tab中包含type,code,msg(当返回err_tab时out_info为nil)
function _M.resume_execute(process_code,session, in_body_str, service_id, header_msg,
                           error_msg)
    local cur_service_id = ffi.new("char[65]")
    local cur_service_name = ffi.new("char[65]")
    local out_headers = ffi.new("char*[1]")
    local out_body = ffi.new("char*[1]")
    local ret = bpm.bpm_resumeExecute(session, in_body_str, service_id, header_msg,
                                cur_service_id, cur_service_name, out_headers, out_body,
                                error_msg)
    if ret == _M.CTL_END then
        -- if _M.get_sys_val(session,"ex_class") then
        --     local ex_class = _M.get_sys_val(session,"ex_class")
        --     local ex_code = _M.get_sys_val(session,"ex_code")
        --     local ex_msg = _M.get_sys_val(session,"ex_msg")
        --     core.log.error("模板执行返回业务错误:",ex_msg)
        --     return nil,exception.build_err_tab(ex_class,ex_code,ex_msg)
        -- end
        return {
            ret = ret,
            body = ffi.string(out_body[0]),
            headers = ffi.string(out_headers[0])
        }
    elseif ret == _M.CTL_BREAK then
        return {
            ret = ret,
            headers = ffi.string(out_headers[0]),
            body = ffi.string(out_body[0]),
            service_id = ffi.string(cur_service_id),
            service_name = ffi.string(cur_service_name)
        }
    else
        -- 异常
        local ability_code
        if process_code == nil then
            ability_code = ""
        else
            ability_code = process_code
        end

        local err = "【NY】" .. ability_code .. "能力编排执行错误,"..service_id.."服务,".. ffi.string(error_msg)

        core.log.error(err)
        return nil, exception.build_err_tab(exception.type.EXCEPT_DAG,
                                            exception.code.DAG_ERR_TEMPLATE_EXC_ERR, 
                                            err)
    end
end

function _M.ss_release(session,error_msg)
    local out_sys_ref = ffi.new("void*[1]")
    return bpm.bpm_terminateExecute(session,true,out_sys_ref,error_msg)
end

function _M.release(session, release_sys)
    if not session then return end
    local error_msg = ffi.new("char[256]")
    local out_sys_ref = ffi.new("void*[1]")
    local ret = bpm.bpm_terminateExecute(session, release_sys, out_sys_ref,
                                         error_msg);
    if ret == 0 then
        return out_sys_ref[0]
    else
        core.log.error("内存释放错误:", ffi.string(error_msg))
        return nil, ffi.string(error_msg)
    end
end

function _M.finally_release(ctx)
    local session = ctx.req_info.session
    if session then
        _M.release(session, true)
        ctx.req_info.session=nil
    end
    
end

-- 将session数据同步到sys
function _M.sync_sys(ctx)
    local session = ctx.req_info.session
    if ctx.req_info.session then
        local sys = ctx.req_info.sys or {}
        sys.process_code = _M.get_sys_val(session, "process_code")
        sys.app_id = _M.get_sys_val(session, "app_id")
        sys.route_type = _M.get_sys_val(session, "route_type")
        sys.route_value = _M.get_sys_val(session, "route_value")
        local access_token = _M.get_sys_val(session, "access_token")
        if access_token and #access_token ~= 0 then
            sys.access_token = access_token
        end
        ctx.req_info.sys = sys
    else
        return nil, "上下文不存在session"
    end
end

-- 将sys数据同步到session
function _M.sync_session(ctx)
    local session = ctx.req_info.session
    if ctx.req_info.session then
        local sys = ctx.req_info.sys or {}
        if sys.es_flag then
            _M.set_sys_val(session, "es_flag", tostring(sys.es_flag))
        end
        if sys.ex_class then
            _M.set_sys_val(session, "ex_class", tostring(sys.ex_class))
            _M.set_sys_val(session, "ex_code", tostring(sys.ex_code))
            _M.set_sys_val(session, "ex_msg", tostring(sys.ex_msg))
        end
    else
        return nil, "上下文不存在session"
    end
end

return _M
