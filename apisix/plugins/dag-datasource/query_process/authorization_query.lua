local core          = require("apisix.core")
local redis_util    = require("apisix.plugins.utils.redis_util")

local _M={version=0.1}

function _M.get_ability_authorization(ability_code)
    local red,err=redis_util.redis_new()
    if not red then
        core.log.error("redis客户端实例化失败:",err)
        return nil,err
    end
    local key = redis_util.get_key(redis_util.ABILITY_AUTHORIZATION,ability_code)
    local res,err2 = red:hgetall(key)
    if err2 then
        return nil,"二次权限检查，查询失败:".. err2
    end
    if redis_util.is_redis_null(res) then
        return nil
    end
    return redis_util.array_to_hash(res)
end


function _M.get_authorization_api_group(app_id,group_id)
    local red,err=redis_util.redis_new()
    if not red then
        core.log.error("redis客户端实例化失败:",err)
        return nil,err
    end
    local key = redis_util.get_key(redis_util.AUTHORIZATION_API_GROUP,app_id,group_id)
    local res,err2 = red:hgetall(key)
    if err2 then
        return nil,"二次权限检查，查询失败:".. err2
    end
    if redis_util.is_redis_null(res) then
        return nil
    end
    return redis_util.array_to_hash(res)
end



