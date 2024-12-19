local err_code=require("apisix.plugins.exception.code")

local _M={
    [err_code.DAG_SUCCESS]=200,                      -- 成功
    [err_code.DAG_ERR_NULL_POINT]=500,               -- 遇到空指针
    [err_code.DAG_ERR_SKIMP_SIZE]=500,               -- 分配的内存大小不够
    [err_code.DAG_ERR_QUEUE_NOTINIT]=500,            -- 队列未初始化
    [err_code.DAG_ERR_XML_FORMAT]=500,               -- xml文档格式不符合标准
    [err_code.DAG_ERR_MEM_RECORD_NOTFOUND]=500,      -- 内存数据库中数据不存在
    [err_code.DAG_ERR_GET_SEQ]=500,                  -- 取流水失败
    [err_code.DAG_ERR_PROCESS_TYPE]=500,             -- 不合法的过程类型
    [err_code.DAG_ERR_PROPERTY_VALUE]=500,           -- 不合法的配置属性
    [err_code.DAG_ERR_CONNECT_STRING]=500,           -- 不合法的数据库连接参数
    [err_code.DAG_ERR_CONNECT_DB]=500,              -- 数据库连接失败
    [err_code.DAG_ERR_PLUGIN]=500,                  -- 插件不存在
    [err_code.DAG_ERR_COMMAND]=500,                 -- 无效的管理名称
    [err_code.DAG_ERR_SFDL]=500,                    -- SFDL不合规范
    [err_code.DAG_ERR_ARG]=500,                     -- 无效的命令行参数
    [err_code.DAG_ERR_EMPTY_FUNC]=500,              -- 未实现的函数
    [err_code.DAG_ERR_SYS_BUSY]=500,                -- 系统繁忙
    [err_code.DAG_ERR_SERVICE_ERR]=500,             -- 服务应答报文错误
    [err_code.DAG_ERR_INVALID_SERVICE_CALL]=400,    -- 无效的服务调用
    [err_code.DAG_ERR_SERVICE_CONF]=500,            -- 服务配置错误
    [err_code.DAG_ERR_REQ_BODY]=415,                -- 请求报文错误
    [err_code.DAG_ERR_BREAKER]=500,					-- 熔断
    [err_code.DAG_ERR_TEMPLATE]=500,                -- 编排模板不符合规范
    [err_code.DAG_ERR_EXEC_TEMPLATE]=500,           -- 模板执行错误
    [err_code.DAG_ERR_ABILITY_NOT_FOUND]=404,       -- 未注册能力
    [err_code.DAG_ERR_LIMITED]=403,                 -- 限流插件错误
    [err_code.DAG_ERR_SQL_INJECTION]=403,           -- sql防注入错误
    [err_code.DAG_ERR_IP_NOT_ALLOW]=403,            -- IP不允许访问
    [err_code.DAG_ERR_INVALID_URI]=404,             -- 不允许调用无效的uri
    [err_code.DAG_ERR_UNKNOWN]=500,                 -- 未知错误
}

return _M