local core                  = require("apisix.core")
local rewrite               = require("apisix.plugins.uig-route.phase_func.rewrite")
local header_filter         = require("apisix.plugins.uig-route.phase_func.header_filter")
local body_filter           = require("apisix.plugins.uig-route.phase_func.body_filter")
local log                   = core.log
local ngx                   = ngx
-- local aoc_amg               = require("apisix.plugins.uig-route.aoc_amg")
-- local new_tab               = require("table.new")
local emergency_log         = require("apisix.plugins.emergency-log").g_log
local memory_query          = require("apisix.plugins.uig-route.memory_query")
local form_data_util        = require("apisix.plugins.utils.form_data_util")

local plugin_name = "uig-route"

local schema = {
    type = "object",
    properties = {
        type={
            type="string",
            enum={"uig","open","shop","sse"}
        },
        uig_uri={
            type="string",
            pattern="(/.*)"
        },
        open_uri={
            type="string",
            pattern="(/.*)"
        },
        shop_uris={
            type="object"
        },
        sse_uri={
            type="string",
            pattern="(/.*)"
        }
    },
    additionalProperties = false,
    required={"type"}
}

local _M = {
    version = 0.1,
    priority = 8000,
    schema = schema,
    name = plugin_name
}

function _M.check_schema(conf)
    local ok, err = core.schema.check(schema, conf)
    if not ok then
        return false, err
    end
    if conf.type == "uig" and type(conf.uig_uri)~="string" then
        return false,"uig_uri数据类型配置错误"
    elseif conf.type == "open" and type(conf.open_uri)~="string" then
        return false,"open_uri数据类型配置错误"
    elseif conf.type == "shop" then
        if type(conf.shop_uris) ~= "table" then
            return false,"shop_uris数据类型配置错误"
        end
        for k,v in pairs(conf.shop_uris) do
            if type(k) ~= "string" or type(v) ~= "string" then
                return false,"shop_uris键值对数据类型配置错误"
            end
        end
    end
    return true
end

local api_tab = {
    {
        methods = {"GET"},
        uri = "/memory/collect",
        handler = memory_query.get_lua_memory
    },
    {
        methods = {"GET"},
        uri = "/memory/template",
        handler = memory_query.get_template_memory
    },
    {
        methods = {"GET"},
        uri = "/memory/kafka-log",
        handler = memory_query.get_kafka_log_memory
    },
    {
        methods = {"GET"},
        uri = "/memory/consumers",
        handler = memory_query.get_consumers_memory
    },
    {
        methods = {"GET"},
        uri = "/memory/datamap",
        handler = memory_query.get_datamap_memory
    },
    {
        methods = {"GET"},
        uri = "/memory/breaker",
        handler = memory_query.get_breaker_memory
    },
    {
        methods = {"GET"},
        uri = "/memory/failed-req",
        handler = memory_query.get_failed_req_memory
    },
    {
        methods = {"GET"},
        uri = "/memory/prometheus",
        handler = memory_query.get_prometheus_memory
    },
    {
        methods = {"GET"},
        uri = "/memory/global-rules",
        handler = memory_query.get_global_rules_memory
    },
    {
        methods = {"GET"},
        uri = "/memory/routes",
        handler = memory_query.get_routes_memory
    },
}

local pass_uri={
    -- 普米
    ["/apisix/prometheus/metrics"]=true
}

-- 将api中需要暴露的uri写入pass_uri
do
    for _,api in pairs(api_tab) do
        pass_uri[api.uri] = true
    end
end

function _M.api()
    return api_tab
end

function _M.rewrite(conf, ctx)
    if ngx.var.remote ~= 9080 or 9180 then 
        ctx.comm_protocol = ""
    end    
    if pass_uri[ngx.var.uri] then
        log.info("当前请求为特殊请求,跳过能力调用流程")
        ctx.pass_req_uri=true
        return
    end
    log.info("uig-route rewrite phase start......")
    -- 判断是否标准amg请求，是则通过服务编码获取process_code进行服务调用
    -- local headers = ngx.req.get_headers()
    -- if headers["x-amg-standard-req"] == "1" then
    --     -- 跳过能运执行插件
    --     ctx.pass_req_uri = true
    --     ctx.amg_req_flag = true
    --     ctx.amg = new_tab(0,5)
    --     return aoc_amg.process_req(conf,ctx)
    -- end

    return rewrite.invoke(conf,ctx)
end

function _M.header_filter(conf,ctx)
    if ctx.pass_req_uri or ctx.conn_protocol == 'websocket' then
        return
    end
    log.info("uig-route header_filter phase start......")
    return header_filter.invoke(conf,ctx)
end

function _M.body_filter(conf,ctx)
    if ctx.pass_req_uri or ctx.conn_protocol == 'websocket' then
        return
    end
    log.info("uig-route body_filter phase start......")
    return body_filter.invoke(conf,ctx)
end

function _M.log(conf,ctx)
    if ctx.pass_req_uri then
        return
    end
    log.info("uig-route log phase start......")
    if not ctx.req_info.ability_route_flag then
        emergency_log(ctx,"释放文件缓存")
        form_data_util.release_file_temp(ctx)
        log.info("释放模板引擎执行内存......")
        emergency_log(ctx,"释放模板引擎内存(未匹配能力)")
    end
end



return _M

