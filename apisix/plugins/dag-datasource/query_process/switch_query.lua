local core          = require("apisix.core")
local redis_util    = require("apisix.plugins.utils.redis_util")

local _M={version=0.1}

function _M.get_switch(business_code)
    local red,err=redis_util.redis_new()
    if not red then
        core.log.error("redis客户端实例化失败:",err)
        return nil,err
    end
    local key = redis_util.get_key(redis_util.BUSINESS_SWITCH,business_code)
    local res,err2 = red:get(key)
    if err2 then
        return nil,"业务开关查询失败:".. err2
    end
    if redis_util.is_redis_null(res) then
        return nil
    end

    return res
end


return _M
