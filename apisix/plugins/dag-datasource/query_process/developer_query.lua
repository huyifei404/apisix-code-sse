local core          = require("apisix.core")
local redis         = require("apisix.plugins.dag-datasource.redis")
local new_tab       = require("table.new")
local redis_util    = require("apisix.plugins.utils.redis_util")
local cache_util    = require("apisix.plugins.utils.cache_util")

local _M={version=0.1}
local mt={
    __index=_M
}

-- ==================================模块方法==================================

-- 获取当前请求匹配的应用-开发者的关系
local function local_get_developer_appid(app_id)
    local red,err=redis_util.redis_new()
    if not red then
        core.log.error("redis客户端实例化失败:",err)
        return nil,err
    end
    app_id = app_id or ""
    -- ENTITY:APP:{ID}:HASH 根据app_id找到开发者的信息
    local app_key = redis_util.get_key(redis_util.APP, app_id)
    core.log.info("app_developer_key : ", app_key)
    red:init_pipeline()           -- 开启批处理
    red:hgetall(app_key)
    local ret,err=red:commit_pipeline()   -- 批处理提交
    if ret == nil then
        return nil,err or ("未注册该应用-开发者关系:".. app_id)
    end
    core.log.info("developer_ret : ", core.json.delay_encode(ret))
    if not redis_util.is_redis_null(ret[1]) then
        return redis_util.array_to_hash(ret[1])
    end
    return false
end

function _M.get_developer_appid(app_id)
    return cache_util.fetch_data(cache_util.func_enum.developer_app,
                                local_get_developer_appid,
                                app_id or "")
end

function _M.get_developer(devloper_id)
    local red,err=redis_util.redis_new()
    if not red then
        core.log.error("redis客户端实例化失败:",err)
        return nil,err
    end
    local key = redis_util.get_key(redis_util.DEVELOPER,devloper_id)
    local res,err = red:hgetall(key)
    if err then
        return nil,"开发者信息查询失败:".. err
    end
    if redis_util.is_redis_null(res) then
        return nil
    end
    return redis_util.array_to_hash(res)
end

return _M
