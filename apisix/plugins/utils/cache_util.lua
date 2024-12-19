local core              = require("apisix.core")
local redis_util        = require("apisix.plugins.utils.redis_util")
local read_conf_util    = require("apisix.plugins.utils.read_conf_util")
local ngx               = ngx
local ipairs            = ipairs
local pairs             = pairs
local new_tab           = require("table.new")
local pack_table        = table.pack
local concat_table      = table.concat
local clone_tab         = core.table.clone
local lru_new           = require("resty.lrucache").new

-- redis数据缓存工具
local _M = {
    version = 0.1,
}

-- 可缓存的方法枚举
_M.func_enum = {
    template_relation = {code = "template_relation",desc = "协议模板匹配信息"},
    service_detail_info = {code = "service_detail_info",desc = "服务详细信息"},
    service_base_info = {code = "service_base_info",desc = "服务基础信息"},
    gray_route = {code = "gray_route",desc = "服务灰度信息"},
    developer_app = {code = "developer_app",desc = "开发者信息"},
    service_path_concat = {code = "service_path_concat",desc = "服务path拼接开关配置"},
    gray_flag_conf = {code = "gray_flag_conf",desc = "灰度flag配置"},
    gray_group = {code = "gray_group",desc = "灰度路由组"},
    dubbo_group_address = {code = "dubbo_group_address",desc = "DUBBO服务组地址"},
    dubbo_city_group = {code = "dubbo_city_group",desc = "DUBBO地市映射"},
}

-- =====================初始化加载配置文件=======================

local cache_conf
local all_allow_flag = false
do
    cache_conf = read_conf_util.get_conf("redis_cache_config")
    if type(cache_conf) ~= "table" then
        cache_conf = {}
    end
    cache_conf.max_cache_count = cache_conf.max_cache_count or 2000
    cache_conf.ttl = cache_conf.ttl or 30
    if type(cache_conf.allow_funcs) ~= "table" then
        cache_conf.allow_funcs = {}
    end
    local hash = new_tab(0,#cache_conf.allow_funcs)
    for _,v in ipairs(cache_conf.allow_funcs) do
        if v == "all" then
            all_allow_flag = true
            break
        end
        if _M.func_enum[v] == nil then
            core.log.error("不支持该方法的缓存:",v)
        else
            hash[v] = true
        end
    end
    core.log.warn("redis_cache_config:",core.json.delay_encode(cache_conf))
    cache_conf.allow_funcs_hash = hash
end

local lrucache = core.lrucache.new({
    count = cache_conf.max_cache_count,
    ttl = cache_conf.ttl,
    invalid_stale = true
})

local function deep_clone(tab)
    local res_tab = clone_tab(tab)
    for k,v in pairs(tab) do
        if type(v) == "table" then
            res_tab[k] = deep_clone(v)
        end
    end
    return res_tab
end

local function create_obj_func(func_enum,query_function,...)
    core.log.info("从redis中查询:",func_enum.desc)
    local res,err = query_function(...)
    if res == nil and err == nil then
        res = ngx.null
    end
    return res,err
end

-- @param redis_key_code: redis key的模板编码，参考rediskey.yml
-- @param query_function: 数据查询方法
-- @param ... : 数据查询方法的参数，必须全部非空
function _M.fetch_data(func_enum,query_function,...)
    local func_code = func_enum.code
    local res,err
    if all_allow_flag or cache_conf.allow_funcs_hash[func_code] then
        local key = concat_table(pack_table(func_code,...),".")
        res,err = lrucache(key,nil,create_obj_func,func_enum,query_function,...)
        if res and type(res) == "table" then
            res = deep_clone(res)
        end
    else
        res,err = create_obj_func(func_enum,query_function,...)
    end
    if res == ngx.null then
        res = nil
    end
    return res,err
end


return _M
