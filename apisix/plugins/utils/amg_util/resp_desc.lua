
local _M = {
    ["ERR_MISS_ARG"]                        = "Missing Required Arguments",                     -- 缺少必填参数
    ["ERR_ARG_INVALID_CHARACTER"]           = "xss chars included in params, such as ",         -- 请求参数中带有以下字符：<, >, ', "
    ["ERR_API_CODE_NOT_EXIST"]              = "Api code not exist",                             -- api code 不存在
    ["ERR_API_VERSION_NOT_EXIST"]           = "Api version not exist",                          -- api version 不存在
    ["ERR_SCENARIO_CODE_NOT_EXIST"]         = "Scenario code not exist",                        -- scenario code 不存在
    ["ERR_SCENARIO_VERSION_NOT_EXIST"]      = "Scenario version not exist",                     -- scenario version 不存在
    ["ERR_ABILITY_CODE_NOT_EXIST"]          = "Ability code not exist",                         -- ability code 不存在
    ["ERR_APP_KEY_NOT_EXIST"]               = "App key not exist",                              -- app key 不存在
    ["ERR_TIMESTAMP_ILLEGAL"]               = "Timestamp illegal",                              -- timestamp 非法
    ["ERR_TIMESTAMP_OUT_OF_RANGE"]          = "Timestamp 5 minutes beyond the  standard time",  -- timestamp 误差超过标准时间5分钟
    ["ERR_AUTHENTICATION"]                  = "Authentication reject ",                         -- 身份认证，拒绝访问
    ["ERR_AUTHORIZATION"]                   = "Authorization reject",                           -- 权限认证，拒绝访问
    ["ERR_APP_CALL_LIMIT_COUNT"]            = "App Call Limited",                               -- 应用超过使用总量限制
    ["ERR_APP_CALL_LIMIT_FREQUENCY"]        = "App Call Exceeds Limited Frequency",             -- 应用调用频率超过限制
    ["ERR_SERVICE_RATE_LIMIT"]              = "exceed service rate limit",                      -- 超过服务提供方处理能力上限
    ["ERR_SERVICE_PROVIDER_TIMEOUT"]        = "Service provider timeout",                       -- 服务提供方超时
    ["ERR_REJECT_APP_LEVEL"]                = "Reject by AMG because of App level",             -- 应用级别未达到AMG设定的等级限制
    ["ERR_REJECT_SERVICE_LEVEL"]            = "Reject by AMG because of service level",         -- 服务级别未达到AMG设定的等级限制
    ["ERR_REJECT_SERVICE"]                  = "Reject by service",                              -- 应用级别未达服务设定的等级限制
    ["ERR_CIRCUIT_BREAK"]                   = "Circuit break",                                  -- AMG调用服务提供方时熔断
    ["ERR_REJECT_IP"]                       = "IP reject",                                      -- IP黑白名单检查，拒绝访问
    ["ERR_DECRYPT_CALL_HISTORY"]            = "Call history decrypt failed",                    -- call-history解密失败
    ["ERR_SCENARIO_CHECK"]                  = "Bypass check failed",                            -- 场景防绕行校验失败
    ["ERR_SERVICE_CALL_LOOP"]               = "Service call infinite loop detected",            -- 服务调用死循环

    ["ERR_ENTITY_IS_NULL"]                  = "The entity information query is empty",          -- 实体信息查询为空

    ["ERR_SERVER_INTERNAL"]                 = "SERVER ERROR:",                                  -- 系统内部错误，请重试
    ["ERR_SERVICE_UNAVAILABLE"]             = "Service Currently Unavailable"                   -- 被调用服务不可用
}

return _M
