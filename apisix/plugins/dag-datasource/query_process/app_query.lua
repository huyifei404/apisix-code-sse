local core          = require("apisix.core")
local redis_util    = require("apisix.plugins.utils.redis_util")

local _M={version=0.1}

function _M.get_app(app_id)
    local red,err=redis_util.redis_new()
    if not red then
        core.log.error("redis客户端实例化失败:",err)
        return nil,err
    end
    local key = redis_util.get_key(redis_util.APP,app_id)
    local res,err = red:hgetall(key)
    if err then
        return nil,"应用信息查询失败:".. err
    end
    if redis_util.is_redis_null(res) then
        return nil
    end
    return redis_util.array_to_hash(res)
end


return _M
