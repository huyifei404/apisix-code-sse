local core              = require("apisix.core")
local resp_code_tab     = require("apisix.plugins.utils.amg_util.resp_code")
local resp_desc_tab     = require("apisix.plugins.utils.amg_util.resp_desc")
local http_status_tab   = require("apisix.plugins.utils.amg_util.http_status")
local response          = core.response
local ngx               = ngx
local string_sub        = string.sub
local new_tab           = require("table.new")
local math              = math
local tostring          = tostring
local aes               = require("resty.aes")
local decode_base64     = ngx.decode_base64
local encode_base64     = ngx.encode_base64
local md5               = ngx.md5
local io                = io
local read_conf_util    = require("apisix.plugins.utils.read_conf_util")
local find_str          = string.find
local sub_str           = string.sub
local re_gsub           = ngx.re.gsub
local uuid              = require('resty.jit-uuid')

uuid.seed()

local _M={}
-- ==========读取配置文件相关配置
-- _M.amg_conf = read_conf_util.get_conf("amg")
-- _M.amg_region_id = _M.amg_conf.region_id

--===============常量===========================
local AMG_BASE_URI = "/amgroute"
local AMG_BEAE_URI_SUFFIX = "/amgroute/"
local AMG_BASE_URI_LEN = #AMG_BASE_URI

local LOCAL_BASE_URI = "/localroute"
local LOCAL_BASE_URI_SUFFIX = "/localroute/"
local LOCAL_BASE_URI_LEN = #LOCAL_BASE_URI

--===============需要跳过插件执行的请求uri===============
local skip_plugin_uris={
    ["/healthcheck"] = true,
    ["/apisix/prometheus/metrics"]=true
}

--=====请求头参数定义=============
_M.AMG_HEADER_ERR_CODE="x-sg-err-code"
_M.AMG_HEADER_ERR_DESC="x-sg-err-desc"
_M.AMG_HEADER_SCENARIO_CODE="x-sg-scenario-code"
_M.AMG_HEADER_SCENARIO_VERSION="x-sg-scenario-version"
_M.AMG_HEADER_ABILITY_CODE="x-sg-ability-code"
_M.AMG_HEADER_API_CODE="x-sg-api-code"
_M.AMG_HEADER_API_VERSION="x-sg-api-version"
_M.AMG_HEADER_APP_KEY="x-sg-app-key"
_M.AMG_HEADER_DEST_APP_KEY="x-sg-dest-app-key"
_M.AMG_HEADER_TIMESTAMP="x-sg-timestamp"
_M.AMG_HEADER_SCENARIO_ID="x-sg-scenario-id"
_M.AMG_HEADER_MESSAGE_ID="x-sg-message-id"
_M.AMG_HEADER_ROUTE_TYPE="x-sg-route-type"
_M.AMG_HEADER_ROUTE_VALUE="x-sg-route-value"
_M.AMG_HEADER_TEST="x-sg-test"
_M.AMG_HEADER_MD5_SECRET="x-sg-md5-secret"
_M.AMG_HEADER_TOKEN="x-sg-token"
_M.AMG_HEADER_CALL_HISTORY="x-sg-call-history"
_M.AMG_HEADER_SPAN_ID="x-sg-spanid"
_M.AMG_HEADER_PARENT_SPAN_ID="x-sg-parent-spanid"
_M.AMG_HEADER_SLA="x-sg-sla"
_M.AMG_HEADER_FORWORD="x-sg-amg-forword"
_M.AMG_HEADER_USER_INFO="x-sg-user-info"
_M.AMG_APP_ID="ID"
--==============================================

_M.resp_code = resp_code_tab
_M.resp_desc = resp_desc_tab
_M.http_status = http_status_tab

--===================服务授权的枚举命名===========================
_M.AUTH_SCOPE_ALL="0"
_M.AUTH_SCOPE_PART="1"
_M.AUTH_WHITELIST="0"
_M.AUTH_BLCAKLIST="1"

-- ===============熔断常量定义=====================
_M.BREAK_TYPE_COUNT = "00"
_M.BREAK_TYPE_RATE = "01"

-- ==============服务状态定义===============
_M.AMG_SERVICE_STATUS_SUCCESS = "1"
_M.AMG_SERVICE_STATUS_FAILED = "0"

-- =============路由类型定义==========
_M.ROUTE_TYPE_PROV="00"
_M.ROUTE_TYPE_PHONE="01"
_M.ROUTE_TYPE_API="02"

-- ============服务authType============
_M.AUTH_TYPE_PUBLIC = "PUBLIC"
_M.AUTH_TYPE_ALLOW = "ALLOW_LIST"
_M.AUTH_TYPE_BLOCK = "BLOCK_LIST"

-- ============故障注入类型=============
_M.FAULT_INJECTION_TIMEOUT = "00"
_M.FAULT_INJECTION_BREAK = "01"
_M.FAULT_INJECTION_HTTP = "02"

-- ==============鉴权错误类型=================
_M.AUTHOR_CODE_ERR = 0
_M.AUTHOR_VERSION_ERR = 1
_M.AUTHOR_TIME_ERR = 2
_M.AUTHOR_BLACK_ERR = 3


-- ======系统默认值======
_M.DEFAULT_SCENARIO_CODE = "B99999999999"  -- 场景默认编码
_M.DEFAULT_PROV = "AAA" -- 省代码默认值，当省代码为空时用这个值标识，用于调用外部服务时拼接域名

--===============================私有方法===================================
local function aes_new(secret)
    local aes_instance = aes:new(secret,nil,aes.cipher(128,"ecb"))
    return aes_instance
end

--===============================模块方法===================================
-- amg错误处理
-- @param http_status: 请求返回的状态码
-- @param resp_code: amg错误编码
-- @param resp_desc: amg错误描述，如系统内部错误需要额外添加错误描述 SERVER ERROR:xxxxx
function _M.error_handle(http_status,resp_code,resp_desc)
    ngx.ctx.is_amg_err_resp=true
    ngx.header[_M.AMG_HEADER_ERR_CODE] = resp_code
    ngx.header[_M.AMG_HEADER_ERR_DESC] = resp_desc
    ngx.ctx.err_code = resp_code
    ngx.ctx.err_msg = resp_desc
    ngx.header["Content-Length"] = 0
    response.exit(http_status,"")
end

-- 根据Base64.encodeBase64(MD5(x-sg-message-id + app_secret + x-sg-timestamp))生成摘要
-- @param message-id: 调用方消息流水号
-- @param app_secret: 应用密钥
-- @param timestamp: 当前请求时间错，格式为YYYYMMDDHHMISSsss
function _M.generate_secret(message_id,app_secret,timestamp)
    return ngx.encode_base64(ngx.md5_bin(message_id..app_secret..timestamp))
end

-- 解析字符串转为时间戳毫秒值,字符串时间格式为YYYYMMDDHHMISSsss
function _M.parse_time(timestamp)
    if type(timestamp) ~= "string" then
		timestamp=tostring(timestamp)
	end
    if not tonumber(timestamp) then
        return nil,"时间字符串格式错误，内容必须为数字"
    end
    if #timestamp ~= 17 then
        return nil,"时间字符串格式错误，长度不等于17"
    end
    local time_tab=new_tab(0,7)
    time_tab.year=string_sub(timestamp,1,4)
    time_tab.month=string_sub(timestamp,5,6)
    time_tab.day=string_sub(timestamp,7,8)
    time_tab.hour=string_sub(timestamp,9,10)
    time_tab.min=string_sub(timestamp,11,12)
    time_tab.sec=string_sub(timestamp,13,14)
    local msec = string_sub(timestamp,15,17)
	return os.time(time_tab)*1000 + msec
end

-- 获取当前系统格式化时间戳YYYYMMDDHHMISSsss
function _M.get_timestamp(timestamp)
    timestamp = timestamp or ngx.now()
    local time = math.floor(timestamp)
    time = os.date("%Y%m%d%H%M%S",time)
    local millisecond = timestamp*1000%1000
    if millisecond>99 then
        return time .. millisecond
    elseif millisecond > 9 and millisecond < 100 then
        return time .. "0" .. millisecond
    else
        return time .. "00" .. millisecond
    end
end

-- 解密call_history
-- x-sg-call-history=BASE64(AES(call-history, secret))
-- call-history=apicode1,apicode2,…,apicodek
-- secret=md5(x-sg-app-key+x-sg-scenario-id+ call-histroy秘钥)
function _M.decode_call_history(cipher_text,app_key,scenario_id,call_history_secret)
    local str = decode_base64(cipher_text)
    if not str then
        return nil
    end
    local secret = md5(app_key .. scenario_id .. call_history_secret)
    local aes_instance = aes_new(secret)
    return aes_instance:decrypt(str)
end

-- 加密call_history
-- x-sg-call-history=BASE64(AES(call-history, secret))
-- call-history=apicode1,apicode2,…,apicodek
-- secret=md5(x-sg-app-key+x-sg-scenario-id+ call-histroy秘钥)
function _M.encode_call_history(call_history,app_key,scenario_id,call_history_secret)
    local secret = md5(app_key .. scenario_id .. call_history_secret)
    local aes_instance = aes_new(secret)
    local str = aes_instance:encrypt(call_history)
    core.log.warn("call_history:",call_history)
    core.log.warn("secret:",secret)
    return encode_base64(str)
end

function _M.aes_encrypt(key,text)
    local aes_instance = aes_new(key)
    local str = aes_instance:encrypt(text)
    core.log.warn("str:",str)
    return encode_base64(str)
end

--- 双平面通用校验开始时间和结束时间方式
function _M.check_time(conf)
    local time = tonumber(os.date("%Y%m%d%H%M%S", ngx.time()))
    local start_time = tonumber(conf.start_time)
    local expire_time = tonumber(conf.expire_time)
    if expire_time  and (expire_time < time) then
        return false
    end
    if start_time  and (start_time > time) then
        return false
    end
    return true
end

-- 获取请求service path，base url为外省应用访问/amgroute,内省应用访问/localroute
function _M.get_service_path(uri,is_current_prov_app)
    local len = #uri
    local f,t
    if is_current_prov_app then
        if len > LOCAL_BASE_URI_LEN then
            f,t = find_str(uri,LOCAL_BASE_URI_SUFFIX)
        else
            f,t = find_str(uri,LOCAL_BASE_URI)
            if f then
                t = t + 1
            end
        end
    else
        if len > AMG_BASE_URI_LEN then
            f,t = find_str(uri,AMG_BEAE_URI_SUFFIX)
        else
            f,t = find_str(uri,AMG_BASE_URI)
            if f then
                t = t + 1
            end
        end
    end

    if f ~= 1 then
        return nil,"invalid base uri"
    end

    local service_path = sub_str(uri,t,len)
    return service_path
end

function _M.set_api_headers(ctx,key,val)
    local headers = ctx.amg.api_headers
    headers[key] = val
end



function _M.check_skip_plugin(ctx)
    local amg_info = ctx.amg
    if amg_info.skip_checked then
        if amg_info.skip_plugin_flag then
            return true
        end
    else
        amg_info.skip_checked = true
        -- ==========检查当前请求uri是否需要跳过
        local flag = skip_plugin_uris[ngx.var.uri]
        if flag then
            ctx.amg.skip_plugin_flag=true
            return true
        end
        return false
    end
end

-- 生成64bit的16位随机数
function _M.generate_spanid(req_id)
    local md5_str=md5(req_id)
    return sub_str(md5_str,9,24)
end

function _M.generate_message_id()
    local message_id,_ = re_gsub(uuid(),"-","")
    return message_id
end


return _M