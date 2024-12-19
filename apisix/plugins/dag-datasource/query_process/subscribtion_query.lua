local core          = require("apisix.core")
local redis_util    = require("apisix.plugins.utils.redis_util")

local _M={version=0.1}

function _M.get_subscribtion_string(app_id,ability_code)
    local red,err=redis_util.redis_new()
    if not red then
        core.log.error("redis客户端实例化失败:",err)
        return nil,err
    end
    local key = redis_util.get_key(redis_util.ABILITY_RELATION,app_id,ability_code)
    local res,err = red:get(key)
    if err then
        return nil,"订阅信息查询失败:".. err
    end
    return res
end


return _M
