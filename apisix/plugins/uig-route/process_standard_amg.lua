local core              = require("apisix.core")
local amg_util          = require("apisix.plugins.utils.amg_util")
local ngx               = ngx
local amg_query         = require("apisix.plugins.dag-datasource.query_process.amg_query")
local log               = core.log

local _M = {}

function _M.invoke(ctx,req_headers)
    local api_code = req_headers[amg_util.AMG_HEADER_API_CODE]
    local api_version = req_headers[amg_util.AMG_HEADER_API_VERSION]
    if api_code and api_version then
        return false
    end
    local aoc_info,err = amg_query.get_aoc_by_amg(api_code,api_version)
    if err then
        return nil,err
    end
    if aoc_info then
        local process_code = aoc_info.AOC_API_CODE
        if not process_code then
            core.log.error("aoc与amg的映射中，缺少aoc_api_code")
            return nil,"aoc与amg的映射中，缺少aoc_api_code"
        end
        -- 使用能力code重写uri
        local new_uri = "/" .. process_code
        log.info("new_uri:", new_uri)
        ngx.req.set_uri(new_uri)
        ctx.pass_req_uri=true
        ctx.amg_req_flag=true
        return true
    else
        return false
    end
end

return _M