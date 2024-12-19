
local core     = require("apisix.core")
local consumer = require("apisix.consumer")
local plugin_name = "app-service-auth"
local ipairs   = ipairs

local lrucache_plugin = core.lrucache.new({
    type = "plugin",
})

local schema = {
    type = "object",
}


local _M = {
    version = 0.1,
    priority = 5,
    type = 'auth',
    name = plugin_name,
    schema = schema,
}


local create_consume_cache
do
    local consumer_ids = {}

    function create_consume_cache(consumers)
        core.table.clear(consumer_ids)
        for _, consumer in ipairs(consumers.nodes) do
            core.log.info("consumer node: ", core.json.delay_encode(consumer))
            consumer_ids[consumer.username] = consumer
        end

        return consumer_ids
    end

end -- do

function _M.check_schema(conf)
    return core.schema.check(schema, conf)
end

-- 通过app_id+服务名查找consumer配置
-- @param app_id: 应用id
-- @param service_name: 服务名
-- @return plugins_conf: 应用+服务维度的插件配置
function _M.get_plugins_conf(app_id,service_name)
    local consumer_conf = consumer.plugin(plugin_name)
    if not consumer_conf then
        core.log.info("应用服务维度查询失败,没有应用+服务维度的配置,使用默认配置")
        return nil
    end
    local consumers = lrucache_plugin("consumers_key",
            consumer_conf.conf_version,
            create_consume_cache, consumer_conf)
    if consumers==nil then
        return nil
    end
    local key="as_" .. app_id .."_" .. service_name
    local app_service_con=consumers[key]
    return app_service_con and app_service_con.plugins
end

return _M
