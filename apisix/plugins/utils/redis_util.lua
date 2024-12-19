local core=require("apisix.core")
local rediskey_template=require("apisix.plugins.utils.redis_util.load_rediskey")
local new_tab=require("table.new")
local redis_cli             = require("apisix.plugins.dag-datasource.redis")
local ngx=ngx

_M={
    version = 0.1,
    -- ===常量===
    APPLYER="dag.key.applier",
    ABILITY="dag.key.ability",
    DEVELOPER="dag.key.developer",
    APP="dag.key.app",
    ABILITY_RELATION="dag.key.abilityRelation",
    CITY_RELATION="dag.key.cityRelation",
    ENTITY_RELATION="dag.key.entityRelation",
    ROUTE_ADDRESS_MAPPING="dag.key.routeAddressMapping",
    SERVICE_PATH_CONCAT="dag.key.routePathConcat",
    COUNTER="dag.key.counter",
    TEMPLATE="dag.key.template",
    PROTOCOL_TEMPLATE_RELATION="dag.key.protocolTemplateRelation",
    PROCESS_TEMPLATE_RELATION="dag.key.processTemplateRelation",
    TEMPLATE_VERSION="dag.key.templateVersion",
    TOKEN="dag.key.token",
    LEAKY_BUCKET="dag.key.limitLeakyBucket",
    SERVICE_LIMIT_LEAKY="dag.key.service.limit.leaky",
    SERVICE_LIMIT_TOKEN="dag.key.service.limit.token",
    DATAMAP="dag.key.dataMapTagetValue",
    DATAMAP_VERSION="dag.key.dataMapVersion",
    LIMIT_INFO="dag.key.limitInfo",
    GRAY_ROUTE="dag.key.grayRoute",
    PROMETHEUS="dag.key.prometheus",
    AMG_API_FROM_AOC = "dag.key.amg.aoc.api.relation",
    AOC_API_FROM_AMG = "dag.key.aoc.amg.api.relation",
    AMG_APP_FROM_AOC = "dag.key.amg.aoc.app.relation",
    AOC_APP_FROM_AMG = "dag.key.aoc.amg.app.relation",
    FAILED_REQ_RECORD = "dag.key.failed.req.record",
    API_ROUOTE_GROUP = "dag.key.route.group",
    GRAY_CONF_FLAG = "dag.key.grayConf",
    GRAY_GROUP = "dag.key.grayGroup",
    BUSINESS_SWITCH="dag.key.businessSwitch",
    ABILITY_AUTHORIZATION="dag.key.abilityAuthorization",
    AUTHORIZATION_API_GROUP="dag.key.authorizationApiGroup",
    RETURN_CODE_CONFIG="dag.key.returnCodeConfig",
    BREAKER_API_PROCESSCODE = "dag.key.breakerApiProcessCode",
    BREAKER_API_STATUS_PROCESSCODE = "dag.key.breakerApiStatusProcessCode",
    BREAKER_API_EVENT_PROCESSCODE = "dag.key.breakerApiEventProcessCode",
    BREAKER_API_EVENT_ABORT_PROCESSCODE = "dag.key.breakerApiEventAbortProcessCode",
    DUBBO_GROUP_ADDRESS = "dag.key.dubboGroupAddress",
    DUBBO_CITY_GROUP = "dag.key.dubboCityGroup"
}

--=============================模板方法=======================================

-- param template_name: rediskey的模板名称，详见conf/rediskey.yml
-- param ...: rediekey模板中占位符需要填入的参数
-- return: 返回根据模板拼接后的key
function _M.get_key(template_name,...)
    return rediskey_template.get_rediskey(template_name,...)
end

-- param tab: 从redis中获取的hash，以数组形式排列
-- return: 将数组转为hash返回
function _M.array_to_hash(tab)
    if tab==nil then
        return nil
    end
    local len=#tab
    if len==0 then
        return {}
    end
    local obj=new_tab(0,len/2)
    for i=1,len-1,2 do
        obj[tab[i]]=tab[i+1]
    end
    return obj
end

function _M.is_redis_null( res )
    if type(res) == "table" then
        for k,v in pairs(res) do
            if v ~= ngx.null then
                return false
            end
        end
        return true
    elseif res == ngx.null then
        return true
    elseif res == nil then
        return true
    end
    return false
end

function _M.redis_new(enable_slave_read)
    return redis_cli:new(enable_slave_read)
end

return _M
