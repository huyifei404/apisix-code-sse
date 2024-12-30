local ngx                           = ngx
local core                          = require("apisix.core")
local server                        = require ("resty.websocket.server")
local client                        = require ("resty.websocket.client")
local protocol                      = require ("resty.websocket.protocol")
local exception_util                = require("apisix.plugins.exception.util")
local err_type                      = require("apisix.plugins.exception.type")
local err_code                      = require("apisix.plugins.exception.code")


local _M={version=0.1}

local function ws_proxy(sock_from, sock_to, flip_masking)
    local opcode_mapper = {
        ["continuation"] = 0x0,
        ["text"] = 0x1,
        ["binary"] = 0x2,
        ["close"] = 0x8,
        ["ping"] = 0x9,
        ["pong"] = 0xA,
    }

    while true do
        local data, typ, err = sock_from:recv_frame(flip_masking)

        if data == nil then
            -- socket already closed
            sock_to:send_close()
            break
        else
            local fin = (typ ~= "continuation")

            if typ == "close" then
                sock_from:send_close()
            end  
            -- 在这里对data进行处理
            -- data = 'filterdata'
            local bytes, err = sock_to:send_frame(fin, opcode_mapper[typ], data, flip_masking)

            if bytes == nil then
                sock_from:send_close()
                break
            end
        end

    end
end

function _M.web_proxy(service_info) 

    core.log.info("websocket proxy started!")

    local sock_server, err = server:new()

    if not sock_server then
        core.log.error("failed to new websocket server: ", err)
        return nil, exception_util.build_err_tab(err_type.EXCEPT_DAG,
                                err_code.DAG_ERR_WEBSOCKET_CONN,
                                "【NY】Websocket服务端新建失败")
    end
    local sock_client, err = client:new()
    local ok, err = sock_client:connect(service_info.ADDRESS[1])
    if not ok then
        core.log.error("failed to connect websocket client: ", err)
        return nil, exception_util.build_err_tab(err_type.EXCEPT_DAG,
                                err_code.DAG_ERR_WEBSOCKET_CONN,
                                "【NY】Websocket客户端新建失败")
    end
    local s2c = ngx.thread.spawn(ws_proxy, sock_client, sock_server, false)
	local c2s = ngx.thread.spawn(ws_proxy, sock_server, sock_client, true)
    if not ngx.thread.wait(s2c) then
        core.log.error("failed to server connect client")
    end

    if not ngx.thread.wait(c2s) then
        core.log.error("failed to client connect server")
    end
    core.log.info("websocket升级协议成功")
    
end

return _M