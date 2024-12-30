local core=require("apisix.core")
local service_call=require("apisix.plugins.ability-route.service_call")
local ngx=ngx

-- 透传能力调用
local _M={}

-- =============================私有方法===============================
local function get_route_value(sys_tab)
    if tostring(sys_tab.route_type) == "1" then
        local route_value=tonumber(sys_tab.route_value)
        if route_value and (route_value >= 11 and route_value <= 23) then
            return route_value
        end
    end
    return 99
end

-- =============================模块方法===============================

function _M.ability_call(ctx,conf)
    local req_info=ctx.req_info
    -- core.log.warn("透传能力调用")
    local sys_tab=req_info.sys
    -- 当前能力为透传能力，直接获取process_code作为服务名
    local service_name=conf.service_code
    local app_id=sys_tab.app_id
    local route_value=get_route_value(sys_tab)
    local req_tab=req_info.req_tab
    local headers=ngx.req.get_headers(nil,sys_tab.transfer_raw_header=="1")

    -- 服务调用
    return service_call.call(req_info,service_name,app_id,route_value,req_tab,headers,ctx)
end

function _M.sse_protocol_call(ctx,conf)
    local req_info=ctx.req_info
    -- local sys_tab=req_info.sys
    -- 当前能力为透传能力，直接获取process_code作为服务名
    local service_name=conf.service_code
    -- local app_id=sys_tab.app_id
    local req_tab=req_info.req_tab
    local app_id=req_info.app_id
    local headers=req_info.headers
    return service_call.sse_call_before(req_info,service_name,app_id,req_tab,headers,ctx)
end

function _M.wb_protocol_call(ctx, conf)
    local req_info=ctx.req_info
    -- 当前能力为透传能力，直接获取process_code作为服务名
    local service_name=conf.service_code
    local req_tab=req_info.req_tab
    local app_id=req_info.app_id
    local headers=req_info.headers
    core.log.info("wb_protocol_call.req_info:", core.json.delay_encode(req_info))
    return service_call.wb_call_before(req_info,service_name,app_id,req_tab,headers,ctx)
end
return _M