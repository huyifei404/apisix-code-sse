local core          = require("apisix.core")
local single        = require("apisix.plugins.dag-datasource.redis.single")
local cluster       = require("resty.rediscluster")
local ngx           = ngx
local string_util   = require("apisix.plugins.utils.string_util")

local CLUSTER_DICT_NAME="dag-redis-cluster-slot-lock"

local redis_conf
local redis_policy
do
    local read_conf_util=require("apisix.plugins.utils.read_conf_util")
    local redis_full_conf=read_conf_util.get_conf("redis")
    assert(redis_full_conf,"缺少redis相关配置")
    local policy=redis_full_conf.policy or "single"
    if policy == "single" then
        redis_conf=redis_full_conf.single
        core.log.info("redis_conf:",core.json.delay_encode(redis_conf))
        assert(redis_conf,"缺少redis单节点配置")
        redis_policy=single
    elseif policy == "cluster" then
        redis_conf=redis_full_conf.cluster
        assert(redis_conf,"缺少redis集群配置")
        core.log.info("redis_conf:",core.json.delay_encode(redis_conf))
        -- 环境变量配置
        local env_serv_list = os.getenv("REDIS_SERV_LIST")
        env_serv_list = env_serv_list and string_util.split(env_serv_list,",") or redis_conf.serv_list
        local env_password = os.getenv("REDIS_PASSWORD") or redis_conf.auth
        local env_connect_timeout = os.getenv("REDIS_CONNECT_TIMEOUT") or redis_conf.connect_timeout
        local env_keepalive_timeout = os.getenv("REDIS_KEEPALIVE_TIMEOUT") or redis_conf.keepalive_timeout
        local env_keepalive_cons = os.getenv("REDIS_KEEPALIVE_CONS") or redis_conf.keepalive_cons
        redis_conf.serv_list = env_serv_list
        redis_conf.auth = env_password
        redis_conf.connect_timeout = env_connect_timeout
        redis_conf.keepalive_timeout = env_keepalive_timeout
        redis_conf.keepalive_cons = env_keepalive_cons
        -- 集群默认开启从节点读取
        -- if redis_conf.enable_slave_read == nil then
        --     redis_conf.enable_slave_read = true
        -- end
        
        -- 解析redis地址
        for i, conf_item in ipairs(redis_conf.serv_list) do
            local host, port, err = core.utils.parse_addr(conf_item)
            if err then
                core.log.error("无法解析redis地址: " .. conf_item .. " err: " .. err)
            end
            redis_conf.serv_list[i] = {ip = host, port = port}
        end
        redis_conf.dict_name=CLUSTER_DICT_NAME
        redis_policy=cluster
    else
        error("redis policy配置错误")
    end
    core.log.warn("redis_conf:",core.json.delay_encode(redis_conf))
end

local _M={}
local mt = {
    __index = _M
}


setmetatable(_M, {
    __index = function(_, cmd)
        -- cache the lazily generated method in our
        -- module table
        local method = function (self,...)
            -- core.log.warn("phase:",ngx.get_phase())
            if ngx.get_phase() == "timer" then
                return self.red_cli[cmd](self.red_cli,...)
            else
                local start = ngx.now()
                local result,err = self.red_cli[cmd](self.red_cli,...)
                ngx.ctx.red_duration = (ngx.ctx.red_duration or 0) + (ngx.now() - start)
                return result,err
            end
        end
        _M[cmd] = method
        return method
    end
})

function _M.new(self,enable_slave_read)
    if enable_slave_read ~= nil then
        redis_conf.enable_slave_read = enable_slave_read
    end
    local red_cli,err = redis_policy:new(redis_conf)
    if not red_cli then
        return nil,err
    end
    local tab = {
        red_cli = redis_policy:new(redis_conf)
    }
    return setmetatable(tab,mt)
end



return _M