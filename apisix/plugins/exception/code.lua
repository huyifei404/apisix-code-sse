
-- 错误码定义
local _M={
    DAG_SUCCESS=0,                      -- 成功
    DAG_ERR_NULL_POINT=1,               -- 遇到空指针
    DAG_ERR_SKIMP_SIZE=2,               -- 分配的内存大小不够
    DAG_ERR_QUEUE_NOTINIT=3,            -- 队列未初始化
    DAG_ERR_XML_FORMAT=4,               -- xml文档格式不符合标准
    DAG_ERR_MEM_RECORD_NOTFOUND=5,      -- 内存数据库中数据不存在
    DAG_ERR_GET_SEQ=6,                  -- 取流水失败
    DAG_ERR_PROCESS_TYPE=7,             -- 不合法的过程类型
    DAG_ERR_PROPERTY_VALUE=8,           -- 不合法的配置属性
    DAG_ERR_CONNECT_STRING=9,           -- 不合法的数据库连接参数
    DAG_ERR_CONNECT_DB=10,              -- 数据库连接失败
    DAG_ERR_PLUGIN=11,                  -- 插件不存在
    DAG_ERR_COMMAND=12,                 -- 无效的管理名称
    DAG_ERR_SFDL=13,                    -- SFDL不合规范
    DAG_ERR_ARG=14,                     -- 无效的命令行参数
    DAG_ERR_EMPTY_FUNC=15,              -- 未实现的函数
    DAG_ERR_SYS_BUSY=16,                -- 系统繁忙
    DAG_ERR_SERVICE_ERR=17,             -- 服务应答报文错误
    DAG_ERR_INVALID_SERVICE_CALL=18,    -- 无效的服务调用
    DAG_ERR_SERVICE_CONF=19,            -- 服务配置错误
    DAG_ERR_REQ_BODY=20,                -- 请求报文错误
    DAG_ERR_BREAKER=21,					-- 熔断
    DAG_ERR_TEMPLATE=22,                -- 编排模板不符合规范
    DAG_ERR_EXEC_TEMPLATE=23,           -- 模板执行错误
    DAG_ERR_ABILITY_NOT_FOUND=24,       -- 未注册能力
    DAG_ERR_LIMITED=25,                 -- 限流插件错误
    DAG_ERR_SQL_INJECTION=26,           -- sql防注入错误
    DAG_ERR_IP_NOT_ALLOW=27,            -- IP不允许访问
    DAG_ERR_INVALID_URI=28,             -- 不允许调用无效的uri
    DAG_ERR_REDIS_SCRIPT=29,            -- redis数据库执行脚本失败
    DAG_ERR_INVALID_METHOD=30,          -- 无效请求方法
    DAG_ERR_PARAM_LIMIT=31,             -- 请求参数数量超出限制
    DAG_ERR_UNKNOWN=99,                 -- 未知错误

    DAG_AMG_REQ = 100,                  -- AMG请求错误
    DAG_AMG_CONF_ERR = 101,             -- AMG相关配置错误


    DAG_ERR_ROUTE_UNREGISTER                     = 1000, --未注册该能力：xxx
    DAG_ERR_ROUTE_BODY_EMPTY                     = 1001, --body为空,无法解析请求信息
    DAG_ERR_ROUTE_PARAM_TOO_LONG                 = 1002, --请求参数超出限制
    DAG_ERR_ROUTE_XML_FORMAT_ERR                 = 1003, --获取xml报文编码失败，报文格式错误，未知格式
    DAG_ERR_ROUTE_NOT_FOUND_APICODE              = 1004, --系统错误，模板无法从报文提取能力code

    DAG_ERR_SERVICE_CALL_URL_EMPTY               = 2000, --服务配置错误，主地址url数量为0
    DAG_ERR_SERVICE_CALL_TIMEOUT                 = 2001, --服务调用超时,url：xxx,timeout:xxxms
    DAG_ERR_SERVICE_CALL_FAIL                    = 2002, --服务调用失败,url:xxx,erroe_msg:xxx
    DAG_ERR_SERVICE_CALL_UNREGISTER              = 2003, --未注册该服务:xxxxxx
    DAG_ERR_SERVICE_CALL_ROUTE_EMPTY             = 2004, --服务路由组实体查询反回空:xxx
    DAG_ERR_SERVICE_CALL_CITY_ROUTE_NOT_FOUND    = 2005, --服务路由组中不存在当前请求的地市配置:xxx
    DAG_ERR_SERVICE_CALL_NOT_FOUND_CITY_CONFIG   = 2006, --服务未查询到相关的分地市配置:xxx
    DAG_ERR_SERVICE_CALL_CITY_ROUTEID_UNDEFINE   = 2007, --分地市使用路由组，但id未配置:xxx
    DAG_ERR_SERVICE_CALL_FORMAT                  = 2008, --服务报文格式配置错误
    DAG_ERR_SERVICE_CREATE_FORM_DATA             = 2009, --生成服务的form-data报文失败
    DAG_ERR_SERVICE_FORM_DATA_PARSE              = 2010, --请求报文错误，form-data内容无法解析

    DAG_ERR_SERVICE_CALL_SERVICE_ROUTE           = 2020, --查询服务路由组实体失败:xxx
    DAG_ERR_SERVICE_CALL_LIMITED_FAIL            = 2021, --服务限流执行失败：xxx
    DAG_ERR_SERVICE_CALL_LIMITED                 = 2022, --服务被限流
    DAG_ERR_SERVICE_CALL_QUREY_DRAG              = 2023, --服务灰度错误1.?查询灰度路由失败2.?灰度路由地址配置错误，解析地址失败
    DAG_ERR_SERVICE_CALL_SERVICE_PARAM_ERR       = 2024, --程序错误，格式设置错误:xxx(服务format参数错误），程序错误，编码设置错误（服务encoding参数错误）
    DAG_ERR_SERVICE_CALL_PARSE_MSG               = 2025, --内部错误，服务GET请求无法解析从模板返回的报文,err：xxx,body:xxx

    DAG_ERR_CONFIGURED                           = 2026, --根据配置的返回码判断为系统失败

    DAG_ERR_IP_PERMISSION                        = 3000, --ip-restriction client IP: xx.xx.xx.xx not allow access(ip黑白名单校验）
    DAG_ERR_IP_NO_PERMISSION                     = 3001, --该IP未获得授权：xxxxxxx

    DAG_ERR_REDIS_INIT                           = 6666, --redis客户端实例化失败...

    DAG_ERR_TENANT_NOT_FOUND_DEVELOPER           = 5000, --缺少app-developer的配置信息
    DAG_ERR_TENANT_AUTH                          = 5001, --缺少租户-应用的关联关系

    DAG_ERR_APPID_EMPTY                          = 6000, --app_id不能为空
    DAG_ERR_APP_TOKEN_AUTH_EMPTY                 = 6001, --缺少token-auth的应用配置信息
    DAG_ERR_APP_UNREGISTER                       = 6002, --未注册该应用...
    DAG_ERR_APP_ACCESS_AUTH_EMPTY                = 6003, --上下文没有access_token
    DAG_ERR_APP_TOKEN_INVALID                    = 6004, --应用token无效
    DAG_ERR_APP_TOKEN_TIME_ERR                   = 6005, --token的开始时间必须小于系统当前时间，结束时间必须大于系统当前时间
    DAG_ERR_APP_TOKEN_UNKNOWN                    = 6010, --token-auth未知错误

    DAG_ERR_TEMPLATE_MATCH_ERR                   = 7000, --协议模板匹配失败
    DAG_ERR_TEMPLATE_NOT_FOUND_TPLID             = 7001, --未定义该模板或者模板版本
    DAG_ERR_TEMPLATE_PARSE_ERR                   = 7002, --解析模板错误...
    DAG_ERR_TEMPLATE_EXC_ERR                     = 7003, --模板执行错误...
    DAG_ERR_TEMPLATE_QUREY_SERVICE_ERR           = 7004, --模板服务信息配置错误...（模板需要的服务信息查询失败）
    DAG_ERR_TEMPLATE_GET_TPL_ERR                 = 7010, --获取请求模板失败…
    DAG_ERR_TEMPLATE_CONFIG_SERVICE_ERR          = 7011, --服务配置错误...（为模板注入服务信息报错）
    DAG_ERR_TEMPLATE_INIT_ERR                    = 7012, --模板数据未初始化完成，无法正常响应

    DAG_ERR_CALL_BREAKER                         = 8000, --触发熔断

    DAG_ERR_TRADE_PERMISSION_NO_CONFIG           = 9000, --缺少trade-permission的应用配置信息(应用未做任何授权)
    DAG_ERR_TRADE_PERMISSION_API_NO_PERMISSION   = 9001, --能力没有权限访问,能力编码:[xxx]
    DAG_ERR_TRADE_PERMISSION_SCENE_NO_PERMISSION = 9002, --场景没有权限访问,场景编码:[xxx]
    DAG_ERR_TRADE_PERMISSION_NOT_FOUND_CONSUMER  = 9010, --trade-permission缺少app_consumer信息（未执行应用认证)
    DAG_ERR_TRADE_PERMISSION_QUERY_SCENE_ERR     = 9011, --trade-permission取scene_list配置出错
    DAG_ERR_TRADE_PERMISSION_QUERY_ABILITY_ERR   = 9012, --trade-permission取ability_list配置出错

    DAG_ERR_LIMITED_REQUEST_OUT_RATE_LIMIT       = 4001, --请求速率超出限制,请求被拒绝
    DAG_ERR_LIMITED_UNKNOWN                      = 4011, --系统未知错误,限流错误返回…
    DAG_ERR_LIMITED_EXC_SCRIPT_ERR               = 4012, --漏桶限流执行redis脚本失败…
    DAG_ERR_LIMITED_TOKEN_BUCKET_ERR             = 4002, --令牌桶限流错误
    DAG_ERR_LIMITED_REQUEST_OUT_NUM_LIMIT        = 4003, --同时请求超过限流令牌最大数目
    DAG_ERR_LIMITED_NOT_FOUND_PROCESS_CODE       = 4004, --process_code not found
    DAG_ERR_CONDITION_BREAKER                    = 20016,-- 规则熔断
}

return _M
