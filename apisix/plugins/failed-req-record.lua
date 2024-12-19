local core              = require("apisix.core")
local redis_util        = require("apisix.plugins.utils.redis_util")
local ngx               = ngx
local time_util         = require("apisix.plugins.utils.time_util")
local amg_util          = require("apisix.plugins.utils.amg_util")
local timer_at          = ngx.timer.at
local clear_tab         = require("table.clear")
local new_tab           = require("table.new")
local unpack_tab        = table.unpack

-- ==================常量=======================
local RECORD_REDIS_KEY = "HISTORY:REQUEST:STARTTIME:ZSET"
local SHARED_DICT_KEY = "failed_req_record"
local FLUSH_CYCLE = 1
local TAB_BUFFER_SIZE = 500
-- =================开关配置================
local req_recore_switch = false
-- =================初始化======================
local record_buffer = ngx.shared["failed-req-record"]
if not record_buffer then
    core.log.error("未配置failed-req-record的共享内存，无法实现异常请求记录")
end

-- ============= 特权进程定时任务=================
local tab_buffer = new_tab(TAB_BUFFER_SIZE,0)
local function fulsh_records(premature,cycle)
    if premature then
        timer_at(cycle,fulsh_records,cycle)
        return
    end
    local len = record_buffer:llen(SHARED_DICT_KEY)
    if len == 0 then
        -- core.log.info("缓存中不存在需要清除的请求记录，跳过本次任务")
        timer_at(cycle,fulsh_records,cycle)
        return
    end
    local temp_tab = new_tab(len,0)
    local t_idx = 1
    local red,err = redis_util.redis_new()
    if not red then
        core.log.error("redis数据库连接失败:",err)
        timer_at(cycle,fulsh_records,cycle)
        return
    end
    red:init_pipeline()
    local val
    local idx = 1
    for i=1,len,1 do
        if idx > TAB_BUFFER_SIZE then
            red:zrem(RECORD_REDIS_KEY,unpack_tab(tab_buffer))
            idx = 1
            clear_tab(tab_buffer)
        end
        val = record_buffer:rpop(SHARED_DICT_KEY)
        temp_tab[t_idx] = val
        tab_buffer[idx] = val
        t_idx = t_idx + 1
        idx = idx + 1
    end
    if idx > 1 then
        red:zrem(RECORD_REDIS_KEY,unpack_tab(tab_buffer))
        clear_tab(tab_buffer)
    end
    local res,err = red:commit_pipeline()
    if not res then
        core.log.error("异常请求记录删除失败，数据回滚：",err)
        for i = 1,len,1 do
            record_buffer:lpush(SHARED_DICT_KEY,temp_tab[i])
        end
    else
        core.log.info("已清除请求记录:",core.json.delay_encode(temp_tab))
    end
    timer_at(cycle,fulsh_records,cycle)
end
if ngx.worker.id() == nil and record_buffer then
    timer_at(1,fulsh_records,FLUSH_CYCLE)
end
-- =============================================

local plugin_name = "failed-req-record"

local schema = {
    type = "object",
    properties = {
        enable = {
            type = "boolean",
            default = false
        }
    }
}

local _M = {
    name = plugin_name,
    schema = schema,
    priority = 9999,
    version = 0.1
}

function _M.check_schema(conf)
    local ok, err = core.schema.check(schema, conf)
    if not ok then 
        return false, err
    end
    req_recore_switch = conf.enable
    if req_recore_switch == true then
        core.log.warn("异常请求记录开关: ON")
    else
        core.log.warn("异常请求记录开关: OFF")
    end
    return true
end

function _M.check_enable(ctx)
    ctx.failed_req_record_flag = req_recore_switch
end

-- 向redis插入记录
function _M.create_req_record(ctx)
    if ctx.failed_req_record_flag and record_buffer then
        local member = ctx.req_id .. "_" .. ngx.var.hostname
        local score = time_util.date_format(ngx.now()*1000,false)
        local red,err = redis_util.redis_new()
        if not red then
            core.log.warn("创建redis连接失败:",err)
            return nil,err
        end
        core.log.info("score:",score)
        core.log.info("member:",member)
        local res,err = red:zadd(RECORD_REDIS_KEY,score,member)
        if not res then
            core.log.error("向redis插入请求记录失败:",err)
            return nil,err
        end
        return true
    end
end

-- 需要删除的记录添加到共享内存
function _M.delete_req_record(ctx)
    if ctx.failed_req_record_flag and record_buffer then
        local member = ctx.req_id .. "_" .. ngx.var.hostname
        record_buffer:lpush(SHARED_DICT_KEY,member)
    end
end

return _M