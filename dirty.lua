--[[
*  @Author      : huangchanglong
*  @Date        : 2023-02-08 22:25
*  LastEditors  : huangchanglong
*  LastEditTime : 2023-02-08 22:25
*  @Description : dirty 基础接口
--]]

local Dirty = {}

local type = type
local rawget = rawget
local rawset = rawset
local next = next
local table_concat = table.concat
local table_insert = table.insert

local DIRTY_SET = 0
local DIRTY_ADD = 1
local DIRTY_DEL = 2
Dirty.DIRTY_SET = DIRTY_SET
Dirty.DIRTY_ADD = DIRTY_ADD
Dirty.DIRTY_DEL = DIRTY_DEL

local NUMBER_KEY_PRE = 'i@'
Dirty.NUMBER_KEY_PRE = NUMBER_KEY_PRE
Dirty.NUMBER_KEY_PRE_MATCH = '^i@'
Dirty.NUMBER_KEY_SUB_CNT = 3

local function init_dirty_root(mng)
    mng.dirty_root = {
        node_cnt = 0,
        node_map = {},
    }
end
local function dirty_root_remove(dirty_root, node)
    dirty_root.node_map[node] = nil
    dirty_root.node_cnt = dirty_root.node_cnt - 1
end
local function dirty_root_add(dirty_root, node)
    dirty_root.node_map[node] = true
    dirty_root.node_cnt = dirty_root.node_cnt + 1
end

local function init_dirty_node(mng)
    local dirty_node = {
        mng_ptr = mng,
        op_map = {},
        op_cnt = 0,
    }

    local root_mng = rawget(mng.root, '__dirty')
    dirty_root_add(root_mng.dirty_root, dirty_node)
    mng.dirty_node = dirty_node
    return dirty_node
end
local function destroy_dirty_node(mng)
    local dirty_node = mng.dirty_node
    -- root 中移除
    local root_mng = rawget(mng.root, '__dirty')
    dirty_root_remove(root_mng.dirty_root, dirty_node)

    -- 解引用
    dirty_node.mng_ptr = nil
    mng.dirty_node = nil
end

local function new_dirty_mng(obj, parent, skey)
    local mng = {
        --root = root_obj,
        parent = parent,
        self = obj,
        skey = skey,
        --dirty_node = nil, -- 惰性初始化
    }

    if parent == nil then
        mng.root = obj
        init_dirty_root(mng)
    else
        mng.root = rawget(parent, '__dirty').root
    end
    return mng
end

local function free_dirty_mng(obj)
    local mng = rawget(obj, '__dirty')
    if not mng then
        return
    end
    local dirty_node = mng.dirty_node
    if dirty_node then
        destroy_dirty_node(mng)
    end

    -- 避免内存泄露
    mng.root = nil
    mng.parent = nil
    mng.self = nil
    mng.skey = nil
    mng.dirty_node = nil

    rawset(obj, '__dirty', nil)
end

local function dirty_node_map_find_key(dirty_node, key)
    return dirty_node.op_map[key] and true or false
end

function Dirty.__enable_dirty(obj, parent, skey)
    if rawget(obj, '__dirty') ~= nil then
        return false
    end
    local mng = new_dirty_mng(obj, parent, skey)
    rawset(obj, '__dirty', mng)

    for k, v in pairs(obj.__data) do
        if type(v) == 'table' then
            v:__enable_dirty(obj, k)
        end
    end
    return true
end

function Dirty.__disable_dirty(obj)
    if rawget(obj, '__dirty') == nil then
        return false
    end

    for _, v in pairs(obj.__data) do
        if type(v) == 'table' then
            v:__disable_dirty()
        end
    end
    -- 尾递归清理
    free_dirty_mng(obj)
    return true
end

function Dirty.__get_dirty(obj, ret)
    local mng = rawget(obj, '__dirty')
    local dirty_node = mng and mng.dirty_node
    if dirty_node == nil or next(dirty_node.op_map) == nil then
        return ret
    end

    -- 反向递归构建ret的path
    local function reverse_ensure_node_path(self, root)
        local smng = rawget(self, '__dirty')
        local parent = smng.parent
        if not parent then
            return root
        end
        local temp = reverse_ensure_node_path(parent, root)
        local skey = smng.skey
        if not temp[skey] then
            temp[skey] = {}
        end
        return temp[skey]
    end

    local dtret = reverse_ensure_node_path(obj, ret)
    for dk, op in pairs(dirty_node.op_map) do
        dtret[dk] = op
    end
end

function Dirty.__clear_dirty(obj)
    local mng = rawget(obj, '__dirty')
    local dirty_node = mng and mng.dirty_node
    if dirty_node == nil then
        return false
    end
    local raw_data = obj.__data
    -- 清理脏数据时，先把后面add/set的node enable
    for dk, op in pairs(dirty_node.op_map) do
        if op ~= DIRTY_DEL then
            local v = raw_data[dk]
            if type(v) == 'table' then
                v:__enable_dirty(obj, dk)
            end
        end
    end
    -- 销毁当前节点的脏数据
    destroy_dirty_node(mng)
end

local function dirty_node_insert_dk(dirty_node, key, op)
    dirty_node.op_map[key] = op
    dirty_node.op_cnt = dirty_node.op_cnt + 1
end
local function dirty_node_remove_dk(dirty_node, key)
    dirty_node.op_map[key] = nil
    dirty_node.op_cnt = dirty_node.op_cnt - 1
end
local function dirty_node_overwrite_dk(dirty_node, key, op)
    local dk_op_map = dirty_node.op_map
    local dkop = dk_op_map[key]
    if dkop == op then
        return
    end

    if dkop == DIRTY_DEL then
        if op == DIRTY_ADD then
            -- 先del 后add 视为set
            dkop = DIRTY_SET
        else
            dkop = op -- DIRTY_SET
        end
    elseif dkop == DIRTY_ADD then
        if op == DIRTY_DEL then
            -- 先add 后del 视为key无脏数据
            dirty_node_remove_dk(dirty_node, key)
        end
        -- 其他情况都保持为add
        return
    else
        dkop = op -- set
    end

    -- 覆盖写不需要修改计数器
    dk_op_map[key] = dkop
end

function Dirty.set_dirty_map(obj, key, op)
    local mng = rawget(obj, '__dirty')
    if not mng then
        return
    end
    local dirty_node = mng.dirty_node
    if not dirty_node then
        dirty_node = init_dirty_node(mng)
    end

    local has = dirty_node_map_find_key(dirty_node, key)
    if has then
        dirty_node_overwrite_dk(dirty_node, key, op)
    else
        dirty_node_insert_dk(dirty_node, key, op)
    end
end

function Dirty.get_dirty_info(root)
    local mng = rawget(root, '__dirty')
    if not mng then
        return nil, "not enable"
    end
    local dirty_root = mng.dirty_root
    if not dirty_root then
        return nil, "not root"
    end
    local amount = dirty_root.node_cnt
    local ret = {}
    local cnt = 0
    for dirty_node in pairs(dirty_root.node_map) do
        cnt = cnt + 1
        dirty_node.mng_ptr.self:__get_dirty(ret)
    end

    if amount ~= cnt then
        local s = string.format("get dirty info. dirty node amount<%d> get<%d>", amount, cnt)
        error(s)
    end
    return ret
end

function Dirty.clear_dirty_info(root)
    local mng = rawget(root, '__dirty')
    if not mng then
        return false
    end
    local dirty_root = mng.dirty_root
    if not dirty_root then
        return false
    end
    local amount = dirty_root.node_cnt

    local cnt = 0
    while true do
        local dirty_node = next(dirty_root.node_map)
        if dirty_node == nil then
            break
        end
        cnt = cnt + 1
        dirty_node.mng_ptr.self:__clear_dirty()
    end

    local left = dirty_root.node_cnt
    if amount ~= cnt and left ~= 0 then
        local s = string.format("clear dirty node. expect<%d> clear<%d> left<%d>", amount, cnt, left)
        error(s)
    end
    return true
end

-- 如果是dict类型需要转化整数key
local function table_clone_obj(obj)
    local tmp = {}

    local pack_key = false
    local cls = obj.__cls
    if cls['type'] == 'dict' and cls['key']['type'] == 'integer' then
        pack_key = true
    end
    for key, value in pairs(obj) do
        if pack_key then
            key = NUMBER_KEY_PRE .. key
        end
        if type(value) == "table" then
            tmp[key] = table_clone_obj(value)
        else
            tmp[key] = value
        end
    end
    return tmp
end

local function merge_mongo_dirty_map(dk_pre_path, obj, set, unset)
    local mng = rawget(obj, '__dirty')
    local dirty_node = mng and mng.dirty_node
    local cnt = 0
    if not dirty_node then
        return cnt
    end

    if dk_pre_path ~= '' then
        dk_pre_path = dk_pre_path .. '.'
    end

    local cls = obj.__cls
    if cls['type'] == 'dict' and cls['key']['type'] == 'integer' then
        dk_pre_path = dk_pre_path .. NUMBER_KEY_PRE
    end

    for key, op in pairs(dirty_node.op_map) do
        local dk_path = dk_pre_path .. key
        if op == DIRTY_SET or op == DIRTY_ADD then
            local v = obj.__data[key]
            if type(v) == "table" then
                v = table_clone_obj(v)
            end
            set[dk_path] = v
        else
            unset[dk_path] = ''
        end
        cnt = cnt + 1
    end

    return cnt
end

-- concat dirty key from root to cur node
local function collect_mongo_dirty_key(stack_s, root_mng, node)
    local mng = rawget(node, '__dirty')
    local parent = mng.parent
    if not parent then
        return nil
    end

    local parent_mng = rawget(parent, '__dirty')
    if parent_mng ~= root_mng then
        collect_mongo_dirty_key(stack_s, root_mng, parent_mng.self)
    end

    local v_type = parent.__cls['type']
    if v_type == "list" then
        -- list skey is number.
        -- skey=1  ---------> prop.items.1
        table_insert(stack_s, node.__dirty.skey)
    elseif v_type == "struct" then
        -- struct not support number key.
        -- skey=members ---> player.org.members (skey=members)
        table_insert(stack_s, node.__dirty.skey)
    else
        -- dict key maybe number.
        -- need conver number to (NUMBER_KEY_PRE .. key)
        -- skey=1001 ----> player.org.members.info.i@1001
        local skey_type = parent.__cls['key']['type']
        if skey_type == "integer" then
            table_insert(stack_s, NUMBER_KEY_PRE .. node.__dirty.skey)
        else
            table_insert(stack_s, node.__dirty.skey)
        end
    end
end

function Dirty.get_mongo_dirty_data(root)
    local set = {}
    local unset = {}
    local ret = {['$set'] = set, ['$unset'] = unset, cnt = 0}

    local root_mng = rawget(root, '__dirty')
    if not root_mng then
        return ret
    end
    local dirty_root = root_mng.dirty_root
    if not dirty_root then
        return ret
    end

    local dirty_cnt = 0
    local amount = dirty_root.node_cnt
    local node_cnt = 0
    for dirty_node in pairs(dirty_root.node_map) do
        local node = dirty_node.mng_ptr.self
        local stack_s = {}
        collect_mongo_dirty_key(stack_s, root_mng, node)
        local dk = table_concat(stack_s, '.')
        node_cnt = node_cnt + 1
        local merge_cnt = merge_mongo_dirty_map(dk, node, set, unset)
        dirty_cnt = dirty_cnt + merge_cnt
    end

    if amount ~= node_cnt then
        local s = string.format("get dirty info. dirty node amount<%d> get<%d>", amount, node_cnt)
        error(s)
    end

    ret.cnt = dirty_cnt
    return ret
end

-- luadata ---> mongodata ---> bson.encode
function Dirty.clone_mongodata(obj)
    return table_clone_obj(obj)
end

return Dirty
