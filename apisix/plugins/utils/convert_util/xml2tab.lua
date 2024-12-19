local xml_reader=require("xmlreader")
local core=require("apisix.core")
local sub_str=string.sub

local _M={
    version=0.1
}

--=======================私有方法============================
local function process_depth(parent_node,parent_depth,depth)
    local sum=parent_depth - depth + 1
    if sum == 0 then
        return parent_node
    end
    if sum < 0 then
        return nil,"未知异常，解析xml失败"
    end
    for i=1,sum,1 do
        parent_node=parent_node.parent
    end
    return parent_node
end

-- 节点body值更改，需要同时更新tab中父节点body的属性指向
local function node_change_body(node,value)
    -- 更改当前节点值
    node.body=value
    -- 更改父节点body对应属性或数组下标指向的值
    local parent_body=node.tab_parent.body
    local idx=node.arr_idx
    if idx then             -- array
        parent_body[idx]=value
    else                    -- hash
        parent_body[node.name]=value
    end
end

-- 数组添加元素
local function insert_arr(arr,node)
    node.tab_parent=arr
    local new_idx=arr.idx+1
    node.arr_idx=new_idx
    arr.idx=new_idx
    arr.body[new_idx]=node.body
end

-- 对象添加元素
local function insert_hash(hash,node,node_name)
    node.tab_parent=hash
    hash.body[node_name]=node.body
    hash.nodes[node_name]=node
end

-- 父节点添加子节点
local function insert_child(parent,child,child_name)
    if parent.type==1 then
        node_change_body(parent,{})
        parent.type=2
        insert_hash(parent,child,child_name)
        return
    end
    local node=parent.nodes[child_name]
    if node then    -- 已存在该子节点，作为数组元素处理
        -- 判断原有节点是否数组
        if node.idx then
            insert_arr(node,child)
        else
            --原节点不是数组，初始化一个数组，将两个子节点放入数组,并将数组覆盖父节点属性
            local arr={
                name=child_name,
                idx=0,
                body={}
            }
            insert_arr(arr,node)
            insert_arr(arr,child)
            insert_hash(parent,arr,child_name)
        end
    else            -- 不存在该子节点，作为属性处理
        insert_hash(parent,child,child_name)
    end
end

------node节点属性-------
-- name        节点名
-- parent      父节点（xml结构）
-- tab_parent  父节点（table结构）
-- idx         数组索引（当该节点为数组时具备该属性）
-- arr_idx     该节点在父节点数组中的索引
-- type        节点类型 1 字符串，2 table
-- body        节点内容 可为lua字符串或lua table
-- nodes       子节点集合

--=======================模块方法============================
function _M.parse_xml(xml_str)
    local r=xml_reader.from_string(xml_str)
    local root={
        name="root",
        parent=nil,
        tab_parent=nil,
        idx=nil,
        type=2,
        body={},
        nodes={}
    }
    -- 父节点
    local parent_depth=-1
    local parent_node=root
    -- 当前节点
    local depth
    local type
    local name
    local node
    local state,err
    while(true) do
        state,err = r:read()
        if state==false then
            break
        elseif state==nil then
            core.log.error("xml格式错误,",err)
            return nil,"xml格式错误,"..sub_str(err,1,#err-1)
        end

        type=r:node_type()
        depth=r:depth()
        -- 获取当前节点名
        name=r:name()
        if type == "element" then
            parent_node=process_depth(parent_node,parent_depth,depth)
            -- if name=="ddddd" then
            --     core.log.warn("'parent:",parent_depth,",current_depth:",depth,"'")
            -- end
            -- core.log.warn("'current_name:",name,",parent_name:",parent_node["@name"],"'")

            -- 当前节点定义
            node={
                name=name,
                parent=parent_node,
                type=1, -- 字符串
                body="",
                nodes={}
            }

            -- 父节点添加子节点
            insert_child(parent_node,node,name)
            -- 父节点指向当前节点
            parent_node=node
            -- 父节点层级改为当前层级
            parent_depth=depth
        elseif type=="text" or type=="cdata" then
            parent_node=process_depth(parent_node,parent_depth,depth)
            parent_depth=depth-1
            -- if parent_node[NODE_VALUE] ~= nil then
            --     parent_node[NODE_VALUE]=r:value()
            -- end
            if parent_node.body=="" then
                node_change_body(parent_node,r:value())
            end
        end
    end
    -- core.log.warn("state:",r:close())
    return root.body
end

return _M