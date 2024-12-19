local core=require("apisix.core")
local nlbpm_util=require("apisix.plugins.nlbpm.nlbpm_util")

local _M={}

local mt={
    __index=function (mytab,key)
        if mytab["__dag_tmp_session"]=="" then
            core.log.warn("session为nil")
            return nil
        end
        if key == "route_value" then
            local city_id=nlbpm_util.get_sys_val(mytab["__dag_tmp_session"],"city_id")
            if city_id then
                return city_id
            end
            local route_type=nlbpm_util.get_sys_val(mytab["__dag_tmp_session"],"route_type")
            if route_type ~= "1" then
                city_id= "99"
            else
                city_id=tonumber(nlbpm_util.get_sys_val(mytab["__dag_tmp_session"],"route_value"))
                if not city_id or city_id < 11 or city_id > 23 then
                    city_id = "99"
                else
                    city_id = tostring(city_id)
                end
            end
            nlbpm_util.set_sys_val(mytab["__dag_tmp_session"],"city_id",city_id)
            return city_id
        end
        return nlbpm_util.get_sys_val(mytab["__dag_tmp_session"],key)
    end
}

function _M.set_session(tab,session)
    tab["__dag_tmp_session"]=session
end

function _M.release_session(tab)
    tab["__dag_tmp_session"]=""
end

function _M.new()
    local tab={
        ["__dag_tmp_session"]=""
    }
    return setmetatable(tab,mt)
end


return _M