local core              = require("apisix.core")
local redis             = require("apisix.plugins.dag-datasource.redis")
local clone_tab         = require("table.clone")
local new_tab           = require("table.new")
local ngx_timer_at      = ngx.timer.at
local sfdl_builder      = require("apisix.plugins.sfdl.element.builder")
local fetch_local_conf  = require("apisix.core.config_local").local_conf
local redis_util        = require("apisix.plugins.utils.redis_util")
local read_conf_util    = require("apisix.plugins.utils.read_conf_util")
local cache_util        = require("apisix.plugins.utils.cache_util")
local nkeys             = core.table.nkeys
local upper_str         = string.upper


local template_versions
local template_data

local _M={version=0.1}
local mt={
    __index=_M
}

-- ================================常量定义================================
local CYCLE_TIME=30 -- 单位：秒

_M.TEMPLATY_TYPE_REQ="REQUEST"
_M.TEMPLATE_TYPE_RESP="RESPONSE"
_M.TEMPLATE_TYPE_ERR="ERROR"
_M.TEMPLATE_TYPE_PRO="PROCESS"

-- =================================模块初始化执行===================================
-- 更新 template_data
local function update_template_data(red,versions,full_versions)
    red:init_pipeline()   -- 开启批处理
    -- 遍历versions,获取模板信息
    for k,_ in pairs(versions) do
        red:hgetall(redis_util.get_key(redis_util.TEMPLATE,k))
    end
    local templates,err =red:commit_pipeline() -- 批处理提交
    -- core.log.warn("templates:",core.json.delay_encode(templates))
    if not templates then
        core.log.error(err)
        return nil,err
    end

    local idx=1
    local val
    for id,_ in pairs(versions) do
        val=templates[idx]
        idx=idx+1
        if redis_util.is_redis_null(val) then
            core.log.error("template版本数据与template数据不一致,缺少:",id)
            -- 删除template_versions中无法查询到的版本数据
            full_versions[id]=nil
        else
            -- 数据存入template_data
            template_data[id]=redis_util.array_to_hash(val)
        end
    end
    -- 遍历返回的模板集合,存入template_data
    -- for _,template in ipairs(templates) do
    --     -- core.log.warn("遍历模板")
    --     template=redis_util.array_to_hash(template)
    --     template_data[template.ID]=template
    -- end
    return true
end

-- 比较新获取的版本号,获取需要更新的模板id
-- @old: 原版本列表
-- @new: 新版本列表
-- return
-- @ids: 需要更新的id列表
-- @delete_list: 本地需要删除的id列表
-- @full_version: 数据源中的id 版本列表
local function get_update_ids(old,new)
    -- 克隆新的模板版本
    local full_versions=clone_tab(new)
    local delete_list={}
    local idx=0
    local ids=new
    for k,_ in pairs(old) do
        if ids[k] then    -- 本地模板版本与redis模板版本比较
            if old[k] == ids[k] then  -- 模板的版本没有改变则从更新列表删除
                ids[k]=nil
            end
        else                -- 存储需要删除的模板
            idx=idx+1
            delete_list[idx]=k
        end
    end
    return ids,delete_list,full_versions
end

local function fetch_data(premature)
    if premature then
        return
    end
    core.log.debug("模板定时更新任务执行。。。。。")
    local red,err=redis_util.redis_new()
    if not red then
        core.log.error("redis客户端实例化失败:",err)
        if template_versions == nil then
            core.log.error("模板数据缓存初始化失败")
        end
        return
    end
    local key=redis_util.get_key(redis_util.TEMPLATE_VERSION)
    -- 获取模板总数
    local versions,err=red:zrange(key,0,-1,"withscores")
    if err then
        core.log.error("template_query init...",err)
        if template_versions == nil then
            core.log.error("模板数据缓存初始化失败")
        end
        return
    end
    if redis_util.is_redis_null(versions) then
        core.log.warn("系统未配置任何协议模板")
        if template_versions == nil then
            core.log.error("模板数据缓存初始化失败")
        end
        return
    end
    -- 数组转hash处理
    versions=redis_util.array_to_hash(versions)
    if template_versions==nil then
        -- 初始化template_data
        template_data=new_tab(0,#versions)
        local full_versions=clone_tab(versions)
        local ok,err=update_template_data(red,versions,full_versions)
        if not ok then
            core.log.error("模板数据缓存初始化失败",err)
            return
        end
        -- 初始化template_versions
        template_versions=full_versions
    else
        -- 获取需要更新的模板id
        local update_ids,delete_ids,full_versions=get_update_ids(template_versions,versions)
        if nkeys(update_ids)==0 then
            return
        end
        -- 更新模板信息
        -- core.log.warn("需更新的模板:",core.json.delay_encode(update_ids))
        local ok,err=update_template_data(red,update_ids,full_versions)
        if not ok then
            core.log.error("模板数据缓存更新失败:",err)
            return
        end
        -- 更新模板版本
        -- core.log.warn("更新后的模板版本:",core.json.delay_encode(new_versions))
        template_versions=full_versions
        -- 删除数据源中不存在的模板
        -- core.log.warn("需删除的模板:",core.json.delay_encode(delete_ids))
        for _,v in ipairs(delete_ids) do
            template_data[v]=nil
        end
    end
end

do
    local timer_config = read_conf_util.get_conf("timer_config")
    local ok,err = core.timer.new("模板更新定时任务",fetch_data,{check_interval = timer_config.template_query})
    if not ok then
        core.log.error("模板更新定时任务启动失败:",err)
    end
end

-- ==================================私有方法==================================

-- template_info={
--     ENCODING="xxx",  编码，规定外围渠道的编码
--     TYPE="xxx",      模板类型，分为请求响应异常三个协议模板和编排模板
--     CONTENT="xxx",   模板内容，协议模板会解析后存储，编排模板不解析
--     CODE="xx",       模板代号
--     ID="xx"          模板id
-- }
local function get_template_and_build(template_id,is_process)
    core.log.info("获取模板信息")
    if template_data[template_id] == nil then
        return nil,"模板不存在:"..template_id
    end
    local template_info=clone_tab(template_data[template_id])
    -- 若模板为能力编排模板，则不需要解析
    local flag=true
    if read_conf_util.get_conf("ffi_enable") == 0 then
        flag=false
    end
    if flag or is_process then
        return template_info
    end
    local pd,err=sfdl_builder.build(template_info.CONTENT)
    if not pd or err then
        core.log.error("解析模板失败,模板id:",template_id,",err:",err)
        return nil,err
    end
    template_info.CONTENT=pd
    return template_info
end

-- ==================================模块方法==================================

-- 获取当前请求匹配的协议模板关系
local function local_get_protocol_relation(process_code,app_id)
    local red,err=redis_util.redis_new()
    if not red then
        core.log.error("redis客户端实例化失败:",err)
        return nil,err
    end
    process_code=upper_str(process_code)
    -- RELATION.TEMPLATE:{SERVICENAME.CONDITION}:HASH
    local complex_key=redis_util.get_key(redis_util.PROTOCOL_TEMPLATE_RELATION,app_id.."."..process_code)
    local pro_key=redis_util.get_key(redis_util.PROTOCOL_TEMPLATE_RELATION,process_code)
    local app_key=redis_util.get_key(redis_util.PROTOCOL_TEMPLATE_RELATION,app_id)
    -- core.log.error("app_key:",app_key)
    red:init_pipeline()           -- 开启批处理
    red:hgetall(complex_key)
    red:hgetall(app_key)
    red:hgetall(pro_key)
    local ret,err=red:commit_pipeline()   -- 批处理提交
    if not ret or err then
        core.log.error("redis查询失败:",err)
        return nil,err
    end
    core.log.info("template_ret:",core.json.delay_encode(ret))
    if not redis_util.is_redis_null(ret[1]) then
        return redis_util.array_to_hash(ret[1])
    end
    if not redis_util.is_redis_null(ret[2]) then
        return redis_util.array_to_hash(ret[2])
    end
    if not redis_util.is_redis_null(ret[3]) then
        return redis_util.array_to_hash(ret[3])
    end
    return false
end

function _M.get_protocol_relation(process_code,app_id)
    if process_code == nil and app_id == nil then
        return false
    end
    local func_enum = cache_util.func_enum.template_relation
    return cache_util.fetch_data(
        func_enum,
        local_get_protocol_relation,
        process_code or "",
        app_id or "")
end

-- 根据模板id获取模板信息
-- 其中协议模板的CONTENT为解析后的sfdl对象，能力编排模板不做解析
function _M.get_sfdl_template(template_id)
    if template_versions==nil then
        core.log.error("模板数据未初始化完成，无法正常响应")
        return nil,"模板数据未初始化完成，无法正常响应"
    end
    local version=template_versions[template_id]
    if version==nil then
        core.log.error("模板未定义,模板id:",template_id)
        return nil,"未定义该模板:"..template_id
    end
    return core.lrucache.global("template/"..template_id,
                                    version,get_template_and_build,template_id)
end

function _M.get_template_info(template_id)
    template_id=tostring(template_id)
    if template_versions==nil then
        core.log.error("模板数据未初始化完成，无法正常响应")
        return nil,"模板数据未初始化完成，无法正常响应"
    end
    local version=template_versions[template_id]
    if version==nil then
        core.log.error("未定义该模板或者模板版本:",template_id)
        return nil,"未定义该模板或者模板版本:"..template_id
    end
    -- local template = core.lrucache.global("template/"..template_id,
    --                                 version,get_template_and_build,template_id)
    local template = template_data[template_id]
    if not template then
        core.log.error("系统错误，模板数据丢失")
        return nil,"系统错误，模板数据丢失"
    end
    -- core.log.warn("template:",core.json.delay_encode(template))
    local content = template.CONTENT
    if content == nil or #content < 38 then
        core.log.error("模板内容配置错误,template_id:",template_id,",content:",content or "nil")
        return nil,"模板内容错误,template_id:" .. template_id .. ",content:".. (content or "nil")
    end

    local template_info=new_tab(0,3)
    template_info.content = content
    template_info.template_name=template_id
    template_info.version_code=tonumber(version)
    return template_info
end

function _M.get_template_number()
    local versions_number = template_versions and nkeys(template_versions)
    local data_number = template_versions and nkeys(template_data)
    return 200,{versionsNumber = versions_number,dataNumber=data_number}
end

function _M.get_data_and_versions()
    return {
        versions = template_versions,
        data = template_data
    }
end



function _M.new(self)
    local tab = {connecter = redis_util.redis_new()}
    return setmetatable(tab, mt)
end

return _M
