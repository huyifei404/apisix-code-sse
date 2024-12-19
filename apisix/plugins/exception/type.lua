

-- 异常类型定义
local _M={
    EXCEPT_BUSINESS=1,      -- 业务错误
    EXCEPT_DB=-1,           -- 数据库异常
    EXCEPT_OS=-2,           -- 操做系统异常
    EXCEPT_MIDDLE=-3,       -- 中间件异常
    EXCEPT_TIMEOUT=-4,      -- 超时异常
    EXCEPT_FORMAT=-5,       -- 报文异常
    EXCEPT_MEMDB=-8,        -- 内存数据库错误
    EXCEPT_BSSP=-7,         -- BSSP内部错误

    EXCEPT_DAG=-17,         -- 能力网关内部错误
    EXCEPT_BREAKER=-18,     -- 熔断
    EXCEPT_REQUEST=-19,     -- 请求错误
    EXCEPT_LIMITED=-20,         -- 限流
    EXCEPT_SQL_INJECTION=-21,   -- sql防注入
    EXCEPT_AMG = -22,           -- AMG请求错误

    --EXCEPT_ROUTE=-11,             --能力路由错误
    --EXCEPT_SERVICE_CALL=-12,      --服务调用错误
    --EXCEPT_IP_RESTRICTION=-13,    --IP黑白名单
    --EXCEPT_REDIS=-14,             --redis
    --EXCEPT_TENANT_AUTH=-15,       --租户认证
    --EXCEPT_APP_SERVICE_AUTH=-16,  --应用认证
    --EXCEPT_TEMPLATE=-17,          --协议模板
    --EXCEPT_CALL_BREAKER=-18,      --熔断
    --EXCEPT_TRADE_PERMISSION=-19,  --应用鉴权
    --EXCEPT_CALL_LIMITED=-20       --限流
}

return _M