local core=require("apisix.core")
local find_str=string.find
local sub_str=string.sub
local reverse_str=string.reverse
local log = core.log

local _M={}

-- ===============常量定义=================
local _n='\n'
local _r='\r'
local _t='\t'
local blank=' '

-- =================模块方法================
-- 清空字符串左右的空白
function _M.trim(str)
    if not str then
        return
    end
    return (str:gsub("^%s*(.-)%s*$", "%1"))
    -- local len=#str
	-- if len==0 then
	-- 	return str
	-- end
	-- local star,endl
	-- for i=1,len,1 do
	-- 	local c=sub_str(str,i,i)
	-- 	if not(c==blank or c == _n or c== _r or c== _t) then
	-- 		star=i
	-- 		break
	-- 	end
	-- end
	-- for i=len,1,-1 do
	-- 	local c=sub_str(str,i,i)
	-- 	if not(c==blank or c == _n or c== _r or c== _t) then
	-- 		endl=i
	-- 		break
	-- 	end
	-- end
	-- return sub_str(str,star,endl)
end

-- 字符串以指定符号分割为字符串数组，默认以"."分割
function _M.split(expression,ch)
    if expression==nil or #expression==0 then
        return {}
    end
    local c=ch or '.'
    local arr = {}
    local i = 1
    local str = expression
    local len = #str
    local endl = 0
    local pos = 0
    while true do
        pos = find_str(str, c, pos + 1, len)
        if pos == nil then
            arr[i] = sub_str(str, endl + 1, len)
            break
        end
        arr[i] = sub_str(str, endl + 1, pos - 1)
        endl = pos
        i = i + 1
    end
    return arr
end

-- 获取xml编码
-- @body: xml字符串
function _M.get_xml_encoding(body)
    -- if sub_str(body,1,5) ~= "<?xml" then
    --     return nil,"xml报文缺少declaration"
    -- end
    local ef,et=find_str(body,"?>")
    if ef==nil then
        return nil,"【NY】xml报文格式错误"
    end
    if find_str(body,"GBK",5,ef) then
        return "GBK"
    elseif find_str(body,"UTF-8",5,ef) then
        return "UTF-8"
    elseif find_str(body,"utf-8",5,ef) then
        return "UTF-8"
    elseif find_str(body,"gbk",5,ef) then
        return "GBK"
    elseif find_str(body,"gb2312",5,ef) then
        return "GBK"
    elseif find_str(body,"GB2312",5,ef) then
        return "GBK"
    end
    return nil,"【NY】xml报文未设置编码"
end

-- 删除指定xml标签内容
-- @body: xml字符串
-- @element_name: xml标签名
function _M.exclude_element(body,element_name)
    local len=#body
    local sf,st=find_str(body,"<"..element_name..">")
    if not sf then
        return body
    end
    local temp_body=reverse_str(body)
    local temp_name=reverse_str("</"..element_name..">")
    local f,t=find_str(temp_body,temp_name)
    if f==nil then
        core.log.error("xml报文格式错误:",body)
        return nil,"xml报文格式错误"
    end
    local et=len-f+1
    return sub_str(body,1,sf-1)..sub_str(body,et+1,len)
end

-- 提取xml字符串的指定标签值
-- @body: xml字符串
-- @element_name: xml标签名
function _M.get_element_value(body,element_name)
    local f,t=find_str(body,"<"..element_name)
    if f and t then
        local f2,_ =find_str(body,"</"..element_name,t)
        if f2 then
            local val=sub_str(body,t+1,f2-1)
            local f3 = find_str(val,">")
            if f3 then
                val = sub_str(val,f3+1)
                return _M.trim(val)
            end
        end
    end
    return nil
end

-- 字符串保存到table
local function stringToTable(s)
    local tb = {}

    --[[
    UTF8的编码规则：
    1. 字符的第一个字节范围： 0x00—0x7F(0-127),或者 0xC2—0xF4(194-244);
        UTF8 是兼容 ascii 的，所以 0~127 就和 ascii 完全一致
    2. 0xC0, 0xC1,0xF5—0xFF(192, 193 和 245-255)不会出现在UTF8编码中
    3. 0x80—0xBF(128-191)只会出现在第二个及随后的编码中(针对多字节编码，如汉字)
    ]]
    for utfChar in string.gmatch(s, "[%z\1-\127\194-\244][\128-\191]*") do
        table.insert(tb, utfChar)
    end

    return tb
end

-- 获取字符串长度,英文字符为一个单位长, 中文字符为2个单位长
function _M.getUTFLen(s)
    local sTable = stringToTable(s)
    local len = 0
    local charLen = 0

    for i=1,#sTable do
        local utfCharLen = string.len(sTable[i])
        -- 长度大于1可认为为中文
        if utfCharLen > 1 then
            --将charLen设为1，可获取中文，英文的字符个数，以下举例，将其方法命名为:function getNewUTFLen(s)
            charLen = 2
        else
            charLen = 1
        end
        -- charLen = 1
        len = len + charLen
    end

    return len
end

-- 获取字符串长度,不管中文，英文一律一个字符为1单位长
function _M.getNewUTFLen(s)
    local sTable = stringToTable(s)
    local len = 0
    local charLen = 0

    for i = 1, #sTable do
        local utfCharLen = string.len(sTable[i])
        if utfCharLen > 1 then
            charLen = 1         -- 修改为1
        else
            charLen = 1
        end

        len = len + charLen
    end

    return len
end

local function get_xml_declaration(type)
    if type == 1 then
        return [[<?xml version="1.0" encoding="GBK"?>]]
    else
        return [[<?xml version="1.0" encoding="UTF-8"?>]]
    end
end

-- 校验xml报文头部，若无头部则根据默认编码添加
-- default_encoding_type 1：GBK 2：UTF-8
function _M.check_xml_declaration(body,default_encoding_type)
    body = _M.trim(body)
    if sub_str(body,1,1) == "<" and sub_str(body,1,5) ~= "<?xml"then
        log.info("xml请求报文缺少declaration,默认GBK编码并添加头部")
        body = get_xml_declaration(default_encoding_type or 1) .. body
    end
    return body
end

return _M