local sw_tracer = require("skywalking.tracer")
local core = require("apisix.core")
local process = require("ngx.process")
local ngx = ngx
local math = math
local require = require

local plugin_name="sw-prefix"

local schema = {
    type = "object",
    properties = {
        sample_ratio = {
            type = "number",
            minimum = 0.00001,
            maximum = 1,
            default = 1
        }
    },
    additionalProperties = false,
}

local _M = {
    version = 0.1,
    priority = 10000, -- last running plugin, but before serverless post func
    name = plugin_name,
    schema = schema,
}

function _M.check_schema(conf)
    return core.schema.check(schema, conf)
end

function _M.rewrite(conf, ctx)
    ctx.aoc_sw_flag = true
end

function _M.log(conf,ctx)
    if not ctx.aoc_sw_flag then
        return
    end
    sw_tracer:prepareForReport()
end

function _M.ability_start(ctx)
    if not ctx.aoc_sw_flag then
        return
    end
    return sw_tracer:start("upstream service")
end

function _M.set_ability_code(ctx,ability_code)
    if not ctx.aoc_sw_flag then
        return
    end
    return sw_tracer:set_operation_name(ability_code)
end

function _M.ability_finish(ctx)
    if not ctx.aoc_sw_flag then
        return
    end
    return sw_tracer:finish()
end

function _M.service_start(ctx,service_info)
    if not ctx.aoc_sw_flag then
        return
    end
    return sw_tracer:service_start(service_info)
end

function _M.service_finish(ctx,http_status)
    if not ctx.aoc_sw_flag then
        return
    end
    return sw_tracer:service_finish(http_status)
end

return _M