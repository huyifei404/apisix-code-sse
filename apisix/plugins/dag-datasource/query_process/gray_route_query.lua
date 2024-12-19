local core              = require("apisix.core")
local redis             = require("apisix.plugins.dag-datasource.redis")
local ngx               = ngx
local redis_util        = require("apisix.plugins.utils.redis_util")
local new_tab           = require("table.new")
local string_util       = require("apisix.plugins.utils.string_util")
local datamap_query     = require("apisix.plugins.dag-datasource.query_process.datamap_query")
local cache_util        = require("apisix.plugins.utils.cache_util")
local ipairs            = ipairs
local json_decode       = core.json.decode

local _M={version=0.2}

-- ===========================私有方法================================

-- ===========================模块方法================================
-- local function local_query_gray_route(applyer_id,process_code,app_id,city_id)
--     core.log.info("灰度路由查询查询")
--     -- 生成gray_route_key
--     local gray_route_key = redis_util.get_key(redis_util.GRAY_ROUTE,applyer_id)
--     -- 查询redis
--     local red,err = redis_util.redis_new()
--     if not red then
--         core.log.error("redis客户端实例化失败:",err)
--         return nil,"redis客户端实例化失败:"..err
--     end
--     local ret,err=red:hgetall(gray_route_key)
--     if err then
--         core.log.error("查询灰度路由失败:",err)
--         return nil,err
--     end
--     core.log.info("灰度路由查询结果:",core.json.delay_encode(ret))

--     -- 返回空则不需要切换环境地址
--     if redis_util.is_redis_null(ret) then
--         return 0
--     end

--     local gray_hash = redis_util.array_to_hash(ret) or {}
--     core.log.info("process_code:",process_code,",app_id:",app_id,",city_id:",city_id,",applyer_id:",applyer_id)

--     local key_list = new_tab(8,0)
--     key_list[1] = app_id.."."..city_id.."."..process_code
--     key_list[2] = app_id..".".."99".."."..process_code
--     key_list[3] = "ALL".."."..city_id.."."..process_code
--     key_list[4] = app_id.."."..city_id..".".."ALL"
--     key_list[5]= "ALL"..".".."99".."."..process_code
--     key_list[6] = app_id..".".."99"..".".."ALL"
--     key_list[7] = "ALL".."."..city_id..".".."ALL"
--     key_list[8] = "ALL"..".".."99"..".".."ALL"

--     for _,v in ipairs(key_list) do
--         if gray_hash[v] then
--             local urls,err = json_decode(gray_hash[v])
--             if not urls then
--                 return nil,"灰度路由地址配置错误，解析地址失败"..err .. ",redis_key:" .. gray_route_key
--             end
--             return urls
--         end
--     end
--     return 0
-- end

local function query_gray_conf(applyer_id)
    local red,err = redis_util.redis_new()
    if not red then
        core.log.error("redis客户端实例化失败:",err)
        return nil,"redis客户端实例化失败:"..err
    end
    -- 查询灰度flag
    local gray_conf_key = redis_util.get_key(redis_util.GRAY_CONF_FLAG,applyer_id)
    local res,err = red:hgetall(gray_conf_key)
    if err then
        core.log.error("灰度flag配置查询失败:",err)
        return nil,err
    end
    if redis_util.is_redis_null(res) then
        return nil
    end
    local gray_conf = redis_util.array_to_hash(res)
    return gray_conf
end

local function query_gray_group(flag)
    local red,err = redis_util.redis_new()
    if not red then
        core.log.error("redis客户端实例化失败:",err)
        return nil,"redis客户端实例化失败:"..err
    end
    local gray_group_key = redis_util.get_key(redis_util.GRAY_GROUP,flag)
    local res,err = red:hgetall(gray_group_key)
    if err then
        core.log.error("灰度路由组查询失败:",err)
        return nil,err
    end
    if redis_util.is_redis_null(res) then
        return nil
    end
    local gray_group = redis_util.array_to_hash(res)
    return gray_group
end

-- local function query_gray_address(service_code,app_id,city_id,applyer_id)
--     local red,err = redis_util.redis_new()
--     if not red then
--         core.log.error("redis客户端实例化失败:",err)
--         return nil,"redis客户端实例化失败:"..err
--     end
--     -- 查询灰度flag
--     local gray_conf_key = redis_util.get_key(redis_util.GRAY_CONF_FLAG,city_id)
--     local res,err = red:hgetall(gray_conf_key)
--     if err then
--         core.log.error("灰度flag配置查询失败:",err)
--         return nil,err
--     end
--     if redis_util.is_redis_null(res) then
--         return nil
--     end
--     local gray_conf = redis_util.array_to_hash(res)
--     local key_list = new_tab(4,0)
--     key_list[1] = "ALL" .. "." .. "ALL" .. "." .. applyer_id
--     key_list[2] = service_code .. "." .. "ALL" .. "." .. applyer_id
--     key_list[3] = "ALL" .. "." .. app_id .. "." .. applyer_id
--     key_list[4] = service_code .. "." .. app_id .. "." .. applyer_id
--     core.log.info("灰度key_list:",core.json.delay_encode(key_list))
--     local flag = nil
--     for _,v in ipairs(key_list) do
--         flag = gray_conf[v]
--         if flag then
--             break
--         end
--     end
--     if not flag then
--         return nil
--     end
--     -- 查询灰度路由组
--     local gray_group_key = redis_util.get_key(redis_util.GRAY_GROUP,flag)
--     res,err = red:hgetall(gray_group_key)
--     if err then
--         core.log.error("灰度路由组查询失败:",err)
--         return nil,err
--     end
--     if redis_util.is_redis_null(res) then
--         return nil
--     end
--     local gray_group = redis_util.array_to_hash(res)
--     local address_str = gray_group["CITY_" .. city_id]
--     if address_str == nil or #address_str==0 then
--         return nil
--     end
--     local address,err = json_decode(address_str)
--     if not address then
--         core.log.error("灰度路由组地址格式错误,flag:",flag, ",city_id:", city_id, ",address:", address_str,",err:",err)
--         return nil,"灰度路由组地址格式错误,flag:" ..flag ..",city_id:" ..city_id .. ",address:" .. address_str .. ",err:" .. err
--     end
--     if #address == 0 then
--         core.log.error("灰度路由组地址数量为0,flag:",flag, ",city_id:", city_id, ",address:", address_str)
--         return nil,"灰度路由组地址数量为0,flag:" ..flag ..",city_id:" ..city_id .. ",address:" .. address_str
--     end
--     return address
-- end

-- function _M.query_gray_route(applyer_id,sys)
--     return cache_util.fetch_data(cache_util.func_enum.gray_route,
--                                 local_query_gray_route,
--                                 applyer_id or "",
--                                 sys.process_code or "",
--                                 sys.app_id or "",
--                                 sys.city_id or "99")
-- end


function _M.query_gray_address(service_code,app_id,city_id,applyer_id)
    local gray_conf,err = cache_util.fetch_data(cache_util.func_enum.gray_flag_conf,
                                                query_gray_conf,applyer_id or "")
    if gray_conf == nil then
        return nil,err
    end
    local key_list = new_tab(4,0)
    key_list[1] = "ALL" .. "." .. "ALL" .. "." .. city_id
    key_list[2] = service_code .. "." .. "ALL" .. "." .. city_id
    key_list[3] = "ALL" .. "." .. app_id .. "." .. city_id
    key_list[4] = service_code .. "." .. app_id .. "." .. city_id
    local flag = nil
    for _,v in ipairs(key_list) do
        flag = gray_conf[v]
        if flag then
            break
        end
    end
    if not flag then
        return nil
    end
    local gray_group,err = cache_util.fetch_data(cache_util.func_enum.gray_group,
                                            query_gray_group,flag)
    if gray_group == nil then
        return nil,err
    end
    local address_str = gray_group["CITY_" .. city_id]
    if address_str == nil or #address_str==0 then
        return nil
    end
    local address,err = json_decode(address_str)
    if not address then
        core.log.error("灰度路由组地址格式错误,flag:",flag, ",city_id:", city_id, ",address:", address_str,",err:",err)
        return nil,"灰度路由组地址格式错误,flag:" ..flag ..",city_id:" ..city_id .. ",address:" .. address_str .. ",err:" .. err
    end
    if #address == 0 then
        core.log.error("灰度路由组地址数量为0,flag:",flag, ",city_id:", city_id, ",address:", address_str)
        return nil,"灰度路由组地址数量为0,flag:" ..flag ..",city_id:" ..city_id .. ",address:" .. address_str
    end
    return address
end



return _M