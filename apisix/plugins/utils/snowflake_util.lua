local ngx        = ngx
local bit        = require("bit")
local core       = require("apisix.core")
local uuid       = require("resty.jit-uuid")
local snowflake  = require("snowflake")
local redis      = require("apisix.plugins.dag-datasource.redis")
local tostring   = tostring
local math_pow   = math.pow
local math_ceil  = math.ceil
local math_floor = math.floor
local now        = ngx.now

local data_machine = nil
local snowflake_inited = false
local attr = nil
local _M = {}

local attr_schema = {
    type = "object",
    properties = {
        snowflake = {
            type = "object",
            properties = {
                enable = { type = "boolean", default = false },
                snowflake_epoc = { type = "integer", minimum = 1, default = 1609459200000 },
                data_machine_bits = { type = "integer", minimum = 1, maximum = 31, default = 12 },
                sequence_bits = { type = "integer", minimum = 1, default = 10 },
                delta_offset = { type = "integer", default = 1, enum = { 1, 10, 100, 1000 } },
                data_machine_ttl = { type = "integer", minimum = 1, default = 30 },
                data_machine_interval = { type = "integer", minimum = 1, default = 10 }
            }
        }
    }
}

local lock_script1 = [[
    local key = KEYS[1]
    local value = ARGV[1]
    local timettl = ARGV[2]
    local lockClientId = redis.call('GET', key)
    if lockClientId == value then
        local res = redis.call('PEXPIRE', key, timettl)
        if res == 1 then
            return 'success'
        end
    elseif not lockClientId then
        local res = redis.call('SET', key, value, 'PX', timettl)
        if res then
            return 'success'
        end
    end
    return 'fail'
]]

local lock_script = "local key = KEYS[1] \n local value = ARGV[1] \n local timettl = ARGV[2] \n local lockClientId = redis.call('GET', key) \n if lockClientId == value then \n     local res = redis.call('PEXPIRE', key, timettl) \n     if res == 1 then \n         return 'success' \n     end \n elseif not lockClientId then \n     local res = redis.call('SET', key, value, 'PX', timettl) \n     if res then \n         return 'success' \n     end \n end \n return 'fail'"
local lock_sha = nil

local function init_script(red,reset)
    if lock_sha ~= nil and not reset then
        core.log.info("redis script has load , sha :",lock_sha)
        return true
    end
    local ret,err=red:script('load',lock_script)
    if not ret then
        return nil,err
    end
    lock_sha=ret
    core.log.info("lock_sha :",lock_sha)
    return true
end

local function execute_script1(red,lock_key,value,time_ttl)

    local ok,err = init_script(red)
    if not ok then
        core.log.error("load redis script err:",err)
        return nil,"load redis script err:"..err
    end

    local res,err=red:evalsha(lock_sha,1,lock_key,value,time_ttl)
    core.log.info("exec redis script,sha:",lock_sha," ,res :",res)

    if res == "fail" then
        core.log.warn(err)
        ok,err = init_script(red,true)
        if not ok then
            core.log.error("load redis script err:",err)
            return nil,"load redis script err:"..err
        end
        res,err=red:eval(lock_script,1,lock_key,value,time_ttl)
        if res=="success" then
            return res
        end
        core.log.error("execute redis script err:",err)
        return nil,"execute redis script err:"..err
    end
    return res,err
end

local function execute_script(red,lock_key,value,time_ttl)

    local res, err = red:eval(lock_script, 1, lock_key, value, time_ttl)
    if res == "success" then
        return res
    end

    return res, err
end

local function timer_lock_key(lock_key,value,time_ttl,delay)
    
    local handler
    handler = function()
        local red,err1 = redis:new(false)
        if not red then
            core.log.error("init redis-cli fail :",err1)
            return
        end
        --local _, err = red:evalsha(lock_sha, 1, lock_key, value, time_ttl)
        local _, err = red:eval(lock_script, 1, lock_key, value, time_ttl)
        if err then
            core.log.error("set key: " .. lock_key .. " failed.")
        else
            core.log.info("set key: " .. lock_key .. ",value: "..value..", ttl:"..time_ttl.." success.")
        end

        ngx.timer.at(delay, handler)
    end

    return ngx.timer.at(delay,handler)
end


local function gen_data_machine(max_number)
    if data_machine == nil then

        local red,err1 = redis:new(false)
        if not red then
            core.log.error("init redis-cli fail :",err1)
            return
        end

        local value = uuid.generate_v4()
        local time_ttl = attr.snowflake.data_machine_ttl
        if type(time_ttl) =="number" then
            time_ttl = time_ttl * 1000
        else
            time_ttl = 30 * 1000 ---default
        end
        local interval = attr.snowflake.data_machine_interval
        local id = 1
        ::continue::
        while (id <= max_number) do

            local lock_key ="snowflake_id_"..tostring(id)

            core.log.info("lock_key:",lock_key,", value:",value,", time_ttl:",time_ttl)
            local res,_=execute_script(red,lock_key,value,time_ttl)
            core.log.info("exec redis script ,res :",res)

            if res == "fail" then
                core.log.info("lock "..(lock_key).." fail")
                id = id + 1
                goto continue
            else
                data_machine = id
                core.log.info("key : " .. lock_key .. " , value : " .. value .. " add ! ")

                local ok, err3 = timer_lock_key(lock_key,value,time_ttl,interval)
                if not ok then
                    core.log.info("failed to create the timer: ", err3)
                    return nil
                else
                    core.log.info("create the timer success.")
                end
                break
            end
        end

        if data_machine == nil then
            core.log.error("No data_machine is not available")
            return nil
        end
    end
    return data_machine
end

local function split_data_machine(data_machine, node_id_bits, datacenter_id_bits)
    local num = bit.tobit(data_machine)
    local worker_id = bit.band(num, math_pow(2, node_id_bits) - 1)
    num = bit.rshift(num, node_id_bits)
    local datacenter_id = bit.band(num, math_pow(2, datacenter_id_bits) - 1)
    return worker_id, datacenter_id
end

-- Initialize the snowflake algorithm
local function snowflake_init()

    local local_conf = core.config.local_conf()
    attr = core.table.try_read_attr(local_conf, "plugin_attr", "trace-id")
    if not attr then
        core.log.error("failed to read snowflake")
        return
    end

    local ok, err = core.schema.check(attr_schema, attr)
    if not ok then
        core.log.error("failed to check the snowflake", ": ", err)
        return
    end

    local max_number = math_pow(2, (attr.snowflake.data_machine_bits))
    local datacenter_id_bits = math_floor(attr.snowflake.data_machine_bits / 2)
    local node_id_bits = math_ceil(attr.snowflake.data_machine_bits / 2)
    data_machine = gen_data_machine(max_number)
    if data_machine == nil then
        return
    else
        core.log.info("init data_machine: ",data_machine)
    end

    local worker_id, datacenter_id = split_data_machine(data_machine, node_id_bits, datacenter_id_bits)

    core.log.info("snowflake init datacenter_id: " .. datacenter_id .. " worker_id: " .. worker_id)

    snowflake.init(
        datacenter_id,
        worker_id,
        attr.snowflake.snowflake_epoc,
        node_id_bits,
        datacenter_id_bits,
        attr.snowflake.sequence_bits,
        attr.delta_offset
    )

    if snowflake_inited == false then
        snowflake_inited = true
    end
end

-- generate snowflake id
function _M.next_id()
    if snowflake_inited == false then
        snowflake_init()
    end

    return snowflake:next_id()
end

function _M.next_trace_id()
    if snowflake_inited == false then
        snowflake_init()
    end

    return  "NYN" .. string.format("%016X", snowflake:next_id())
end


return _M
