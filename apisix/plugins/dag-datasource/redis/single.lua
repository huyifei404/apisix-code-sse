local redis_c = require "resty.redis"
local read_conf_util=require("apisix.plugins.utils.read_conf_util")
local clone_tab=require "table.clone"
local ngx=ngx
local new_tab=require "table.new"
local core=require "apisix.core"



local _M = new_tab(0, 155)

local DEFAULT_KEEPALIVE_TIMEOUT = 55000
local DEFAULT_KEEPALIVE_CONS = 1000

_M._VERSION = '0.01'


local commands = {
    "append",            "auth",              "bgrewriteaof",
    "bgsave",            "bitcount",          "bitop",
    "blpop",             "brpop",
    "brpoplpush",        "client",            "config",
    "dbsize",
    "debug",             "decr",              "decrby",
    "del",               "discard",           "dump",
    "echo",
    "eval",              "exec",              "exists",
    "expire",            "expireat",          "flushall",
    "flushdb",           "get",               "getbit",
    "getrange",          "getset",            "hdel",
    "hexists",           "hget",              "hgetall",
    "hincrby",           "hincrbyfloat",      "hkeys",
    "hlen",
    "hmget",              "hmset",      "hscan",
    "hset",
    "hsetnx",            "hvals",             "incr",
    "incrby",            "incrbyfloat",       "info",
    "keys",
    "lastsave",          "lindex",            "linsert",
    "llen",              "lpop",              "lpush",
    "lpushx",            "lrange",            "lrem",
    "lset",              "ltrim",             "mget",
    "migrate",
    "monitor",           "move",              "mset",
    "msetnx",            "multi",             "object",
    "persist",           "pexpire",           "pexpireat",
    "ping",              "psetex",            "psubscribe",
    "pttl",
    "publish",      --[[ "punsubscribe", ]]   "pubsub",
    "quit",
    "randomkey",         "rename",            "renamenx",
    "restore",
    "rpop",              "rpoplpush",         "rpush",
    "rpushx",            "sadd",              "save",
    "scan",              "scard",             "script",
    "sdiff",             "sdiffstore",
    "select",            "set",               "setbit",
    "setex",             "setnx",             "setrange",
    "shutdown",          "sinter",            "sinterstore",
    "sismember",         "slaveof",           "slowlog",
    "smembers",          "smove",             "sort",
    "spop",              "srandmember",       "srem",
    "sscan",
    "strlen",       --[[ "subscribe",  ]]     "sunion",
    "sunionstore",       "sync",              "time",
    "ttl",
    "type",         --[[ "unsubscribe", ]]    "unwatch",
    "watch",             "zadd",              "zcard",
    "zcount",            "zincrby",           "zinterstore",
    "zrange",            "zrangebyscore",     "zrank",
    "zrem",              "zremrangebyrank",   "zremrangebyscore",
    "zrevrange",         "zrevrangebyscore",  "zrevrank",
    "zscan",
    "zscore",            "zunionstore",       "evalsha", 
}


local mt = { __index = _M }


local function is_redis_null( res )
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

function _M.array_to_hash(tab)
    if tab==nil then
        return {}
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


-- change connect address as you need
function _M.connect_mod( self, redis )
    redis:set_timeout(self.timeout)
    return redis:connect(self.host, self.port)
end


function _M.set_keepalive_mod(self, redis )
    return redis:set_keepalive(self.keepalive_timeout or DEFAULT_KEEPALIVE_TIMEOUT, self.keepalive_cons or DEFAULT_KEEPALIVE_CONS)
end


function _M.init_pipeline( self )
    self._reqs = {}
end


function _M.commit_pipeline( self )
    local reqs = self._reqs

    if nil == reqs or 0 == #reqs then
        return {}, "no pipeline"
    else
        self._reqs = nil
    end

    local redis, err = redis_c:new()
    if not redis then
        return nil, err
    end
    redis:set_timeouts(self.timeout, self.timeout, self.timeout)
    local ok, err = _M.connect_mod(self,redis)
    if not ok then
        core.log.error("redis connect error:",err)
        return nil, err
    end
    local count
    count, err = redis:get_reused_times()
    if 0 == count then
        if self.password and self.password ~= '' then
            local ok, err = redis:auth(self.password)
            if not ok then
                core.log.warn("auth err:",err)
                return nil, err
            end
        end
    elseif err then
        -- core.log.info(" err: ", err)
        return nil, err
    end

    redis:init_pipeline()
    for _, vals in ipairs(reqs) do
        local fun = redis[vals[1]]
        table.remove(vals , 1)

        fun(redis, table.unpack(vals))
    end

    local results, err = redis:commit_pipeline()
    if not results or err then
        return nil, err
    end

    if is_redis_null(results) then
        results = {}
        ngx.log(ngx.WARN, "is null")
    end
    -- table.remove (results , 1)

    self.set_keepalive_mod(self,redis)

    for i,value in ipairs(results) do
        if is_redis_null(value) then
            results[i] = nil
        end
    end
    self._reqs=nil
    return results, err
end


function _M.subscribe( self, channel )
    local redis, err = redis_c:new()
    if not redis then
        return nil, err
    end
    redis:set_timeouts(self.timeout, self.timeout, self.timeout)

    local ok, err = _M.connect_mod(self,redis)
    if not ok or err then
        core.log.error("redis connect error:",err)
        return nil, err
    end
    local count
    count, err = redis:get_reused_times()
    if 0 == count then
        if self.password and self.password ~= '' then
            local ok, err = redis:auth(self.password)
            if not ok then
                return nil, err
            end
        end
    elseif err then
        -- core.log.info(" err: ", err)
        return nil, err
    end

    local res, err = redis:subscribe(channel)
    if not res then
        return nil, err
    end

    res, err = redis:read_reply()
    if not res then
        return nil, err
    end

    redis:unsubscribe(channel)
    self.set_keepalive_mod(self,redis)

    return res, err
end


function _M.do_command(self, cmd, ... )
    if self._reqs then
        table.insert(self._reqs, {cmd, ...})
        return
    end

    local redis, err = redis_c:new()
    if not redis then
        return nil, err
    end
    redis:set_timeouts(self.timeout, self.timeout, self.timeout)
    local ok, err = _M.connect_mod(self,redis)
    if not ok or err then
        core.log.error("redis connect error:",err)
        return nil, err
    end
    local count
    count, err = redis:get_reused_times()
    if 0 == count then
        if self.password and self.password ~= '' then
            local ok, err = redis:auth(self.password)
            if not ok then
                core.log.warn("auth err:",err)
                return nil, err
            end
        end
    elseif err then
        -- core.log.info(" err: ", err)
        return nil, err
    end

    local fun = redis[cmd]
    local result, err = fun(redis, ...)
    if not result or err then
        -- ngx.log(ngx.ERR, "pipeline result:", result, " err:", err)
        return nil, err
    end

    if is_redis_null(result) then
        result = nil
    end

    self.set_keepalive_mod(self,redis)

    return result, err
end


for i = 1, #commands do
    local cmd = commands[i]
    _M[cmd] =
            function (self, ...)
                return _M.do_command(self, cmd, ...)
            end
end


function _M.new(self, opts)
    opts = opts or {}
    local timeout = (opts.timeout and opts.timeout * 1000) or 1000
    local db_index= opts.db_index or 0
    return setmetatable({
            timeout = timeout,
            keepalive_timeout=opts.keepalive_timeout,
            keepalive_cons=opts.keepalive_cons,
            host=opts.host,
            port=opts.port,
            password=opts.password,
            db_index = db_index,
            _reqs = nil }, mt)
end


return _M