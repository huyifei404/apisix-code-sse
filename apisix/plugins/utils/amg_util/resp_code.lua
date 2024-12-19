
local _M={
    ["ERR_MISS_ARG"]=10000,                     -- 缺少必填参数
    ["ERR_ARG_INVALID_CHARACTER"]=11004,        -- 请求参数中带有以下字符：<, >, ', "
    ["ERR_API_CODE_NOT_EXIST"]=11005,           -- api code 不存在
    ["ERR_API_VERSION_NOT_EXIST"]=11006,        -- api version 不存在
    ["ERR_SCENARIO_CODE_NOT_EXIST"]=11007,      -- scenario code 不存在
    ["ERR_SCENARIO_VERSION_NOT_EXIST"]=11008,   -- scenario version 不存在
    ["ERR_ABILITY_CODE_NOT_EXIST"]=11009,       -- ability code 不存在
    ["ERR_APP_KEY_NOT_EXIST"]=110010,           -- app key 不存在
    ["ERR_TIMESTAMP_ILLEGAL"]=110011,           -- timestamp 非法
    ["ERR_TIMESTAMP_OUT_OF_RANGE"]=110012,       -- timestamp 误差超过标准时间5分钟
    ["ERR_AUTHENTICATION"]=20001,               -- 身份认证，拒绝访问
    ["ERR_AUTHORIZATION"]=20002,                -- 权限认证，拒绝访问
    ["ERR_APP_CALL_LIMIT_COUNT"]=20003,         -- 应用超过使用总量限制
    ["ERR_APP_CALL_LIMIT_FREQUENCY"]=20004,     -- 应用调用频率超过限制
    ["ERR_SERVICE_RATE_LIMIT"]=20005,           -- 超过服务提供方处理能力上限
    ["ERR_SERVICE_PROVIDER_TIMEOUT"]=20006,     -- 服务提供方超时
    ["ERR_REJECT_APP_LEVEL"]=20007,             -- 应用级别未达到AMG设定的等级限制
    ["ERR_REJECT_SERVICE_LEVEL"]=20008,         -- 服务级别未达到AMG设定的等级限制
    ["ERR_REJECT_SERVICE"]=20009,               -- 应用级别未达到服务设定的等级限制
    ["ERR_CIRCUIT_BREAK"]=20010,                -- AMG调用服务提供方时熔断
    ["ERR_REJECT_IP"]=20011,                    -- IP黑白名单检查，拒绝访问
    ["ERR_DECRYPT_CALL_HISTORY"]=20012,         -- call history解密失败
    ["ERR_SCENARIO_CHECK"]=20013,               -- 场景绕行调用检查未通过
    ["ERR_SERVICE_CALL_LOOP"]=20014,            -- 服务调用死循环

    ["ERR_ENTITY_IS_NULL"] = 22001,             -- 实体信息查询为空

    ["ERR_SERVER_INTERNAL"]=30000,              -- 系统内部错误，请重试
    ["ERR_SERVICE_UNAVAILABLE"]=31001           -- 被调用服务不可用
}

return _M