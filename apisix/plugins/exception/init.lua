local core=require("apisix.core")
local tostring=tostring
local error_type=require("apisix.plugins.exception.type")
local error_core=require("apisix.plugins.exception.code")
local new_tab=require("table.new")
local status_mapping=require("apisix.plugins.exception.status_mapping")
local ngx=ngx


local _M={
    version=0.1,
    type=error_type,
    code=error_core
}

-- ===================================模块方法===================================
-- 抛出异常，在body_filter阶段处理
-- param req_info: 上下文，即ctx.req_info
-- param err_type: 异常类型，参考apisix.plugins.exception.type
-- param err_code: 错误码，参考apisix.plugins.exception.code
-- param err_msg: 错误描述
-- param status: 配置响应码--在响应阶段该属性无效，默认200
-- return: 返回状态码和空字符串
function _M.throw(req_info,err_type,err_code,err_msg,status,is_business_err)
    if not is_business_err then
        -- 非业务错误处理
        req_info.is_err_request=true
        ngx.header["aoc-err-flag"] = 1
    end
    status=status or 200
    -- 向全局变量ngx中添加sw_status
    ngx.ctx.sw_status = status_mapping[err_code] or 500
    req_info.is_sys_err=true
    local sys=req_info.sys or {}
    sys.ex_class=tostring(err_type)
    sys.ex_code=tostring(err_code)
    sys.ex_msg=tostring(err_msg)
    req_info.sys=sys
    return status,""
end

function _M.build_err_tab(type, code, msg)
    local err_tab = new_tab(0, 3)
    err_tab.type = type
    err_tab.code = code
    err_tab.msg = msg
    return err_tab
end

return _M