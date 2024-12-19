local core=require("apisix.core")
local string_util=require("apisix.plugins.utils.string_util")
local sub_str=string.sub

local _M={}

--=========================常量定义================================
local _n='\n'
local _r='\r'
local _t='\t'
local blank=' '
--==================================模块方法======================================
local function get_first_char_not_blank(str)
    local len=#str
    for i=1,len,1 do
        local c=sub_str(str,i,i) do
            if not (c==_n or c== _r or c==_t or c== blank) then
                return c
            end
        end
    end
    return ""
end
-- 判断报文格式编码，并存入ctx.req_info
-- @param body: 请求报文
-- @return format: 报文格式
-- @return encoding: 编码
-- @return err: 异常返回错误信息，format和encoding为nil
function _M.invoke(body)
    local format,encoding,err
    -- local c=get_first_char_not_blank(body)
    local c=sub_str(body,1,1)
    if c=="<" then
        format="XML"
        encoding,err=string_util.get_xml_encoding(body)
        if not encoding then
            core.log.error("获取xml报文编码失败:",err)
            return nil,nil,err
        end
    elseif c=="{" then
        format="JSON"
        encoding="UTF-8"
    else
        core.log.error("报文格式错误，未知格式")
        return nil,nil,"【NY】报文格式错误，未知格式"
    end
    return format,encoding
end

return _M