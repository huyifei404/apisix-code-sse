local core                  = require("apisix.core")
local pack_tab              = table.pack
local unpack_tab            = table.unpack
local concat_tab            = table.concat
local pairs                 = pairs
local log_crit             = core.log.crit
local json_encode           = core.json.encode

-- =================开关配置================
local emergency_log_switch = false
-- =========================================

local plugin_name = "emergency-log"

local schema = {
    type = "object",
    properties = {
        enable = {
            type = "boolean",
            default = false
        }
    }
}

local _M = {
    name = plugin_name,
    schema= schema,
    priority = 10000,
    version = 0.1
}

function _M.check_schema(conf)
    local ok, err = core.schema.check(schema, conf)
    if not ok then
        return false, err
    end
    emergency_log_switch = conf.enable
    if emergency_log_switch == true then
        core.log.warn("debug日志开关: ON")
    else
        core.log.warn("debug日志开关: OFF")
    end
    return true
end

function _M.check_enable(ctx)
    ctx.emergency_log_flag = emergency_log_switch
end

function _M.g_log(ctx, ...)
    if ctx.emergency_log_flag then
        log_crit("请求id:",ctx.req_id,",",...)
    end
end

function _M.sys_log(ctx)
    if ctx.emergency_log_flag then
        local sys = ctx.req_info.sys
        log_crit("请求id:",ctx.req_id,",sys.process_code:",sys.process_code)
        log_crit("请求id:",ctx.req_id,",sys.app_id:",sys.app_id)
        log_crit("请求id:",ctx.req_id,",sys.city_id:",sys.city_id)
        log_crit("请求id:",ctx.req_id,",sys.ex_class:",sys.ex_class)
        log_crit("请求id:",ctx.req_id,",sys.ex_code:",sys.ex_code)
        log_crit("请求id:",ctx.req_id,",sys.ex_msg:",sys.ex_msg)
        log_crit("请求id:",ctx.req_id,",sys.dag_resp_encoding:",sys.dag_resp_encoding)
        log_crit("请求id:",ctx.req_id,",sys.transfer_raw_body:",sys.transfer_raw_body)
    end
end


return _M