local core                  = require("apisix.core")
local redis_util            = require("apisix.plugins.utils.redis_util")
local table_new             = require("table.new")

local _M = {}

-- 通过能运信息查询三码信息以及应用信息
-- @param process_code: 能运的能力编码
-- @return aoc_info:包含字段能力与三码服务的映射关系——amg_relation,缺省应用信息——app
function _M.get_amg_by_aoc(process_code,app_id)
    local red,err = redis_util.redis_new()
    if not red then
        core.log.error("redis客户端实例化失败:",err)
        return nil,"redis客户端实例化失败:"..err
    end
    local amg_api_key = redis_util.get_key(redis_util.AMG_API_FROM_AOC,process_code)
    local amg_app_key = redis_util.get_key(redis_util.AMG_APP_FROM_AOC,app_id)
    red:init_pipeline()
    red:hgetall(amg_api_key)
    red:hgetall(amg_app_key)
    local res,err = red:commit_pipeline()
    if not res then
        core.log.warn("能运查询三码映射信息失败:",err)
        return nil,"能运查询三码映射信息失败:"..err
    end
    if redis_util.is_redis_null(res[1]) then
        core.log.error("能运查询三码映射返回空,无服务信息,key:",amg_api_key)
        return nil,"能运查询三码映射返回空,key:"..amg_api_key
    end
    if redis_util.is_redis_null(res[2]) then
        core.log.error("能运查询三码映射,无应用信息,key:",amg_app_key)
        return nil,"能运查询三码映射返回空,key:"..amg_app_key
    end
    local amg_info = table_new(0,2)
    amg_info["api"] = redis_util.array_to_hash(res[1])
    amg_info["app"] = redis_util.array_to_hash(res[2])
    return amg_info
end

-- 通过三码信息查询能运信息
function _M.get_aoc_by_amg(api_code,api_version,app_id)
    local red,err = redis_util.redis_new()
    if not red then
        core.log.error("redis客户端实例化失败:",err)
        return nil,"redis客户端实例化失败:"..err
    end
    local aoc_api_key = redis_util.get_key(redis_util.AOC_API_FROM_AMG,api_code,api_version)
    local aoc_app_key = redis_util.get_key(redis_util.AOC_APP_FROM_AMG,app_id)
    red:init_pipeline()
    red:hgetall(aoc_api_key)
    red:hgetall(aoc_app_key)
    local res,err = red:commit_pipeline()
    if not res then
        core.log.error("三码查询能运映射信息失败:",err)
        return nil,"三码查询能运映射信息失败:"..err
    end
    if redis_util.is_redis_null(res[1]) then
        core.log.error("三码查询能运映射返回空,key:",aoc_api_key)
        return nil,"三码查询能运映射返回空,key:"..aoc_api_key
    end
    if redis_util.is_redis_null(res[2]) then
        core.log.error("三码查询能运映射返回空,key:",aoc_app_key)
        return nil,"三码查询能运映射返回空,key:"..aoc_app_key
    end
    local aoc_info = table_new(0,2)
    aoc_info.api = redis_util.array_to_hash(res[1])
    aoc_info.app = redis_util.array_to_hash(res[2])
    return aoc_info
end

return _M