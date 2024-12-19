local core              = require("apisix.core")
local redis             = require("apisix.plugins.dag-datasource.redis")
local ngx               = ngx
local clone_tab         = require("table.clone")
local new_tab           = require("table.new")
local fetch_local_conf  = require("apisix.core.config_local").local_conf
local redis_util        = require("apisix.plugins.utils.redis_util")
local nkeys             = core.table.nkeys
local concat_tab        = table.concat
local ngx_timer_at      = ngx.timer.at
local read_conf_util    = require("apisix.plugins.utils.read_conf_util")

local _M={version=0.1}
local datamap_versions
local shared_datamap=ngx.shared["shared-datamap"]
-- =================================常量定义=======================
CYCLE_TIME=30 -- 单位:秒

-- =================================私有方法==========================

-- datamap的rediskey拼接
local function concat_rediskey(datamap_id)
    return "DATAMAP:"..datamap_id..":STRING"
end

-- 更新shared-datamap
local function update_shared_datamap(red,versions,full_versions)
    red:init_pipeline()     -- redis批处理开启
    for id,_ in pairs(versions) do
        red:get(concat_rediskey(id))
    end
    local ret,err=red:commit_pipeline() -- 批处理提交
    if not ret then
        return nil,err
    end
    local idx=1
    local val
    -- core.log.warn("version:",core.json.delay_encode(versions))
    for id,_ in pairs(versions) do
        val=ret[idx]
        idx=idx+1
        if redis_util.is_redis_null(val) then
            core.log.error("datamap版本数据与datamap数据不一致,缺少:",id)
            -- 删除datamap_versions中不应该存在的版本数据
            full_versions[id]=nil
        else
            -- 数据存入shared_datamap
            -- core.log.warn("shared_datamap更新,key:",id,",val:",val)
            shared_datamap:set(id,val)
        end
    end
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
            if old[k] == ids[k] then  -- 模板的版本没够改变则从更新列表删除
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
    core.log.info("=========特权进程定时更新datamap=========")
    if premature then
        return
    end
    local red,err=redis_util.redis_new()
    if not red then
        core.log.error("redis客户端实例化失败:",err)
        if datamap_versions == nil then
            core.log.error("初始化datamap数据失败")
        end
        return
    end
    local key=redis_util.get_key(redis_util.DATAMAP_VERSION)
    -- 获取所有datamap id以及版本号
    local versions,err=red:zrange(key,0,-1,"withscores")
    if err then
        core.log.error("datamap_versions查询错误:",err)
        if datamap_versions == nil then
            core.log.error("初始化datamap数据失败")
        end
        return
    end
    if redis_util.is_redis_null(versions) then
        core.log.warn("系统未配置datamap")
        if datamap_versions == nil then
            core.log.error("初始化datamap数据失败")
        end
        return
    end
    -- 数组转hash处理
    versions=redis_util.array_to_hash(versions)
    -- core.log.error("datamap_versions:",core.json.delay_encode(versions))
    if datamap_versions == nil then
        -- 初始化datamap_versions,将datamap数据存入shared_dict
        local full_versions=clone_tab(versions)
        local ok,err=update_shared_datamap(red,versions,full_versions)
        if not ok then
            core.log.error("初始化datamap数据失败:",err)
            return
        end
        -- 初始化datemap_versions
        datamap_versions=full_versions
    else
        -- 获取更新列表,更新shared_dict
        local update_ids,delete_ids,full_versions=get_update_ids(datamap_versions,versions)
        if nkeys(update_ids)==0 then
            return
        end
        local ok,err=update_shared_datamap(red,update_ids,full_versions)
        if not ok then
            core.log.error("datamap数据更新失败:",err)
            return
        end
        -- 更新模板版本
        datamap_versions=full_versions
        -- 删除数据源中不存在的数据
        -- core.log.warn("需删除的模板:",core.json.delay_encode(delete_ids))
        for _,v in ipairs(delete_ids) do
            -- core.log.warn("删除指定datamap:",v)
            shared_datamap:delete(v)
        end
    end
end

-- =================================模块初始化=================================
do
    -- 进程id为nil(特权进程）执行定时任务
    if ngx.worker.id() == nil then
        local timer_config = read_conf_util.get_conf("timer_config")
        local ok,err = core.timer.new("datamap更新定时任务",fetch_data,{check_interval = timer_config.datamap_query})
        if not ok then
            core.log.error("datamap更新定时任务启动失败:",err)
        end
    end
end

-- ==================================模块方法==================================
function _M.data_map(domain_id,value_type,source_value)
    local tab=new_tab(3,0)
    tab[1]=domain_id
    tab[2]=value_type
    tab[3]=source_value
    local ret,err=shared_datamap:get(concat_tab(tab,"."))
    if err then
        core.log.error("datamap获取异常:",err)
    end
    return ret
end

function _M.get_memeory()
    local capacity = shared_datamap:capacity()
    local free_space = shared_datamap:free_space()
    return 200,{memory = capacity - free_space}
end

return _M
