local core              = require("apisix.core")
local redis             = require("apisix.plugins.dag-datasource.redis")
local redis_util        = require("apisix.plugins.utils.redis_util")
local read_conf_util    = require("apisix.plugins.utils.read_conf_util")
local find_str          = string.find
local ffi               = require("ffi")
local json_decode       = core.json.decode
local emergency_log     = require("apisix.plugins.emergency-log")
local cache_util        = require("apisix.plugins.utils.cache_util")
local clone_tab         = core.table.clone

local _M={version=0.1}
local mt={
    __index=_M
}

local city_group
-- ============================初始化===========================
-- 加载配置文件中地市分组
do
    city_group=read_conf_util.get_conf("city_group")
    if city_group == nil then
        core.log.error("未配置地市分组")
        return nil,"系统配置错误"
    end
end

-- =================================常量值==============================
local ADDRESS_TYPE_MAIN="MAIN"             -- 服务主地址
local ADDRESS_TYPE_EMERGENCY="EMERGENCY"   -- 服务备地址

local URL_TYPE_HTTP="HTTP"                 -- URl 普通类型
local URL_TYPE_HTTPS="HTTPS"               -- URL https类型
local URL_TYPE_ZKDUBBO="ZKDUBBO"           -- URL ZK类型
local URL_TYPE_DUBBO="DUBBO"               -- URL DUBBO类型

local format_tab = {
    XML = "XML",
    JSON = "JSON",
    FORMDATA = "FORMDATA"
}

local encoding_tab = {
    GBK = "GBK",
    ["UTF-8"] = "UTF-8"
}
-- ==================================私有方法==================================
-- 根据指定service_name和condition查询服务信息
local function query_full_service(red,service_name,condition)
    condition=condition and (condition .. ".") or ""
    -- 主地址
    local key_main=redis_util.get_key(redis_util.ROUTE_ADDRESS_MAPPING,service_name,condition .. ADDRESS_TYPE_MAIN)
    core.log.info("service redis key:",key_main)
    local ret,err=red:hgetall(key_main)
    if err then
        core.log.error(service_name.."服务查询失败:",err)
        return nil,err
    end
    if redis_util.is_redis_null(ret) then
        return nil
    end
    local main=redis_util.array_to_hash(ret)
    -- local emergency=redis_util.array_to_hash(ret[2])
    return main
end

-- 通过地市id查询地市分组
local function city_id_grouping(city_id)
    local id=tonumber(city_id)
    if id==nil then
        core.log.error("route_value不是数字")
        return nil,"route_value不是数字"
    end
    return city_group[id] or ""
end

-- 根据地市分组获筛选URL
local function get_url_by_group(urls,city_id)
    local len=#urls
    if len==0 then
        return nil,"数据配置错误，url数量为0"
    elseif len==1 then
        return urls
    end
    local group_id,err=city_id_grouping(city_id)
    if not group_id then
        return nil,err
    end
    for _,v in ipairs(urls) do
        local f,_ =find_str(v,"default.group="..group_id)
        if f~=nil then
            return {v}
        end
    end
    return {urls[1]}
end

local function process_url_type(url_type,urls,city_id)
    if not urls then
        return nil,"ADDRESS解析失败，结果为空"
    end

    if url_type == URL_TYPE_ZKDUBBO then
        return get_url_by_group(urls,city_id)
    end

    if url_type == URL_TYPE_HTTP or url_type == URL_TYPE_HTTPS then
        return urls
    end
    return nil,"服务URLTYPE配置错误"..tostring(url_type)
end

local function check_service_info(service_info,code)
    local format=service_info.FORMAT
    local encoding=service_info.ENCODING
    if not format_tab[format] then
        return nil,"服务报文格式配置错误:"..format ..",service_code:".. code
    end
    if not encoding_tab[encoding] then
        return nil,"服务编码配置错误"..encoding ..",service_code:".. code
    end
    if service_info.CODE == nil then
        return nil,"服务code不能为空" ..",service_code:".. code
    end
    if service_info.APPLYERID == nil then
        return nil,"提供者id不能为空" ..",service_code:".. code
    end
    return service_info
end

local function engine_format_map(format)
    if format == format_tab.FORMDATA then
        return format_tab.JSON
    end
    return format
end

-- ==================================模块方法==================================
local function get_service_info(service_name)
    local red,err=redis_util.redis_new()
    if not red then
        core.log.error("redis客户端实例化失败:",err)
        return nil,err
    end
    local res,err = red:hgetall(redis_util.get_key(redis_util.ROUTE_ADDRESS_MAPPING,service_name,ADDRESS_TYPE_MAIN))
    if err then
        core.log.error("服务查询失败,",err)
        return nil,service_name.."服务查询失败:"..err
    end
    if redis_util.is_redis_null(res) then
        return nil
    end
    return redis_util.array_to_hash(res)
end

_M.get_service_info = get_service_info

-- 根据服务名将服务信息存入模板
function _M.set_service_info(service_arr,size)

    local cur_service_code = ""
    if service_arr == nil  then
        core.log.error("服务数组为空")
        return cur_service_code,false,"服务数组为空"
    end
    if size == 0 then
        return cur_service_code,true
    end
    core.log.info("service_task size:",size)
    local red,err=redis_util.redis_new()
    if not red then
        core.log.error("redis客户端实例化失败:",err)
        return cur_service_code,false,err
    end
    red:init_pipeline()
    for i=0,size-1,1 do
        local service_name=ffi.string(service_arr[i].serviceName)
        red:hgetall(redis_util.get_key(redis_util.ROUTE_ADDRESS_MAPPING,service_name,ADDRESS_TYPE_MAIN))
    end
    local res,err=red:commit_pipeline()
    if err then
        core.log.error("服务查询失败,",err)
        cur_service_code=ffi.string(service_arr[0].serviceName)
        return cur_service_code,false,err
    end
    core.log.info("res:",core.json.delay_encode(res))
    core.log.info("service_name:",ffi.string(service_arr[0].serviceName))
    if #res == 0 then
        cur_service_code=ffi.string(service_arr[0].serviceName)
        return cur_service_code,false,"未注册服务"..cur_service_code
    end
    for k=1,size,1 do
        local service=service_arr[k-1]
        local service_name = ffi.string(service.serviceName)
        local info,err = cache_util.fetch_data(
            cache_util.func_enum.service_base_info,
            get_service_info,
            service_name or "")
        if err then
            return nil,err
        end
        if info == nil then
            cur_service_code=service_name
            return cur_service_code,false,"未注册服务" .. service_name
        end
        local ok,err=check_service_info(info,service_name)
        if not ok then
            cur_service_code=service_name
            return cur_service_code,false,err
        end
        service.encoding=info.ENCODING
        service.dataformatName= engine_format_map(info.FORMAT) .."_DATAFORMAT"
        service.pluginType=2
    end
    return cur_service_code,true
end


local function error_handle(message,service_name,app_id,route_value)
    core.log.error(message,",服务:",service_name,",应用id:",app_id,",地市id:",route_value)
    return nil,message..",服务:"..service_name..",应用id:".. app_id .. ",地市id:".. route_value
end

local function check_address(api_info,tag,service_name,app_id,route_value)
    local arr = json_decode(api_info.ADDRESS)
    if not arr then
        return error_handle(tag.."地址解析错误:"..(api_info.ADDRESS or "nil"),service_name,app_id,route_value)
    end
    if arr[1]==nil then
        return error_handle(tag.."地址数量为0",service_name,app_id,route_value)
    end
    api_info.ADDRESS=arr
    return api_info
end

-- 查询服务详细信息
local function local_get_detail_service(service_name,app_id,route_value)
    local red,err1 = redis_util.redis_new()
    if not red then
        core.log.error("redis客户端实例化失败:",err1)
        return nil,"redis客户端实例化失败:"..err1
    end
    local api_key = redis_util.get_key(redis_util.ROUTE_ADDRESS_MAPPING, service_name, ADDRESS_TYPE_MAIN)
    local api_app_key = redis_util.get_key(redis_util.ROUTE_ADDRESS_MAPPING, service_name, app_id .. "." .. ADDRESS_TYPE_MAIN)
    local api_app_city_key = redis_util.get_key(redis_util.ROUTE_ADDRESS_MAPPING, service_name, app_id .. "." .. route_value .. "." .. ADDRESS_TYPE_MAIN)
    local dubbo_city_group_key = redis_util.get_key(redis_util.DUBBO_CITY_GROUP)

    red:init_pipeline()
    red:hgetall(api_key)
    red:hgetall(api_app_key)
    red:hgetall(api_app_city_key)
    red:hgetall(dubbo_city_group_key)

    local res, err = red:commit_pipeline()
    if err then
        core.log.error("redis查询失败:", err)
        return nil, "redis查询失败:" .. err
    end
    if redis_util.is_redis_null(res[1]) then
        return error_handle("未注册该服务",service_name,app_id,route_value)
    end
    local api_info_main = redis_util.array_to_hash(res[1])

    -- 判断服务是否需要分地市
    if api_info_main.ADDRESS == nil or #api_info_main.ADDRESS == 0 then
        local api_info
        -- 分地市使用路由组配置
        if not redis_util.is_redis_null(res[2]) then
            api_info = redis_util.array_to_hash(res[2])
            local route_id = api_info.ADDRESSGROUPID
            if route_id == nil then
                return error_handle("分地市使用路由组，但id未配置",service_name,app_id,route_value)
            end
            local route_key = redis_util.get_key(redis_util.API_ROUOTE_GROUP,route_id)
            res,err = red:hgetall(route_key)
            if err then
                core.log.error("查询服务路由组实体失败:",err)
                return nil,"查询服务路由组实体失败:"..err
            end
            if redis_util.is_redis_null(res) then
                return error_handle("服务路由组实体查询反回空:"..route_key,service_name,app_id,route_value)
            end
            local route_tab = redis_util.array_to_hash(res)
            local address = route_tab["CITYID_"..route_value]
            if address == nil then
                return error_handle("服务路由组中不存在当前请求的地市配置",service_name,app_id,route_value)
            end

            api_info.ADDRESS=address
            api_info_main.is_route_group = true
            api_info,err = check_address(api_info,"服务分地市（路由组）",service_name,app_id,route_value)
        elseif not redis_util.is_redis_null(res[3]) then
            -- 分地市使用ADDRESS配置
            api_info = redis_util.array_to_hash(res[3])
            api_info,err = check_address(api_info,"服务分地市（ADDRESS）",service_name,app_id,route_value)
        else
            return error_handle("服务未查询到相关的分地市配置",service_name,app_id,route_value)  -- 已测试
        end
        if api_info == nil then
            return nil,err
        end
        api_info_main.ADDRESS = api_info.ADDRESS
        return api_info_main
    end


    -- 判断服务是DUBBO服务
    if api_info_main.URLTYPE and api_info_main.URLTYPE == URL_TYPE_DUBBO then
        core.log.info("DUBBO服务，地市:", route_value)

        local city_group_name;
        -- 获取地市与组名的映射关系，例：14:group_31
        if redis_util.is_redis_null(res[4]) then
            -- redis没获取到，获取配置文件的默认映射
            core.log.warn("未查询到地市与地址组配置:", err)
            if not city_group then
                core.log.error("未配置默认地市与地址组:", err)
                return nil,"未查询到地市与地址组配置:" .. route_value
            end
            city_group_name = city_id_grouping(route_value)
        else
            -- 获取redis内的映射
            local group_mapping = redis_util.array_to_hash(res[4])
            city_group_name = group_mapping[route_value .. ""] or city_id_grouping(route_value)
        end

        core.log.debug("group_mapping:", core.json.delay_encode(group_mapping))
        core.log.debug("city_group_name:", city_group_name)

        if city_group_name == nil then
            core.log.error("未查询到地市与地址组的对应关系:", route_value)
            return nil,"未查询到地市与地址组的对应关系:" .. route_value
        end

        api_info_main,err = check_address(api_info_main,"服务分地市（ADDRESS）",service_name,app_id,route_value)

        -- 根据组查询对应组的地址
        local group_address_key = redis_util.get_key(redis_util.DUBBO_GROUP_ADDRESS, api_info_main.ADDRESS[1], city_group_name)
        core.log.debug("group_address_key:", group_address_key)

        res,err = red:hgetall(group_address_key)
        if err then
            core.log.error("查询dubbo服务组地址失败:",err)
            return nil,"查询dubbo服务组地址失败:"..err
        end

        if redis_util.is_redis_null(res) then
            return error_handle("查询dubbo服务组地址为空:" .. group_address_key, service_name, app_id, route_value)
        end

        local route_tab = redis_util.array_to_hash(res)
        core.log.debug("route_tab:", core.json.delay_encode(route_tab))
        if route_tab == nil then
            return error_handle("dubbo服务组地址为空:" .. group_address_key, service_name, app_id, route_value)
        end

        local address_list = {}
        for key, value in pairs(route_tab) do
            if value == "1" then
                table.insert(address_list, key)
            end
        end
        if #address_list == 0 then
            core.log.error("已启用的地址列表为空:", api_info_main.GROUP, city_group_name)
            return nil,"已启用的地址列表为空:" .. api_info_main.GROUP .. "." .. city_group_name
        end

        core.log.debug("address_list:", core.json.delay_encode(address_list))

        api_info_main.ADDRESS = core.json.encode(address_list)

        api_info_main,err = check_address(api_info_main,"DUBBO服务",service_name,app_id,route_value)
    else
        core.log.info("不分地市")
        -- 服务不分地市，直接取ADDRESS字段作为url数组
        api_info_main,err = check_address(api_info_main,"服务（不分地市）",service_name,app_id,route_value)
    end

    return api_info_main,err
end

-- 查询服务path拼接配置
local function local_get_service_path_concat(service_name)
    local red,err = redis_util.redis_new()
    if not red then
        core.log.error("redis客户端实例化失败:",err)
        return nil,"redis客户端实例化失败:"..err
    end

    local key = redis_util.get_key(redis_util.SERVICE_PATH_CONCAT,service_name)

    local res,err = red:hgetall(key)
    if err then
        core.log.error("redis查询服务地市path拼接配置查询失败:",err)
        return nil,"redis查询服务地市path拼接配置查询失败"..err
    end
    if redis_util.is_redis_null(res) then
        return nil
    end

    return redis_util.array_to_hash(res)
end

-- 查询服务详细信息（缓存）
function _M.get_detail_service(service_name,app_id,route_value)
    local func_enum = cache_util.func_enum.service_detail_info
    return cache_util.fetch_data(
        func_enum,
        local_get_detail_service,
        service_name or "",
        app_id or "",
        route_value or "99")
end

-- 查询服务+应用维度的服务信息
function _M.get_service_by_app(service_name,app_id)
    local red,err=redis_util.redis_new()
    if not red then
        core.log.error("redis客户端实例化失败:",err)
        return nil,err
    end
    local key = redis_util.get_key(redis_util.ROUTE_ADDRESS_MAPPING,service_name,app_id .. "." .. ADDRESS_TYPE_MAIN)
    local res,err = red:hgetall(key)
    if err then
        core.log.error("服务查询失败,",err)
        return nil,err
    end
    if redis_util.is_redis_null(res) then
        return nil
    end
    return redis_util.array_to_hash(res)
end

-- 查询服务+应用+地市维度的服务信息
function _M.get_service_by_app_city(service_name,app_id,city_id)
    local red,err=redis_util.redis_new()
    if not red then
        core.log.error("redis客户端实例化失败:",err)
        return nil,err
    end
    local key = redis_util.get_key(redis_util.ROUTE_ADDRESS_MAPPING,
                service_name,app_id .. "."..
                city_id .."." .. ADDRESS_TYPE_MAIN)
    local res,err = red:hgetall(key)
    if err then
        core.log.error("服务查询失败,",err)
        return nil,err
    end
    if redis_util.is_redis_null(res) then
        return nil
    end
    return redis_util.array_to_hash(res)
end


-- 查询服务path拼接配置(缓存)
function _M.get_service_path_concat(service_name)
    local func_enum = cache_util.func_enum.service_path_concat
    return cache_util.fetch_data(
        func_enum,
        local_get_service_path_concat,
        service_name or "")
end


return _M
