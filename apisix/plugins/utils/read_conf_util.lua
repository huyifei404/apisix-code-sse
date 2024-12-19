local core=require("apisix.core")
local fetch_local_conf = require("apisix.core.config_local").local_conf

local _M={}

local local_conf
do
    local err
    local_conf,err=fetch_local_conf()
    if not local_conf then
        core.log.error(err)
        return nil,err
    end
end

function _M.get_conf(key)
    return local_conf[key]
end


return _M