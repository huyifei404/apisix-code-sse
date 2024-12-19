
local upload   = require "resty.upload"
local decode   = require "cjson.safe".decode
local tonumber = tonumber
local tmpname  = os.tmpname
local concat   = table.concat
local type     = type
local find     = string.find
local open     = io.open
local sub      = string.sub
local sep      = sub(package.config, 1, 1) or "/"
local ngx      = ngx
local req      = ngx.req
local var      = ngx.var
local body     = req.read_body
local file     = ngx.req.get_body_file
local data     = req.get_body_data
local pargs    = req.get_post_args
local uargs    = req.get_uri_args
local nkeys    = require("table.nkeys")
local new_tab  = require("table.new")
local tostring = tostring


local core     = require("apisix.core")

local _M = {}

local LINE_SEPARATOR = "\r\n"

local defaults = {
    -- tmp_dir          = var.reqargs_tmp_dir,
    tmp_dir          = "/home/apisix_code/apisix/tmpdir",
    timeout          = 1000,
    chunk_size       = 4096,
    max_get_args     = 100,
    max_post_args    = 100,
}

local function read(f)
    local f, e = open(f, "rb")
    if not f then
        return nil, e
    end
    local c = f:read "*a"
    f:close()
    return c
end

local function basename(s)
    local p = 1
    local i = find(s, sep, 1, true)
    while i do
        p = i + 1
        i = find(s, sep, p, true)
    end
    if p > 1 then
        s = sub(s, p)
    end
    return s
end

local function kv(r, s)
    if s == "formdata" then return end
    local e = find(s, "=", 1, true)
    if e then
        r[sub(s, 2, e - 1)] = sub(s, e + 2, #s - 1)
    else
        r[#r+1] = s
    end
end

local function parse(s)
    if not s then return nil end
    local r = {}
    local i = 1
    local b = find(s, ";", 1, true)
    while b do
        local p = sub(s, i, b - 1)
        kv(r, p)
        i = b + 1
        b = find(s, ";", i, true)
    end
    local p = sub(s, i)
    if p ~= "" then kv(r, p) end
    return r
end

local function new_parse(s)
    if not s then return nil end
    local r = {}
    local i = 1
    local b = find(s, ";", 1, true)
    local offset = 1
    while b do
        local p = sub(s, i, b - offset)
        kv(r, p)
        i = b + 2 - offset
        b = find(s, "\";", i, true)
        offset = 0
    end
    local p = sub(s, i)
    if p ~= "" then kv(r, p) end
    return r
end

function _M.decode(ctx,options)
    local file_temp = ctx.file_temp
    if not file_temp then
        file_temp = {}
        ctx.file_temp = file_temp
    end
    options = options or defaults
    local files = {}

    local tmpdr = options.tmp_dir or defaults.tmp_dir
    if tmpdr and sub(tmpdr, -1) ~= sep then
        tmpdr = tmpdr .. sep
    end
    local maxfz = options.max_file_size    or defaults.max_file_size
    local maxfs = options.max_file_uploads or defaults.max_file_uploads
    local chunk = options.chunk_size       or defaults.chunk_size
    local form, e = upload:new(chunk, options.max_line_size or defaults.max_line_size)
    if not form then return nil, e end
    local h, p, f, o, s
    local u = 0
    form:set_timeout(options.timeout or defaults.timeout)
    while true do
        local t, r, e = form:read()
        if not t then return nil, e end
        if t == "header" then
            if not h then h = {} end
            if type(r) == "table" then
                local k, v = r[1], new_parse(r[2])
                if v then h[k] = v end
            end
        elseif t == "body" then
            if h then
                local d = h["Content-Disposition"]
                f = {
                    name = d.name,
                    content_type = h["Content-Type"] and h["Content-Type"][1],
                    filename = d.filename
                }
                if maxfz then
                    s = 0
                end
                h = nil
            end
            if f.filename then    -- 文件类型字段
                -- check max_file_size
                if maxfz then
                    s = s + #r
                    if maxfz < s then
                        return nil, "The maximum size of an uploaded file exceeded.field name:" .. f.name
                    end
                end
                -- check max_file_uploads
                if maxfs and maxfs < u + 1 then
                    return nil, "The maximum number of files allowed to be uploaded simultaneously exceeded.field name:" .. f.name
                end
                -- 存储文件内容到上下文
                if f.data == nil then
                    f.data = #file_temp + 1
                    file_temp[f.data] = {idx = 1}
                end
                local tf = file_temp[f.data]
                tf[tf.idx] = r
                tf.idx = tf.idx + 1
            else                        -- 文本类型字段
                if f.idx == nil then
                    f.idx = 1
                end
                local idx = f.idx
                f[idx] = r
                f.idx = idx + 1
            end
        elseif t == "part_end" then
            local c, d
            c, d, f = files, f, nil
            if c then
                local n = d.name
                -- 合并value
                if d.filename then
                    -- 文件类型
                    file_temp[d.data] = concat(file_temp[d.data])
                else
                    -- 文本类型
                    d = concat(d)
                end
                local s = d
                if maxfs and d.size> 0 then
                    u = u + 1
                end
                -- local s = d.data and concat(d.data) or d
                if n then
                    local z = c[n]
                    if z then
                        if z.n then
                            z.n = z.n + 1
                            z[z.n] = s
                        else
                            z = { z, s }
                            z.n = 2
                        end
                        c[n] = z
                    else
                        c[n] = s
                    end
                else
                    c.n = c.n + 1
                    c[c.n] = s
                end
            end
        elseif t == "eof" then
            break
        end
    end

    return files
end

local function generate_part(ctx,name,field_info)
    if type(name) == "number" then
        return
    end
    local val = nil
    local arr = new_tab(13,0)
    arr[1] = LINE_SEPARATOR
    arr[2] = "Content-Disposition: form-data; name=\""
    arr[3] = name
    arr[4] = "\""
    local idx = 4
    if type(field_info) == "table" then
        -- filename
        local filename = field_info.filename
        if #filename == 0 then
            return nil,"类型为文件的字段，filename不可为空,field:" .. name
        end
        arr[idx+1] = "; filename=\""
        arr[idx+2] = field_info.filename
        arr[idx+3] = "\""
        idx = idx + 3
        -- Content-Type
        if field_info.content_type then
            arr[idx+1] = LINE_SEPARATOR
            arr[idx+2] = "Content-Type: "
            arr[idx+3] = field_info.content_type
            idx = idx + 3
        else
            return nil,"类型为文件的字段，content_type不能为空,field:" .. name
        end
        -- 取文件内容
        val = ctx.file_temp[tonumber(field_info.data)] or ""
    else
        val = field_info
    end
    -- header换行
    arr[idx+1] = LINE_SEPARATOR
    idx = idx + 1
    -- value部分
    arr[idx+1] = LINE_SEPARATOR
    arr[idx+2] = val
    arr[idx+3] = LINE_SEPARATOR

    return concat(arr)
end

local function generate_boundary()
    return "----ApisixFormBoundary" .. sub(ngx.md5(tostring(ngx.now())),9,24)
end

-- @param ctx: apisix上下文
-- @param for_data_tab: form-data在apisix中的table模型
-- @return: {content_type: 头部Content-Type,content: 生成的form-data body}
function _M.encode(ctx,form_data_tab)
    if not form_data_tab or nkeys(form_data_tab) == 0 then
        return nil
    end
    -- local boundary = "----WebKitFormBoundaryAow7XYEQkvh027uB"
    local boundary = generate_boundary()
    local arr = new_tab(nkeys(form_data_tab)+2,0)
    arr[1] = ""
    local idx = 1
    for k,v in pairs(form_data_tab) do
        local part,err = generate_part(ctx,k,v)
        if not part then
            return nil,"form-data报文生成失败," .. err
        end
        idx = idx + 1
        arr[idx] = part
    end
    arr[idx+1] = ""
    local content = concat(arr,"--"..boundary) .. "--" .. LINE_SEPARATOR
    local result = {
        content_type = "multipart/form-data; boundary=" .. boundary,
        content = content
    }
    return result
end

function _M.release_file_temp(ctx)
    if ctx.file_temp then
        core.table.clear(ctx.file_temp)
        ctx.file_temp = nil
    end
end


return _M