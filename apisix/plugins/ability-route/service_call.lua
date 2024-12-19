local core                  = require("apisix.core")
local query_service         = require("apisix.plugins.dag-datasource.query_process.service_query")
local convert_util          = require("apisix.plugins.utils.convert_util")
local http_call             = require("apisix.plugins.ability-route.http_call")
local exception_util        = require("apisix.plugins.exception.util")
local err_type              = require("apisix.plugins.exception.type")
local err_code              = require("apisix.plugins.exception.code")
local gray_route            = require("apisix.plugins.dag-datasource.query_process.gray_route_query")
local upper_str             = string.upper
local ngx                   = ngx
local tab_new               = require("table.new")
local tab_nkeys             = require("table.nkeys")
local tostring              = tostring
local log                   = core.log
local emergency_log         = require("apisix.plugins.emergency-log")
-- local service_limit_util    = require("apisix.plugins.utils.service_limit_util")
local redis_util            = require("apisix.plugins.utils.redis_util")
local business_switch_code      = require("apisix.plugins.utils.redis_util.business_switch")
local new_tab               = require("table.new")
local form_data_util        = require("apisix.plugins.utils.form_data_util")
local snowflake_util        = require("apisix.plugins.utils.snowflake_util")
local pairs                 = pairs
local ipairs                = ipairs
local string_util           = require("apisix.plugins.utils.string_util")
local placeholder_util      = require("apisix.plugins.utils.placeholder_util")
local escape_uri            = ngx.escape_uri

local _M={version=0.1}

-- ===============================私有方法===============================
local function judge_concat_path(service_code,route_value)
    route_value = tostring(route_value or 99)
    local res,err = query_service.get_service_path_concat(service_code)
    if err then
        return nil,"【NY】判断服务path拼接失败:" .. err
    end
    if not res then
        return true
    end
    local enable = "1" == res.ENABLE
    local city_ids = string_util.split(res.CITY_IDS,",")
    local is_include = false
    for _,v in ipairs(city_ids) do
        if route_value == v then
            is_include = true
            break
        end
    end
    return is_include == enable
end

local function concat_path(service_info,url_param,route_value)
    local path = service_info.PATH or ""
    local address = service_info.ADDRESS
    url_param = url_param or ""
    route_value = route_value

    local concat_path_flag = true
    if service_info.is_route_group then
        local ok,err = judge_concat_path(service_info.CODE,route_value)
        if err then
            return nil,exception_util.build_err_tab(err_type.EXCEPT_MEMDB,
                                                err_code.DAG_ERR_UNKNOWN,
                                                err)
        end
        if ok then
            core.log.info("路由组，服务拼接path")
        else
            core.log.info("路由组，服务不拼接path")
            concat_path_flag = false
        end
    else
        core.log.info("服务拼接path")
    end

    if not concat_path_flag then
        path = ""
    end

    for k,v in ipairs(address) do
        -- 变量服务的address,拼接path和url参数，并解析和替换占位符
        address[k] = placeholder_util.replace(v..path .. url_param)
    end

    return true
end

-- 查询服务信息
local function get_service_info(ctx,service_name,app_id,route_value)
    service_name=service_name or ""
    app_id =app_id or ""
    route_value = route_value or 99
    local service_info,err=query_service.get_detail_service(service_name,app_id,route_value)

    -- service_info = clone_service_info(service_info)
    if not service_info then
        core.log.error("服务信息查询失败:",err)
        return nil,exception_util.build_err_tab(err_type.EXCEPT_MEMDB,
                        err_code.DAG_ERR_SERVICE_CONF,"【NY】服务信息查询失败:"..err)
    end
    emergency_log.g_log(ctx,"service_info:",core.json.delay_encode(service_info))

    return service_info
end

-- 配置请求header
local function set_header_param(service_info,header_tab,body_len,content_type,ignore_charset)
    -- 配置请求header
    if not content_type then
        if ignore_charset then
            local cfg_format=upper_str(service_info.FORMAT)
            if cfg_format=="XML" then
                content_type="text/xml"
            elseif cfg_format == "JSON" then
                content_type="application/json"
            else
                core.log.error("服务报文格式配置错误:",service_info.FORMAT)
                return nil,exception_util.build_err_tab(err_type.EXCEPT_MEMDB,
                            err_code.DAG_ERR_SERVICE_CALL_FORMAT,
                            "【NY】服务报文格式配置错误"..service_info.FORMAT)
            end
        else
            local cfg_format=upper_str(service_info.FORMAT)
            if cfg_format=="XML" then
                content_type="text/xml;charset="..service_info.ENCODING
            elseif cfg_format == "JSON" then
                content_type="application/json;charset="..service_info.ENCODING
            else
                core.log.error("服务报文格式配置错误:",service_info.FORMAT)
                return nil,exception_util.build_err_tab(err_type.EXCEPT_MEMDB,
                            err_code.DAG_ERR_SERVICE_CALL_FORMAT,
                            "【NY】服务报文格式配置错误"..service_info.FORMAT)
            end
        end
    end

    header_tab["Content-Type"]=content_type
    header_tab["Content-Length"]=body_len
    header_tab["content-type"]=nil
    header_tab["content-length"]=nil
    return true
end

-- 生成url参数
local function generate_url_param(tab)
    local len=tab_nkeys(tab)
    if not tab or tab_nkeys(tab)==0 then
        return ""
    end
    local arr=tab_new(len,0)
    local idx=0
    for k,v in pairs(tab) do
        if type(v) == "table" then
            -- 若元素是table则不作为参数
            -- core.log.error("body参数转为url参数,数组或对象不能作为值:",core.json.delay_encode(v))
        else
            idx = idx + 1
            arr[idx]=tostring(k) .. "=" .. escape_uri(tostring(v))
        end
    end
    local get_param = tab.get_param
    if get_param and type(get_param == "table") then
        for k,v in pairs(get_param) do
            if type(v) == "table" then
                -- 若元素是table则不作为参数
                -- core.log.error("body参数转为url参数,数组或对象不能作为值:",core.json.delay_encode(v))
            else
                idx = idx + 1
                arr[idx]=tostring(k) .. "=" .. escape_uri(tostring(v))
            end
        end
    end
    if idx == 0 then
        return ""
    end
    return "?" .. table.concat(arr,"&")
end

local function service_limit(ctx,service_info)
    local red,err = redis_util.redis_new()
    if not red then
        core.log.error("redis客户端实例化失败:",err)
        return nil,exception_util.build_err_tab(err_type.EXCEPT_MEMDB,
                                        err_code.DAG_ERR_REDIS_INIT,"redis客户端实例化失败:"..err)
    end
    -- local ok,err = service_limit_util.execute(ctx,red,service_info.CODE,service_info.CONFIG)
    -- if ok == nil then
    --     core.log.error("服务限流执行失败:",err)
    --     return nil,exception_util.build_err_tab(err_type.EXCEPT_DAG,
    --                                     err_code.DAG_ERR_SERVICE_CALL_LIMITED_FAIL,
    --                                     "【NY】服务限流执行失败"..err)
    -- end
    if not ok then
        core.log.error("服务被限流:",err)
        return nil,exception_util.build_err_tab(err_type.EXCEPT_LIMITED,
                                        err_code.DAG_ERR_SERVICE_CALL_LIMITED,
                                        "【NY】服务被限流:"..err)
    end
    return true
end

-- ===============================模块方法=================================
-- 服务调用，req_tab
function _M.call(req_info,service_name,app_id,route_value,req_tab,header_tab,ctx)
    emergency_log.g_log(ctx,"透传服务编码:",service_name)
    emergency_log.g_log(ctx,"透传服务应用id:",app_id)
    emergency_log.g_log(ctx,"透传服务地市:",route_value)
    emergency_log.g_log(ctx,"透传服务调用......")
    -- 查询服务信息
    local service_info,err_tab=get_service_info(ctx,service_name,app_id,route_value)
    core.log.info("service_info:",core.json.delay_encode(service_info))
    if not service_info then
        return nil,err_tab
    end
    req_info.service_info=service_info

    -- 服务维度限流执行
    local ok,err_tab = service_limit(ctx,service_info)
    if not ok then
        return nil,err_tab
    end

    -- 存储服务日志信息
    local service_log_list=req_info.services
    if not service_log_list then
        service_log_list={}
        req_info.services=service_log_list
    end
    local service_log={}
    service_log.service_code=service_info.CODE
    service_log.format=service_info.FORMAT
    service_log.encoding=service_info.ENCODING
    if ctx.business_switch.ZIPKINTRACE_SWITCH == business_switch_code.SWITCH_OPEN then
        service_log.header_shield = service_info.HEADERSHIELD
        -- 单个服务，span_id 使用 trace_id
        service_log.span_id = ctx.req_id
        service_log.span_node = '1.1'
    end
    service_log_list[#service_log_list+1] = service_log

    -- 灰度路由查询
    local sys=req_info.sys
    local gray_urls,err=gray_route.query_gray_address(service_name,app_id,route_value,service_info.APPLYERID)
    if err then
        core.log.error("灰度路由执行错误:",err)
        return nil,exception_util.build_err_tab(err_type.EXCEPT_MEMDB,
                                                err_code.DAG_ERR_SERVICE_CALL_QUREY_DRAG,
                                                "【NY】服务灰度错误:"..err)
    end
    if gray_urls then
        emergency_log.g_log(ctx,"服务灰度地址:",core.json.delay_encode(gray_urls))
        log.info("服务灰度地址:",core.json.delay_encode(gray_urls))
        service_info.ADDRESS = gray_urls
    end

    core.log.info('服务请求报文结构:',core.json.delay_encode(req_tab))
    -- 判断是否get请求，是则将req_tab转为url参数，不是则转为req_body
    local req_body
    local url_param
    local content_type
    if service_info.HTTPMETHOD == "GET" or service_info.HTTPMETHOD == "get" then
        log.info("后端服务GET请求，body参数转为url参数")
        url_param=generate_url_param(req_tab)
        log.info("url参数:",url_param)
    elseif sys.transfer_raw_body == "1" then
        if service_info.FORMAT == "FORMDATA" then
            return nil,exception_util.build_err_tab(err_type.EXCEPT_MEMDB,
                            err_code.DAG_ERR_SERVICE_CONF,"当服务format为FORMDATA时，不能使用sys.transfer_raw_body配置")
        end
        log.info("transfer_raw_body = 1")
        req_body = req_info.raw_req_body
    elseif service_info.FORMAT == "FORMDATA" then
        local form_data,err = form_data_util.encode(ctx,req_tab)
        if not form_data then
            core.log.error("生成服务的form-data报文失败:",err)
            return nil,exception_util.build_err_tab(err_type.EXCEPT_FORMAT,
                                err_code.DAG_ERR_SERVICE_CREATE_FORM_DATA,"【NY】生成服务的form-data报文失败:"..err)
        end
        log.info("form-data content_type:",form_data.content_type)
        log.info("form-data body:",form_data.content)
        req_body = form_data.content
        -- core.log.warn("generated body:",core.json.delay_encode(req_body))
        -- req_body = "----------------------------880430294952931365184560\r\nContent-Disposition: form-data; name=\"name\"\r\n\r\n张三\r\n----------------------------880430294952931365184560\r\nContent-Disposition: form-data; name=\"key\"\r\n\r\nabc\r\n----------------------------880430294952931365184560\r\nContent-Disposition: form-data; name=\"fff\"; filename=\"常用命令.txt\"\r\nContent-Type: text\\/plain\r\n\r\nwindows：\r\n\tbcdedit \\/set {current} hypervisorlaunchtype off\r\n\tbcdedit \\/set {current} hypervisorlaunchtype auto\r\n\t\r\nlinux:\r\n\t\r\n\tjmeter：.\\/jmeter -n -t testplan\\/test_mock_api.jmx -l testplan\\/result.txt -e -o testplan\\/webreport\r\n----------------------------880430294952931365184560\r\nContent-Disposition: form-data; name=\"process_code\"\r\n\r\nBOSS_QueryVisitArea\r\n----------------------------880430294952931365184560\r\nContent-Disposition: form-data; name=\"app_id\"\r\n\r\n109000000166\r\n----------------------------880430294952931365184560\r\nContent-Disposition: form-data; name=\"access_token\"\r\n\r\ndzSMIfWUxFlv3iCknyi3\r\n----------------------------880430294952931365184560--\r\n"
        content_type = form_data.content_type
        -- content_type = "multipart/form-data; boundary=--------------------------880430294952931365184560"
    else
        core.log.info("service format:",service_info.FORMAT)
        req_body,err=convert_util.tab_to_body(req_tab,"UTF-8",service_info.ENCODING,service_info.FORMAT)
        if not req_body then
            core.log.error(err)
            return nil,exception_util.build_err_tab(err_type.EXCEPT_FORMAT,
                                err_code.DAG_ERR_SERVICE_CALL_SERVICE_PARAM_ERR,
                                err)
        end
    end

    -- 拼接服务的url,包含path和url_param
    ok,err_tab = concat_path(service_info,url_param,route_value)
    if not ok then
        return err_tab
    end

    core.log.info("服务请求报文:",req_body or "nil")
    -- 配置请求header
    if service_info.HEADERSHIELD=="2" then
        emergency_log.g_log(ctx,"过滤服务请求头")
        header_tab = new_tab(0,2)
    else
        if ctx.business_switch.ZIPKINTRACE_SWITCH == business_switch_code.SWITCH_OPEN then
            header_tab["traceid"] = service_log.span_id
        end
    end
    local ok,err_tab=set_header_param(service_info,header_tab,req_body and #req_body or nil,content_type,sys.ignore_charset=="1")
    if not ok then
        return nil,err_tab
    end
    -- 服务调用
    return http_call.call(req_info,service_info,req_body,header_tab,ctx)
end

-- 服务调用，req_body
function _M.template_call(req_info,service_name,span_node,app_id,route_value,req_body,header_tab,ctx)
    emergency_log.g_log(ctx,"编排服务编码:",service_name)
    emergency_log.g_log(ctx,"编排服务调用顺序:",span_node)
    emergency_log.g_log(ctx,"编排服务应用id:",app_id)
    emergency_log.g_log(ctx,"编排服务地市:",route_value)
    emergency_log.g_log(ctx,"编排服务调用......")
    --emergency_log.g_log(ctx,"模板引擎返回的服务请求头",header_tab)
    emergency_log.g_log(ctx,"模板引擎返回的服务请求报文:",req_body)
    -- 查询服务信息
    local service_info,err_tab=get_service_info(ctx,service_name,app_id,route_value)
    if not service_info then
        return nil,err_tab
    end
    req_info.service_info = service_info

    -- 服务维度限流执行
    local ok,err_tab = service_limit(ctx,service_info)
    if not ok then
        return nil,err_tab
    end

    -- 存储服务日志信息
    local service_log_list=req_info.services
    if not service_log_list then
        service_log_list={}
        req_info.services=service_log_list
    end
    local service_log={}
    service_log.service_code=service_info.CODE
    service_log.format=service_info.FORMAT
    service_log.encoding=service_info.ENCODING
    if ctx.business_switch.ZIPKINTRACE_SWITCH == business_switch_code.SWITCH_OPEN then
        service_log.header_shield = service_info.HEADERSHIELD
        service_log.span_id = snowflake_util.next_trace_id()
        service_log.span_node = span_node
    end

    service_log_list[#service_log_list+1] = service_log
    -- 灰度路由查询
    local sys=req_info.sys
    local gray_urls,err=gray_route.query_gray_address(service_name,app_id,route_value,service_info.APPLYERID)
    if err then
        core.log.error("灰度路由执行错误:",err)
        return nil,exception_util.build_err_tab(err_type.EXCEPT_MEMDB,
                                                err_code.DAG_ERR_SERVICE_CALL_QUREY_DRAG,
                                                "【NY】服务灰度错误:"..err)
    end
    if gray_urls then
        emergency_log.g_log(ctx,"服务灰度地址:",core.json.delay_encode(gray_urls))
        log.info("服务灰度地址:",core.json.delay_encode(gray_urls))
        service_info.ADDRESS = gray_urls
    end


    -- 判断是否get请求，是则将req_body转req_tab,并将参数转为url参数
    local url_param
    local content_type
    if service_info.HTTPMETHOD == "GET" or service_info.HTTPMETHOD == "get" then
        log.info("后端服务GET请求，body参数转为url参数")
        local req_tab,err
        if service_info.FORMAT == "JSON" then
            req_tab,err=core.json.decode(req_body)
        else
            req_tab,err=convert_util.xml_to_tab(req_body)
        end
        if err then
            core.log.error("内部错误，服务GET请求无法解析从模板返回的报文,err:",err,",body:",req_body)
            return nil,exception_util.build_err_tab(err_type.EXCEPT_DAG,
                                                    err_code.DAG_ERR_SERVICE_CALL_PARSE_MSG,
                                                    "【NY】内部错误，服务GET请求无法解析从模板返回的报文,err:"..err..",body:"..req_body)
        end
        url_param=generate_url_param(req_tab)
        req_body=nil
        log.info("url参数:",url_param)
    elseif service_info.FORMAT == "FORMDATA" then
        local req_tab,err = core.json.decode(req_body)
        if err then
            core.log.error("内部错误，服务GET请求无法解析从模板返回的报文,err:",err,",body:",req_body)
            return nil,exception_util.build_err_tab(err_type.EXCEPT_DAG,
                                                    err_code.DAG_ERR_SERVICE_CALL_PARSE_MSG,
                                                    "【NY】内部错误，服务GET请求无法解析从模板返回的报文,err:"..err..",body:"..req_body)
        end
        local form_data,err = form_data_util.encode(ctx,req_tab)
        if not form_data then
            core.log.error("生成服务的form-data报文失败:",err)
            return nil,exception_util.build_err_tab(err_type.EXCEPT_FORMAT,
                                err_code.DAG_ERR_SERVICE_CREATE_FORM_DATA,
                                "【NY】生成服务的form-data报文失败:"..err)
        end
        log.info("form-data content_type:",form_data.content_type)
        log.info("form-data body:",form_data.content)
        req_body = form_data.content
        content_type = form_data.content_type
    end

    -- 拼接服务的url,包含path和url_param
    ok,err_tab = concat_path(service_info,url_param,route_value)
    if not ok then
        return err_tab
    end

    -- 配置请求header
    if service_info.HEADERSHIELD=="2" then
        emergency_log.g_log(ctx,"过滤服务请求头")
        header_tab = new_tab(0,2)
    else
        if ctx.business_switch.ZIPKINTRACE_SWITCH == business_switch_code.SWITCH_OPEN then
            header_tab["traceid"] = service_log.span_id
        end
    end
    local ok,err_tab=set_header_param(service_info,header_tab,req_body and #req_body or nil,content_type,sys.ignore_charset=="1")
    if not ok then
        return nil,err_tab
    end
    -- 服务调用
    return http_call.call(req_info,service_info,req_body,header_tab,ctx)
end

return _M