local service       = require("apisix.http.service")
local find_str      = string.find
local sub_str       = string.sub
local new_tab       = require("table.new")
local concat        = table.concat
local core          = require("apisix.core")

local _M = {}

local L_CHAR = "${"
local R_CHAR = "}"
local L_LEN = #L_CHAR
local R_LEN = #R_CHAR
local ID_PREFIX = "VARIABLE_"

local function get_placeholder_value(place_holder)
    local service_id = ID_PREFIX .. place_holder
    local entity = service.get(service_id)
    entity = entity and entity.value
    return entity and entity.name
end

function _M.replace(expression)
    if expression == nil then
        return "nil"
    end
    if #expression == 0 then
        return expression
    end
    local arr = new_tab(5,0)
    local idx = 0
    local temp = expression
    local header
    local key
    local value
    while(true) do
        local f,_ = find_str(temp,L_CHAR)
        if f == nil then
            idx = idx + 1
            arr[idx] = temp
            break
        end
        local _,t = find_str(temp,R_CHAR,f+L_LEN)
        if t == nil then
            idx = idx + 1
            arr[idx] = temp
            break
        end
        header = sub_str(temp,1,f-1)
        idx = idx + 1
        arr[idx] = header
        key = sub_str(temp,f+L_LEN,t-1)
        value = get_placeholder_value(key)
        idx = idx + 1
        if value then
            arr[idx] = value
        else
            arr[idx] = sub_str(temp,f,t+R_LEN-1)
        end
        temp = sub_str(temp,t+R_LEN)
    end
    return concat(arr)
end

return _M