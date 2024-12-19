local core              = require("apisix.core")
local log               = core.log
local emergency_log     = require("apisix.plugins.emergency-log")
local json_decode       = core.json.decode
local strategy_selector = require("apisix.plugins.limit-count.strategy_selector")
local script_executer   = require("apisix.plugins.limit_script.executer")
local limit_leaky_name  = require("apisix.plugins.limit-leaky-bucket").name
local limit_token_name  = require("apisix.plugins.limit-token-bucket").name
local redis_util        = require("apisix.plugins.utils.redis_util")
local exception         = require("apisix.plugins.exception")
local ngx               = ngx
local sleep             = ngx.sleep
local ngx_time          = ngx.time
local tonumber          = tonumber

local _M = {}

local function delay_control(ctx,delay,key,plugin_name)
    delay=tonumber(delay)
    if delay >=0 and delay <0.001 then
        return true
    elseif delay >= 0.001 then
        core.log.warn(plugin_name.."服务维度限流插件,请求延时:",delay,"秒,key:",key)
        sleep(delay)
        return true
    elseif delay==-1 then
        core.log.error(plugin_name.."服务维度请求速率超出限制,请求被拒绝,key:",key)
        return false,plugin_name.."服务维度请求速率超出限制,请求被拒绝,key:"..key
    else
        core.log.error("系统未知错误,服务维度限流错误返回:"..delay,",key:",key)
        return nil,"系统未知错误,服务维度限流错误返回:" .. delay.."key:"..key
    end
end

local function check_conf_hour(conf)
    local now_hour = tonumber(os.date("%H",ngx_time()))
    local start_hour = tonumber(conf.start_hour)
    local end_hour = tonumber(conf.end_hour)
    if start_hour and now_hour < start_hour then
        return false
    end
    if end_hour and now_hour > end_hour then
        return false
    end
    return true
end

local function check_rate_conf(conf)
    if type(conf.rate) ~= "number" then
        return false
    end
    if type(conf.max_burst) ~= "number" then
        return false
    end
    return true
end

local function limit_leaky_handle(ctx,red,service_code,conf)
    if conf == nil then
        return true
    end
    -- 判断配置是否有效，若无效则不执行限流
    if not check_rate_conf(conf) then
       return true
    end
    -- 判断是否在生效时间范围内，若不在范围内，跳过限流
    if not check_conf_hour(conf) then
        return true
    end
    local key = redis_util.get_key(redis_util.SERVICE_LIMIT_LEAKY,service_code)
    local delay,err = script_executer.execute(red,script_executer.LIMIT_LEAKY,key,conf)
    if delay == nil then
        return nil,err
    end
    return delay_control(ctx,delay,key,"漏桶")
end

local function limit_token_handle(ctx,red,service_code,conf)
    if conf == nil then
        return true
    end
    -- 判断配置是否有效，若无效则不执行限流
    if not check_rate_conf(conf) then
        return true
     end
    -- 判断是否在生效时间范围内，若不在范围内，跳过限流
    if not check_conf_hour(conf) then
        return true
    end
    conf.permits = conf.permits or 1
    local key = redis_util.get_key(redis_util.SERVICE_LIMIT_TOKEN,service_code)
    local delay,err =  script_executer.execute(red,script_executer.LIMIT_TOKEN,key,conf)
    if delay == nil then
        return nil,err
    end
    return delay_control(ctx,delay,key,"令牌桶")
end

-- 返回true: 请求通过
-- 返回false: 请求被限流，请求拒绝
-- 返回nil: 出现系统错误，请求拒绝
function _M.execute(ctx,red,service_code,service_conf_str)
    if service_conf_str==nil or #service_conf_str==0 then
        return true
    end
    core.log.info("服务维度限流准备执行。。。。。")
    core.log.info("服务维度限流配置:",service_conf_str)
    core.log.info("服务code:",service_code)
    local conf_tab,err = json_decode(service_conf_str)
    if conf_tab == nil then
        log.error("服务config配置解析失败:",service_conf_str,",err:",err)
        return nil,"服务config配置解析失败:" .. service_conf_str
    end
    local limit_leaky_conf = conf_tab[limit_leaky_name]
    local limit_token_conf = conf_tab[limit_token_name]

    -- 记录服务限流阈值到上下文
    ctx.req_info.service_rate = limit_leaky_conf.rate or limit_leaky_conf.rate

    local ok,err
    ok,err = limit_leaky_handle(ctx,red,service_code,limit_leaky_conf)
    if not ok then
        ctx.req_info.service_rate_status = 2
        return ok,err
    end
    ok,err = limit_token_handle(ctx,red,service_code,limit_token_conf)
    if not ok then
        ctx.req_info.service_rate_status = 2
        return ok,err
    end

    return true
end



return _M