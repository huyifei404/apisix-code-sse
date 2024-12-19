local sw_tracer = require("skywalking.tracer")
local core = require("apisix.core")
local process = require("ngx.process")
local ngx = ngx
local math = math
local require = require

local plugin_name="sw-prefix"

local schema = {
    type = "object",
    additionalProperties = false,
}

local _M = {
    version = 0.1,
    priority = -1100, -- last running plugin, but before serverless post func
    name = plugin_name,
    schema = schema,
}

function _M.check_schema(conf)
    return core.schema.check(schema, conf)
end

-- function _M.body_filter(conf, ctx)
--     -- if ctx.skywalking_sample and ngx.arg[2] then
--     if ctx.skywalking_sample then
--         sw_tracer:finish()
--         core.log.info("tracer finish")
--     end
--     -- local spans=ngx.ctx.tracingContext.internal.finished_spans
--     -- spans[1].operation_name=ngx.var.uri
--     -- spans[1].owner.internal.first_span.operation_name=ngx.var.uri
-- end


-- function _M.log(conf, ctx)
--     if ctx.skywalking_sample then
--         sw_tracer:prepareForReport()
--         core.log.info("tracer prepare for report")
--     end
-- end

return _M