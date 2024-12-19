local core=require("apisix.core")
local new_tab=require("table.new")

local _M={}

function _M.build_err_tab(type, code, msg)
    local err_tab = new_tab(0, 3)
    err_tab.type = type
    err_tab.code = code
    err_tab.msg = msg
    return err_tab
end

return _M