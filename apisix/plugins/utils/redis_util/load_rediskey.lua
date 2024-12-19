local log = require("apisix.core.log")
local profile = require("apisix.core.profile")
local yaml = require("tinyyaml")
local core = require "apisix.core"
local io_open = io.open
local type = type
local ngx=ngx
local find_str=string.find
local sub_str=string.sub
local new_tab=require("table.new")
local insert_tab=table.insert
local clone_tab=require("table.clone")

local apisix_home = (ngx and ngx.config.prefix()) or ""

local config_data
local rediskey_template

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
    COUNTER="dag.key.counter",
    TEMPLATE="dag.key.template",
    PROTOCOL_TEMPLATE_RELATION="dag.key.protocolTemplateRelation",
    PROCESS_TEMPLATE_RELATION="dag.key.processTemplateRelation",
    TEMPLATE_VERSION="dag.key.templateVersion",
    TOKEN="dag.key.token",
    DATAMAP="dag.key.dataMapTagetValue",
    DATAMAP_VERSION="dag.key.dataMapVersion"
}

--=============================私有方法=======================================
local function read_file(path)
    local file, err = io_open(path, "rb")   -- read as binary mode
    if not file then
        log.error("failed to read config file:" .. path, ", error info:", err)
        return nil, err
    end

    local content = file:read("*a") -- `*a` reads the whole file
    file:close()
    return content
end

local function get_rediskey_path(file_name)
    local file_path = apisix_home  .. "conf/" .. file_name
    return file_path .. ".yml"
end

function _M.clear_cache()
    config_data = nil
end

local function read_conf(force)
    if not force and config_data then
        return config_data
    end

    local yaml_config, err = read_file(get_rediskey_path("rediskey"))
    if type(yaml_config) ~= "string" then
        return nil, "failed to read config file:" .. err
    end

    config_data = yaml.parse(yaml_config)
    return config_data
end

local function process_key_template(key_template)
    local template={}
    local temp=key_template
    while(true) do
        local f,_=find_str(temp,"{")
        local _,t=find_str(temp,"}")
        if f == nil then
            insert_tab(template,temp)
            break
        else
            local header=sub_str(temp,1,f-1)
            temp=sub_str(temp,t+1)
            insert_tab(template,header)
            insert_tab(template,"__placeholder")
        end
    end
    local fun=function (...)
        local args={...}
        local idx=0
        local temp=clone_tab(template)
        for k,v in ipairs(temp) do
            if  v == "__placeholder" then
                idx=idx+1
                temp[k]=args[idx]
            end
        end
        return table.concat(temp)
    end
    return fun
end

local function get_template(force)
    if not force and rediskey_template then
        return rediskey_template
    end
    local data=read_conf(force)
    rediskey_template=new_tab(0,#data)
    for k,v in pairs(data) do
        rediskey_template[k]=process_key_template(v)
    end
    return rediskey_template
end

do
    -- 加载rediskey.yaml并解析
    get_template()
end

--=============================模板方法=======================================

function _M.get_rediskey(template_name,...)
    local fun=rediskey_template[template_name]
    if fun == nil then
        return nil,"未定该rediskey模板"
    end
    return fun(...)
end

return _M