local core              = require("apisix.core")
local ipairs            = ipairs
local string_util       = require("apisix.plugins.utils.string_util")
local ngx               = ngx
local get_req_headers   = ngx.req.get_headers
local json_decode       = core.json.decode

local _M = {}

local process_code_key_arr = { "process_code", "processCode","apicode","x-sg-api-code"}
local app_id_key_arr = {"app_id","appId"}
local load_conf_tag = false

-- 从头部获取
local function from_header(process_code,app_id)
    local req_headers = get_req_headers()
    if not process_code then
        for _,v in ipairs(process_code_key_arr) do
            process_code = req_headers[v]
            if process_code then
                break
            end
        end
    end
    if not app_id then
        for _,v in ipairs(app_id_key_arr) do
            app_id = req_headers[v]
            if app_id then
                break
            end
        end
    end
    return process_code,app_id
end

-- 遍历table,排除content,获取process_code，app_id
local function from_table(req_tab)
    local process_code, app_id
    local count = 0
    for k, v in pairs(req_tab) do
        if k ~= "content" then
            if process_code == nil then
                for _,key in ipairs(process_code_key_arr) do
                    if k == key then
                        process_code = v
                        count = count + 1
                    end
                end
            end
            if app_id == nil then
                for _,key in ipairs(app_id_key_arr) do
                    if k == key then
                        app_id = v
                        count = count + 1
                    end
                end
            end
            if type(v) == "table" then
                local a, b = from_table(v)
                if a ~= nil and process_code == nil then
                    process_code = a
                    count = count + 1
                end
                if b ~= nil and app_id == nil then
                    app_id = b
                    count = count + 1
                end
            end
            if count == 2 then
                break
            end
        end
    end
    return process_code, app_id
end

-- xml字符串提取
local function from_xml_string(body,key_arr)
    local temp
    for _, v in ipairs(key_arr) do
        temp = string_util.get_element_value(body, v)
        if temp then
            return temp
        end
    end
    return nil
end

--==================================模块方法======================================
-- 从报文提取process_code和app_id并返回
-- @body 请求报文
-- @format 报文格式
function _M.invoke(body, format)

    -- 从 配置中读取process_code,app_id
    if load_conf_tag == false then
        local local_conf = core.config.local_conf()
        local attr = core.table.try_read_attr(local_conf, "req_attr")
        if attr then
            for key,value in pairs(attr) do
                if key == "process_code" then
                    process_code_key_arr = string_util.split(value,",")
                elseif key == "app_id" then
                    app_id_key_arr = string_util.split(value,",")
                end
            end
        end
        load_conf_tag = true
    end

    local process_code, app_id
    if format == "XML" then
        -- 删除content标签
        local body, err = string_util.exclude_element(body, "content")
        if not body then
            core.log.error("xml报文格式错误")
            return nil,nil, err
        end
        -- 从xml报文中获取
        app_id = from_xml_string(body,app_id_key_arr)
        process_code = from_xml_string(body,process_code_key_arr)
    else
        local tab, err = json_decode(body)
        if not tab then
            core.log.error("json报文格式错误:", err)
            return nil,nil,err
        end
        -- 从table中遍历获取
        process_code,app_id = from_table(tab)
    end
    -- 若为空从头部获取
    process_code,app_id = from_header(process_code,app_id)

    return process_code,app_id
end

return _M