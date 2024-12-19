local core=require("apisix.core")
local tostring=tostring
local template_query=require("apisix.plugins.dag-datasource.query_process.template_query")
local sfdl_builder=require("apisix.plugins.sfdl.element.builder")
local ngx=ngx
local io_open=io.open
local read_conf_util=require("apisix.plugins.utils.read_conf_util")
local apisix_home = (ngx and ngx.config.prefix()) or ""
local template_exec = require("apisix.plugins.nlbpm.template_exec")
local json_decode=core.json.decode
local new_tab=require("table.new")
local log = core.log

local _M={
    version=0.1,
}

local default_template=nil
-- ===================================私有方法===================================
local function get_template_file_path(file_name)
    local file_path = apisix_home .. "apisix/plugins/exception/" .. file_name
    return file_path .. ".sfdl"
end

local function read_file(path)
    local file, err = io_open(path, "rb")   -- read as binary mode
    if not file then
        core.log.error("failed to read config file:" .. path, ", error info:", err)
        return nil, err
    end

    local content = file:read("*a") -- `*a` reads the whole file
    file:close()
    return content
end
-- =================================初始化================================
local flag=true
if read_conf_util.get_conf("ffi_enable") == 0 then
    flag=false
end
-- 获取默认异常处理模板
do
    -- 获取默认模板的文本内容
    local content,err=read_file(get_template_file_path("default_error"))
    if content then
        default_template=content
        if not default_template then
            core.log.error("异常默认处理模板解析失败:",err)
        end
    end
end

--获取错误默认返回flag和固定的错误返回
local function get_err_template()
    local err_default_format = "XML"
    local err_default_flag = false
    local err_default_content = nil

    local local_conf = core.config.local_conf()
    local err_default_attrs = core.table.try_read_attr(local_conf, "err_default")
    if err_default_attrs then
        err_default_flag = err_default_attrs.flag
        err_default_format = err_default_attrs.format
        err_default_content = err_default_attrs.default
    end
    return err_default_flag,err_default_format,err_default_content
end

-- ===================================模块方法===================================
-- 处理异常
function _M.invoke(ctx,body)
    local req_info=ctx.req_info
    -- 获取异常模板
    local err_template,err
    local protocol_info= req_info.protocol_info
    if protocol_info then
        err_template,err = template_query.get_template_info(protocol_info[template_query.TEMPLATE_TYPE_ERR]);
        if not err_template then
            core.log.error("获取异常模板失败:",err,",执行默认异常模板")
        end
    end
    if not err_template then
        -- 增加错误模板固定返回
        local err_default_flag,err_default_format,err_default_content = get_err_template()
        if err_default_flag then
            log.warn("使用配置的异常模板,要求返回的模板的format:",err_default_format,",content:",err_default_content)
            local json_parse_flag,default_json = json_decode(err_default_content);
            if not json_parse_flag then
                core.log.error("配置的异常模板解析失败:",err_default_content,",执行默认异常模板")
            else
                req_info.app_format = err_default_format
                return json_decode(err_default_content)
            end
        end
        err_template=new_tab(0,3)
        err_template.content=default_template
        err_template.template_name="default_err_template"
        err_template.version_code=1
    end
    if req_info.service_info then
        req_info.service_info.ENCODING="UTF-8"
    end
    log.warn("请求id:",ctx.req_id,"sys.ex_msg:",req_info.sys.ex_msg or "")
    -- local out_tab,_,err_tab=protocol_template_exec(ctx,err_template,"{}","JSON","UTF-8",req_info.sys,flag)
    log.warn("请求id:",ctx.req_id,",执行异常模板......")
    local exe_out, err_tab = template_exec.sfdl_exec(ctx,
                                req_info.sys.process_code,
                                err_template.content,
                                err_template.template_name,
                                err_template.version_code,"{}","UTF-8")
    if not exe_out then
        core.log.error("请求id:",ctx.req_id,",异常模板执行失败,",err_tab.msg,",执行默认异常模板")
        exe_out, err_tab = template_exec.sfdl_exec(ctx,
                                req_info.sys.process_code,
                                default_template,
                                "default_err_template",
                                1,"{}","UTF-8")
        if not exe_out then
            core.log.error("请求id:",ctx.req_id,",默认异常模板执行错误....",err_tab.msg)
            return {
                operation_out={
                    response={
                        resp_result=-17,
                        resp_code=99,
                        resp_desc="系统未知异常"
                    }
                }
            }
        end
    end
    return json_decode(exe_out.body)
end

return _M