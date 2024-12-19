local core              = require("apisix.core")
local ngx               = ngx
local service_query     = require("apisix.plugins.dag-datasource.query_process.service_query")
local http              = require("resty.http")
local math              = math
local new_tab           = require("table.new")

local _M = {}

local function rand_url(urls)
    math.randomseed(ngx.now())
    local idx= math.random(1,#urls)
    return urls[idx]
end

local function http_call(url,method,headers,body)
    local httpc = http.new()
    -- httpc:set_timeout(timeout) 配置超时
    return httpc:request_uri(url, {
        method = method,
        body = body or "",
        headers = headers,
        ssl_verify = false
    })
end

function _M.process_req(conf,ctx)
    local headers = ngx.req.get_headers()
    local api_code = headers["x-aoc-api-code"]
    -- local version = headers["x-aoc-api-version"]
    -- 根据api_code查询服务信息，发起请求调用并返回
    local service_info,err = service_query.get_detail_service(api_code,"","")
    if not service_info then
        ngx.header["Content-Type"]="application/json"
        return 500,{respCode="30000",respDesc=err}
    end
    local body = core.request.get_body()
    local url = rand_url(service_info["ADDRESS"])
    local method = service_info["HTTPMETHOD"]
    -- 服务调用信息存入上下文
    local service_call_info = new_tab(0,10)
    service_call_info.url = url
    service_call_info.method = method
    service_call_info.req_body = body
    service_call_info.start_time = ngx.now()*1000
    service_call_info.format = service_info["FORMAT"]
    service_call_info.encoding = service_info["ENCODING"]
    service_call_info.applyer_id=service_info["APPLYERID"]
    service_call_info.service_code = service_info["CODE"]
    -- 发起服务调用
    local res,err = http_call(url,method,headers,body)
    service_call_info.end_time = ngx.now()*1000
    service_call_info.resp_body = res.body or ""
    ctx.amg.service_call_info = service_call_info
    if not res then
        core.log.error("服务调用失败:",err)
        core.log.error("服务调用方法:",service_info.HTTPMETHOD)
        core.log.error("服务调用地址:",core.json.delay_encode(service_info.ADDRESS))
        core.log.error("服务请求头:",core.json.delay_encode(headers))
        core.log.error("服务请求报文:",body or "")
        if err == "timeout" then
            return 500,{respCode="20006",respDesc="服务调用超时"}
        end
        ngx.header["Content-Type"]="application/json"
        return 500,{respCode="31001",respDesc="服务调用失败:"..err}
    end
    core.response.set_header("Content-Type",res.headers["Content-Type"])
    return res.status,res.body
end


return _M