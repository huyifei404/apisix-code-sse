local core                      = require("apisix.core")
local ngx                       = ngx
local failed_req_record         = require("apisix.plugins.failed-req-record")
local emergency_log             = require("apisix.plugins.emergency-log").g_log
local sw8                       = require("apisix.plugins.sw-prefix")

local _M = {}

-- ==================================私有方法=====================================
-- 响应报文处理（执行响应模板，格式转换,编码转换未实现）

-- ===============================模块方法=========================================
function _M.invoke(conf, ctx)
    -- local body=ctx.req_info.dag_resp_body or "系统错误，无法正常处理"
    local body=ctx.req_info.dag_resp_body
    if body then
        if ngx.status == 200 then
            failed_req_record.delete_req_record(ctx)
        end
    else
        body = "系统错误，无法正常处理"
    end
    ngx.arg[1] = body
    ngx.arg[2] = true
    emergency_log(ctx,"外围响应报文:",ctx.req_info.dag_resp_body)
    sw8.ability_finish(ctx)
end

return _M
