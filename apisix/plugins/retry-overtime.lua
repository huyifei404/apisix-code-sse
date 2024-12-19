--
-- Licensed to the Apache Software Foundation (ASF) under one or more
-- contributor license agreements.  See the NOTICE file distributed with
-- this work for additional information regarding copyright ownership.
-- The ASF licenses this file to You under the Apache License, Version 2.0
-- (the "License"); you may not use this file except in compliance with
-- the License.  You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.
--
local core = require("apisix.core")
local exception = require("apisix.plugins.exception")
local plugin_name = "retry-overtime"
local ngx = ngx

local schema = {
    type = "object",
    properties = {
        retry_type = { type = "integer", default = 2 ,emum={1,2}},
        retries = { type = "integer", minimum = 0, default = 1 },
        timeout = { type = "number", minimum = 1, default = 30000 }, --默认超时30秒
    },
}

local _M = {
    version = 0.1,
    priority = 100,
    name = plugin_name,
    schema = schema,
}

-- 服务重试
-- retry_type 1为源地址重试，2为多地址重试，默认2
-- len 为url数组长度
-- retries为重试次数
function _M.service_retry(urls, retries, retry_type, service_call_fun, ...)
    local target_url
    local len = #urls
    local res, err

    if retry_type == 1 then
        -- 随机重试
        for i = 1, retries, 1 do
            local randomIndex = math.random(1, len)
            local randomUrl = urls[randomIndex]
            target_url = randomUrl
            core.log.debug("可用地址数量:", len, " 随机:",randomIndex)

            res, err = service_call_fun(randomUrl,...)
            core.log.info("服务调用 ", i, " 次")
            if res and res.status == 200 then
                return res, err, target_url
            else
                core.log.error("服务地址调用失败:",err,",url:",randomUrl)
            end
        end
        return res, err, target_url
    else
        -- 多地址剔除重试
        local url_available = {}
        for i, v in ipairs(urls) do
            url_available[i] = v
        end

        local i = 1
        while #url_available > 0 do
            local randomIndex = math.random(1, #url_available)
            local randomUrl = url_available[randomIndex]
            target_url = randomUrl
            core.log.debug("可用地址数量:",#url_available, " 随机:",randomIndex)

            res, err = service_call_fun(randomUrl,...)
            core.log.info("服务调用 ", i, " 次 最大重试:", retries)
            if res and res.status == 200 then
                return res, err, target_url
            end
            core.log.error("服务地址调用失败:", err, "  url:", randomUrl, "重试次数:", i, " 最大重试次数:", retries)
            table.remove(url_available, randomIndex)
            i = i + 1
            if i > retries then
                break
            end
        end

        return res, err, target_url
    end
end

function _M.check_schema(conf)
    local ok,err = core.schema.check(schema, conf)
    if not ok then
        return false,err
    end
    if conf.retries == 0 then
        conf.retries=1
    end
    return true
end

return _M
