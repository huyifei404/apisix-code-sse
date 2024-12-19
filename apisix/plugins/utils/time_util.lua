local core              = require("apisix.core")
local tab_new           = require("table.new")
local sub_str           = string.sub
local ngx               = ngx


local _M = {}

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
    local time_tab=tab_new(0,7)
    time_tab.year=sub_str(timestamp,1,4)
    time_tab.month=sub_str(timestamp,5,6)
    time_tab.day=sub_str(timestamp,7,8)
    time_tab.hour=sub_str(timestamp,9,10)
    time_tab.min=sub_str(timestamp,11,12)
    time_tab.sec=sub_str(timestamp,13,14)
    local msec = sub_str(timestamp,15,17)
	return os.time(time_tab)*1000 + msec
end

-- 获取当前系统格式化时间戳YYYYMMDDHHMISSsss
-- @param timestamp: 时间戳毫秒值
-- @param add_msec,返回结果是否带上毫秒值，默认true
function _M.date_format(timestamp,add_msec)
    local time = math.floor(timestamp)
    time = os.date("%Y%m%d%H%M%S",time/1000)
    if add_msec == false then
        return time
    end
    local millisecond = timestamp%1000
    if millisecond>99 then
        return time .. millisecond
    elseif millisecond > 9 and millisecond < 100 then
        return time .. "0" .. millisecond
    else
        return time .. "00" .. millisecond
    end
end


return _M