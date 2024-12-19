local core                  = require("apisix.core")
local template_query        = require("apisix.plugins.dag-datasource.query_process.template_query")
local ngx                   = ngx
local nkeys                 = require("table.nkeys")
local pairs                 = pairs
local ipairs                = ipairs
local consumer              = require("apisix.consumer")
local trace_logger          = require("apisix.plugins.trace-logger")
local router                = require("apisix.router")

local breaker_dict          = ngx.shared["plugin-single-ability-breaker"]
local datamap_dict          = ngx.shared["shared-datamap"]
local prometheus_dict       = ngx.shared["prometheus-metrics"]
local failed_req_dict       = ngx.shared["failed-req-record"]

-- 各个模块缓存所占用内存的查询方法
local _M = {}

-- lua虚拟机占用内存
function _M.get_lua_memory()
    -- collectgarbage("collect")
    local memory = collectgarbage("count")
    return 200,{memory = memory}
end

-- 协议模板缓存
function _M.get_template_memory()
    local tab = template_query.get_data_and_versions()
    local versions = tab.versions
    local data = tab.data
    local size = 0
    if data then
        for _,v in pairs(data) do
            size = size + #v.CONTENT
        end
    end
    local result = {
        versions_number = versions and nkeys(versions) or "nil",
        data_number = data and nkeys(data) or "nil",
        used_memory = size
    }
    return 200,result
end

-- kafka日志缓存
function _M.get_kafka_log_memory()
    local entries = trace_logger.get_entries()
    local size = 0
    for _,v in ipairs(entries) do
        size = size + #v
    end
    return 200,{
        used_memory = size,
        number = #entries
    }
end

-- redis数据缓存


-- apisix实体缓存
function _M.get_consumers_memory()
    local values = consumer.consumers()
    local json = core.json.encode(values)
    local size = #json
    return 200,{
        number = #values,
        used_memory = size
    }
end

-- datamap数据缓存
function _M.get_datamap_memory()
    local capacity = datamap_dict:capacity()
    local free_space = datamap_dict:free_space()
    local tab = {
        capacity = capacity,
        free_space = free_space,
        used_memory = capacity - free_space
    }
    return 200,tab
end

-- prometheus数据缓存
function _M.get_prometheus_memory()
    local capacity = prometheus_dict:capacity()
    local free_space = prometheus_dict:free_space()
    local tab = {
        capacity = capacity,
        free_space = free_space,
        used_memory = capacity - free_space
    }
    return 200,tab
end

-- 失败请求记录数据缓存
function _M.get_failed_req_memory()
    local capacity = failed_req_dict:capacity()
    local free_space = failed_req_dict:free_space()
    local tab = {
        capacity = capacity,
        free_space = free_space,
        used_memory = capacity - free_space
    }
    return 200,tab
end

-- 熔断数据缓存
function _M.get_breaker_memory()
    local capacity = breaker_dict:capacity()
    local free_space = breaker_dict:free_space()
    local tab = {
        capacity = capacity,
        free_space = free_space,
        used_memory = capacity - free_space
    }
    return 200,tab
end

-- 全局配置缓存
function _M.get_global_rules_memory()
    local values = router.global_rules and router.global_rules.values or {}
    local json = core.json.encode(values)
    local size = #json
    return 200,{
        number = #values,
        used_memory = size
    }
end

-- 路由实体缓存查询
function _M.get_routes_memory()
    local values = router.http_routes()
    local json = core.json.encode(values)
    local size = #json
    return 200,{
        number = #values,
        used_memory = size
    }
end


return _M