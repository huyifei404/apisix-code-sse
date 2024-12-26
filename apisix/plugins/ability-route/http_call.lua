local core                          = require("apisix.core")
local http                          = require("resty.http")
local exception_util                = require("apisix.plugins.exception.util")
local err_type                      = require("apisix.plugins.exception.type")
local err_code                      = require("apisix.plugins.exception.code")
local get_app_service_conf          = require("apisix.plugins.app-service-auth").get_plugins_conf
local retry_overtime                = require("apisix.plugins.retry-overtime")
local string_util                   = require("apisix.plugins.utils.string_util")
local read_conf_util                = require("apisix.plugins.utils.read_conf_util")
local ngx                           = ngx
local updata_time                   = ngx.update_time
local time_now                      = ngx.now
local emergency_log                 = require("apisix.plugins.emergency-log").g_log
local json_delay_encode             = core.json.delay_encode
local new_tab = require "table.new"

local sw8                           = require("apisix.plugins.sw-prefix")

local _M = {version = 0.1}

local service_http_conf = read_conf_util.get_conf("service_http") or {}
local HTTP_KEEPALIVE_POOL = service_http_conf.keepalive_pool or 2000
local HTTP_KEEPALIVE_TIMEOUT = service_http_conf.keepalive_timeout or 15000

-- ===================================私有方法======================================
-- 服务单次请求
local function http_req(url, httpc, method, body, headers,service_log)
    core.log.info("服务请求url:",url)
    service_log.url = url
    local res, err = httpc:request_uri(url, {
        method = method,
        body = body or "",
        headers = headers,
        ssl_verify = false,
        keepalive = true,
        keepalive_pool = HTTP_KEEPALIVE_POOL,
        keepalive_timeout = HTTP_KEEPALIVE_TIMEOUT
    })
    -- 调用dubbo服务出现连接异常关闭的问题
    if not res and (err == "closed" or err == "connection reset by peer") then
        core.log.info("连接异常,重新建立连接:", err)
        httpc:close()
        -- 重试请求
        res, err = httpc:request_uri(url, {
            method = method,
            body = body or "",
            headers = headers,
            ssl_verify = false,
            keepalive = true,
            keepalive_pool = HTTP_KEEPALIVE_POOL,
            keepalive_timeout = HTTP_KEEPALIVE_TIMEOUT
        })
    end

    return res, err
end

-- @param app_id string:应用id
-- @param service_name string: 服务名
-- @return number retry_type: 重试类型，1源地址重试，2 多地址重试
-- @return number retries : 重试次数，源地址重试时对同一地址的重试次数
-- @return number timeout: 服务调用超时时长，单位：秒
local function get_timeout_retries(app_id, service_name)
    local plugin_name = retry_overtime.name
    local plugins_conf = get_app_service_conf(app_id, service_name or "")
    if not plugins_conf then
        return 1, 1, 30000
    end
    local conf = plugins_conf[plugin_name]
    if not conf then
        return 1, 1, 30000
    end
    core.log.info("conf:", core.json.delay_encode(conf))
    return conf.retry_type, conf.retries, conf.timeout
end

local function print_urls(urls)
    if urls == nil then
        return "nil"
    end
    if type(urls) == "string" then
        return urls
    end
    local str = "["
    local len = #urls
    for i = 1,len,1 do
        str = str .. urls[i]
        if i < len then
            str = str .. ","
        end
    end
    str = str .. "]"
    return str
end

function _M.long_call(req_info, service_info, req_body, headers,ctx)
    core.log.info("long_call_service_info:",core.json.delay_encode(service_info))
    --重试类型，重试次数，超时时长
    local retry_type, retries, timeout = get_timeout_retries(req_info.app_id or "", service_info.CODE)
    -- httpc初始化
    local httpc = http.new()
    httpc:set_timeout(timeout)
    if #service_info.ADDRESS == 0 then
        return nil, exception_util.build_err_tab(err_type.EXCEPT_MEMDB,
                                                 err_code.DAG_ERR_SERVICE_CALL_URL_EMPTY,
                                                 "【NY】服务配置错误，主地址url数量为0")
    end
    -- 头部参数过滤
    headers["host"] = nil
    headers["Host"] = nil
    local service_log=new_tab(5,0)
    local encoding = service_info.ENCODING
    local format = service_info.FORMAT
    local res, err ,target_url = retry_overtime.service_retry(service_info.ADDRESS, retries,
    retry_type, http_req, httpc,
    service_info.HTTPMETHOD, req_body, headers,service_log)

    if not res then
        core.log.error("请求id:",ctx.req_id,"服务code:",service_info.CODE)
        core.log.error("请求id:",ctx.req_id,"服务调用方法:",service_info.HTTPMETHOD)
        core.log.error("请求id:",ctx.req_id,"服务调用地址:",print_urls(target_url))
        core.log.error("请求id:",ctx.req_id,"服务请求头:",core.json.delay_encode(headers))
        core.log.error("请求id:",ctx.req_id,"服务请求报文:",req_body or "")
        req_info.res_status = 500
        if err == "timeout" then
            core.log.error("请求id:",ctx.req_id,"服务调用超时")
            core.log.error("请求id:",ctx.req_id,"服务timeout:",timeout)
            return nil, exception_util.build_err_tab(err_type.EXCEPT_TIMEOUT,
                                                     err_code.DAG_ERR_SERVICE_CALL_TIMEOUT,
                                                     "【NY】"..service_info.CODE.."服务调用超时,url:"..print_urls(target_url).. ",timeout:"..timeout .. "ms")
        end
        core.log.error("请求id:",ctx.req_id,"服务调用错误:",err)
        return nil,exception_util.build_err_tab(err_type.EXCEPT_MIDDLE,
                                                err_code.DAG_ERR_SERVICE_CALL_FAIL,
                                                "【NY】"..service_info.CODE.."服务调用失败,url:" .. print_urls(target_url) .. "err_msg:" .. err)

    end
    req_info.res_status = res.status
    if res.status ~=200 then
        core.log.error("请求id:",ctx.req_id,",服务调用方法:",service_info.HTTPMETHOD)
        core.log.error("请求id:",ctx.req_id,",服务调用地址:",print_urls(target_url))
        core.log.error("请求id:",ctx.req_id,",服务请求头:",core.json.delay_encode(headers))
        core.log.error("请求id:",ctx.req_id,",服务请求报文:",req_body or "")
        core.log.error("请求id:",ctx.req_id,",服务调用失败,错误状态码:",res.status)
        core.log.error("请求id:",ctx.req_id,",服务响应报文:",res.body)
        return nil, exception_util.build_err_tab(err_type.EXCEPT_MIDDLE,
                                                 err_code.DAG_ERR_SERVICE_CALL_FAIL,
                                                 "【NY】"..service_info.CODE.."服务调用失败,url:" ..print_urls(target_url) .. ",status:" .. res.status .. ",body:" .. (res.body or "nil"))
    end  
    core.log.info("请求id:",ctx.req_id,",服务调用响应头:",core.json.delay_encode(res.headers))
    core.log.info("请求id:",ctx.req_id,",服务调用响应报文:",res.body)
    req_info.sys.es_flag = 0
    res.body = res.body or ""
    if format == "XML" then
        if encoding == "UTF-8" then
            res.body = string_util.check_xml_declaration(res.body,2)
        else
            res.body = string_util.check_xml_declaration(res.body,1)
        end
    end
    return res
end

-- ===================================模块方法======================================

function _M.call(req_info, service_info, req_body, headers,ctx)
    core.log.info("service_info:",core.json.delay_encode(service_info))
    -- 重试类型，重试次数，超时时长
    local retry_type, retries, timeout = get_timeout_retries(req_info.sys.app_id or "", service_info.CODE)
    -- httpc初始化
    local httpc = http.new()
    httpc:set_timeout(timeout)

    if #service_info.ADDRESS == 0 then
        return nil, exception_util.build_err_tab(err_type.EXCEPT_MEMDB,
                                                 err_code.DAG_ERR_SERVICE_CALL_URL_EMPTY,
                                                 "【NY】服务配置错误，主地址url数量为0")
    end
    -- core.log.info("url:", service_info.ADDRESS[1])
    emergency_log(ctx,"服务请求urls:",json_delay_encode(service_info.ADDRESS))

    -- 头部参数过滤
    headers["host"] = nil
    headers["Host"] = nil
    ------------------

    -- 存储服务调用日志信息
    local encoding = service_info.ENCODING
    local format = service_info.FORMAT
    local service_log=req_info.services[#req_info.services]
    service_log.service_code=service_info.CODE
    service_log.format=format
    service_log.applyer_id=service_info.APPLYERID
    service_log.encoding=encoding
    service_log.req_body=req_body or ""
    service_log.req_headers = headers
    -- updata_time()
    service_log.start_time=time_now()*1000
    -- skywalking
    sw8.service_start(ctx,service_info)

    emergency_log(ctx,"服务请求头:",json_delay_encode(headers))
    emergency_log(ctx,"服务请求body:",req_body)
    core.log.info("服务请求头:",json_delay_encode(headers))
    core.log.info("服务请求body:",req_body or "nil")
    -- 服务调用

    local res, err ,target_url = retry_overtime.service_retry(service_info.ADDRESS, retries,
                                                  retry_type, http_req, httpc,
                                                  service_info.HTTPMETHOD, req_body, headers,service_log)
    -- skywalking
    sw8.service_finish(ctx,200)
    -- 存储服务调用日志信息
    -- updata_time()
    -- 改为传入http调用函数，由函数为url赋值
    -- service_log.url=target_url or ""
    service_log.end_time=time_now()*1000
    service_log.status = res and res.status
    service_log.resp_body=res and res.body or ""
    service_log.resp_headers =res and res.headers or {}
    -- 异常处理
    if not res then
        core.log.error("请求id:",ctx.req_id,"服务code:",service_info.CODE)
        core.log.error("请求id:",ctx.req_id,"服务调用方法:",service_info.HTTPMETHOD)
        core.log.error("请求id:",ctx.req_id,"服务调用地址:",print_urls(target_url))
        core.log.error("请求id:",ctx.req_id,"服务请求头:",core.json.delay_encode(headers))
        core.log.error("请求id:",ctx.req_id,"服务请求报文:",req_body or "")
        req_info.res_status = 500
        if err == "timeout" then
            core.log.error("请求id:",ctx.req_id,"服务调用超时")
            core.log.error("请求id:",ctx.req_id,"服务timeout:",timeout)
            return nil, exception_util.build_err_tab(err_type.EXCEPT_TIMEOUT,
                                                     err_code.DAG_ERR_SERVICE_CALL_TIMEOUT,
                                                     "【NY】"..service_info.CODE.."服务调用超时,url:"..print_urls(target_url).. ",timeout:"..timeout .. "ms")
        end
        core.log.error("请求id:",ctx.req_id,"服务调用错误:",err)
        return nil,exception_util.build_err_tab(err_type.EXCEPT_MIDDLE,
                                                err_code.DAG_ERR_SERVICE_CALL_FAIL,
                                                "【NY】"..service_info.CODE.."服务调用失败,url:" .. print_urls(target_url) .. "err_msg:" .. err)
    end
    req_info.res_status = res.status
    if res.status ~=200 then
        core.log.error("请求id:",ctx.req_id,",服务调用方法:",service_info.HTTPMETHOD)
        core.log.error("请求id:",ctx.req_id,",服务调用地址:",print_urls(target_url))
        core.log.error("请求id:",ctx.req_id,",服务请求头:",core.json.delay_encode(headers))
        core.log.error("请求id:",ctx.req_id,",服务请求报文:",req_body or "")
        core.log.error("请求id:",ctx.req_id,",服务调用失败,错误状态码:",res.status)
        core.log.error("请求id:",ctx.req_id,",服务响应报文:",res.body)
        return nil, exception_util.build_err_tab(err_type.EXCEPT_MIDDLE,
                                                 err_code.DAG_ERR_SERVICE_CALL_FAIL,
                                                 "【NY】"..service_info.CODE.."服务调用失败,url:" ..print_urls(target_url) .. ",status:" .. res.status .. ",body:" .. (res.body or "nil"))
    end
    -- core.log.warn("请求id:",ctx.req_id,",服务调用响应头:",core.json.delay_encode(res.headers))
    -- core.log.warn("请求id:",ctx.req_id,",服务调用响应报文:",res.body)
    emergency_log(ctx,"服务调用响应头:",json_delay_encode(res.headers))
    emergency_log(ctx,"服务调用响应报文:",res.body or "nil")
    -- 主备调用标志(在实现主备调用后。。)
    req_info.sys.es_flag = 0
    res.body = res.body or ""
    if format == "XML" then
        if encoding == "UTF-8" then
            res.body = string_util.check_xml_declaration(res.body,2)
        else
            res.body = string_util.check_xml_declaration(res.body,1)
        end
    end
    return res
end

return _M
