local xml2lua = require("apisix.plugins.utils.convert_util.xml2lua")
local iconv = require("iconv")
local gbk_to_utf8 = iconv.new("utf-8", "gbk")
local utf8_to_gbk = iconv.new("gbk", "utf-8")
local xml2tab=require("apisix.plugins.utils.convert_util.xml2tab")
local core=require("apisix.core")
local re_gsub=ngx.re.gsub
local tostring=tostring

local pairs = pairs

local _M = {}

-- =================================私有方法===========================================
-- xml字段值转义
local function trans_val(str)
    local new_str= re_gsub(tostring(str),"&","&amp;","jo")
    new_str=re_gsub(new_str,"<","&lt;","jo")
    new_str=re_gsub(new_str,">","&gt;","jo")
    return new_str
end

local function change_encoding(type,str)
    local cd
    if type == 1 then --utf8_to_gbk
        core.log.info("utf8->gbk")
        cd=iconv.new("gb18030", "utf-8")
    elseif type==2 then --gbk_to_utf8
        core.log.info("gbk->utf8")
        cd=iconv.new("utf-8", "gb18030")
    end
    local ostr,err=cd:iconv(str)
    if err == iconv.ERROR_INCOMPLETE then
        core.log.error("编码转换错误:Incomplete input")
        return nil,"编码转换错误:Incomplete input"
    elseif err == iconv.ERROR_INVALID then
        core.log.error("编码转换错误:Invalid input")
        return nil,"编码转换错误:Incomplete input"
    elseif err == iconv.ERROR_NO_MEMORY then
        core.log.error("编码转换错误:Failed to allocate memory")
        return nil,"编码转换错误:Incomplete input"
    elseif err == iconv.ERROR_UNKNOWN then
        core.log.error("编码转换错误:There was an unknown error")
        return nil,"编码转换错误:Incomplete input"
    end
    return ostr
end

local function tab2xml(tab,tab_name)
    local str=""
    if tab[1]~=nil then             -- array
        for _,v in ipairs(tab) do
            if type(v) == "table" then
                str=str.."<" .. tab_name .. ">" .. tab2xml(v,tab_name) .. "</" .. tab_name ..">"
            else
                str=str.. "<" .. tab_name .. ">" .. trans_val(v) .. "</" .. tab_name ..">"
            end
        end
    else                            -- object
        for k,v in pairs(tab) do
            if type(v) == "table" then
                if v[1]~=nil then  -- array
                    str=str..tab2xml(v,k)
                else               -- object
                    str=str.."<" .. k .. ">" .. tab2xml(v,tab_name) .. "</" .. k ..">"
                end
            else
                str=str.."<" .. k .. ">" .. trans_val(v) .. "</" .. k ..">"
            end
        end
    end
    return str
end


-- =================================模块方法==============================================
-- xml转table
function _M.xml_to_tab(xml)
    -- local nhandler = handler:new()
    -- local parser = xml2lua.parser(nhandler)
    -- parser:parse(xml)
    -- return nhandler.root
    return xml2tab.parse_xml(xml)
end

-- table转xml
function _M.tab_to_xml(tab)
    -- core.log.warn("tab:",core.json.delay_encode(tab))
    if type(tab)~= "table" then
        core.log.error("非table类型的参数无法转为xml字符串")
        return tostring(tab)
    end
    return tab2xml(tab,"root")
end

-- 字符串utf-8转gbk
function _M.utf8_to_gbk(str)
    return change_encoding(1,str)
end

-- 字符串gbk编码转utf-8
function _M.gbk_to_utf8(str)
    return change_encoding(2,str)
end


-- 将table转为指定编码指定格式的报文
-- @tab: 报文table
-- @old_encoding: 原报文编码
-- @target_encoding: 目标编码
-- @target_format: 目标报文格式
function _M.tab_to_body(tab,old_encoding,target_encoding,target_format)
    local declaration=[[<?xml version="1.0" encoding="]]..target_encoding..[["?>]]
    local body
    core.log.info("target_format:",target_format)
    if target_format == "JSON" then
        body=core.json.encode(tab)
    elseif target_format == "XML" then
        body=declaration.._M.tab_to_xml(tab)
    else
        core.log.error("程序错误，格式设置错误:",target_format)
        return nil,"程序错误，格式设置错误:"..target_format
    end

    if old_encoding== target_encoding then
        return body
    elseif target_encoding=="GBK" then
        return _M.utf8_to_gbk(body)
    elseif target_encoding=="UTF-8" then
        return _M.gbk_to_utf8(body)
    end
    core.log.error("程序错误，编码设置错误")
    return nil,"程序错误，编码设置错误"..target_encoding
end

return _M
