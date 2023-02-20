-- lua function enable_oldindex can enable or disable metamethod __oldindex
-- local enable_oldindex = enable_oldindex or (function() end)

local Dirty = require("dirty")
local math = math
local tconcat = table.concat
local tonumber = tonumber
local tostring = tostring
local next = next

local function _cls_parse_error(cls, data, msg)
    local s = string.format("cls parse: <%s> <%s> %s", cls.name, tostring(data), tostring(msg))
    error(s)
end

-- 新增类型必须实现
-- is_atom 是否原子类型
-- default 默认值
-- parse 解析函数
-- new 构造函数（非atom类型）
-- setfield 修改属性（非atom类型）
local KEYWORD_MAP = {
    ["struct"] = require("orm_cls.struct"),
    ["map"] = require("orm_cls.dict"),
    ["list"] = require("orm_cls.list"),
    ["boolean"] = {is_atom=true, default=false,
        parse = function(_, s)
            return s == true
        end
    },
    ["integer"] = {is_atom=true, default=0,
        parse = function(cls, s)
            local value = math.tointeger(s)
            if value == nil then
                _cls_parse_error(cls, s, "is not integer")
            end
            return value
        end
    },
    ["double"] = {is_atom=true, default=0,
        parse = function(cls, s)
            local value = tonumber(s)
            if value == nil then
                _cls_parse_error(cls, s, "is not double")
            end
            return value
        end
    },
    ["string"] = {is_atom=true, default="",
        parse = function(_, s)
            return tostring(s)
        end
    },
    ["binary"] = {is_atom=true, default="",
        parse = function(_, s)
            return s
        end
    },
    ["date"] = {is_atom=true, default=nil,
        parse = function(_, s)
            return s
        end
    },
}

local KEYWORD_ATTRS = {
    ['__cls'] = true,
    ['__dirty'] = true,
    ['__data'] = true,
}

local function has_cls_type(cls_type)
    return KEYWORD_MAP[cls_type]
end

local function get_register_cls(cls_type)
    return KEYWORD_MAP[cls_type]
end

local g_cls_ref_map = {} -- cls_name : [parent_name, ...]
local g_cls_map = {} -- cls_name: cls

local function check_ref(node_id, parent_id)
    -- print('check ref', node_id, parent_id)
    if parent_id == nil then
        return
    end

    if parent_id == node_id then
        error(string.format('type<%s> ref redefined', node_id))
    end

    local p_map = g_cls_ref_map[node_id]
    if not p_map then
        p_map = {}
        g_cls_ref_map[node_id] = p_map
    end

    p_map[parent_id] = true -- record parent

    -- check and update parent's parent
    local pp_map = g_cls_ref_map[parent_id]
    if not pp_map then
        pp_map = {}
        g_cls_ref_map[parent_id] = pp_map
    end

    for pp_id, _ in pairs(pp_map) do
        check_ref(node_id, pp_id)
    end
end

local function create_cls(cls, parent_name)
    if parent_name then
        cls.name = parent_name .. "." .. cls.name
    end

    local cls_name = cls.name
    local cls_type = cls.type

    if has_cls_type(cls_name) then
        error(string.format("cls name<%s> is keyword", cls_name))
        return nil
    end

    if not cls_type then
        error(string.format(" cls name<%s> invalid cls type", cls_name))
        return nil
    end

    -- ref type
    local ref_cls = g_cls_map[cls_type]
    if ref_cls then
        check_ref(ref_cls.name, parent_name)
        -- copy ref
        for k, v in pairs(ref_cls) do
            cls[k] = v
        end
        -- reset name
        cls.name = cls_name
        if not ref_cls.id then
            assert(false, cls.name)
            cls.id = ref_cls
        end
        return cls
    end

    local cls_cfg = get_register_cls(cls_type)
    if not (cls_cfg and cls_cfg.parse) then
        error(string.format("data type <%s> <%s> no parse", cls_name, cls_type))
        return nil
    end

    check_ref(cls_name, parent_name)

    cls.id = cls
    cls.parse = cls_cfg.parse
    cls.is_atom = cls_cfg.is_atom
    cls.default = cls_cfg.default

    if cls.is_atom then
        return cls
    end

    cls.new = cls_cfg.new
    local mt_index = {
        __cls = cls,
        __enable_dirty = Dirty.__enable_dirty,
        __disable_dirty = Dirty.__disable_dirty,
        __get_dirty = Dirty.__get_dirty,
        __clear_dirty = Dirty.__clear_dirty,
    }
    local mt = {
        __index = function(t, key)
            return t.__data[key] or mt_index[key]
        end,
        __newindex = cls_cfg.setfield,
        __pairs = function(t)
            return next, t.__data, nil
        end,
    }
    -- TODO 其他元表补充
    cls.mt = mt

    if cls_type == 'struct' then
        assert(cls.attrs, "not attrs")
        local attrs = {}
        for k, v in pairs(cls.attrs) do
            if KEYWORD_ATTRS[k] then
                error(string.format("class <%s> define key attr <%s>", cls_name, k))
            end
            v.name = k
            local v_cls = create_cls(v, cls_name)
            if v_cls.is_atom then
                mt_index[k] = v_cls.default
            end
            attrs[k] = v_cls
        end
        cls.attrs = attrs
        return cls
    end

    if cls_type == 'list' then
        mt.__ipairs = function(t)
            return function(a, i)
                i = i + 1
                local v = a[i]
                if v then return i, v end
            end, t.__data, 0
        end
        mt.__len = function(t)
            return rawlen(t.__data)
        end
        mt.__concat = function(t)
            return tconcat(t.__data)
        end

        cls.item.name = 'item'
        cls.item = create_cls(cls.item, cls_name)
        return cls
    end

    if cls_type == 'map' then
        cls.key.name = 'key'
        cls.key = create_cls(cls.key, cls_name)
        cls.value.name = 'value'
        cls.value = create_cls(cls.value, cls_name)
        return cls
    end
    error(string.format("unsupport cls type<%s>", cls_type))
end

local M = {}

function M.init(type_list)
    -- reset
    g_cls_map = {}
    g_cls_ref_map = {}

    for _, item in ipairs(type_list) do
        local name = item.name
        assert(name, 'not cls name')
        g_cls_map[name] = create_cls(item, nil)
    end
    M.g_cls_map = g_cls_map
    M.g_cls_ref_map = g_cls_ref_map
end

function M.create(cls_name, data)
    local cls = g_cls_map[cls_name]
    if not cls then
        error(string.format("create obj, illgeal cls<%s>", cls_name))
    end
    return cls:new(data)
end

-- dirty manager 挂载到节点
function M.enable_dirty(obj)
    obj:__enable_dirty(nil, nil)
end
function M.disable_dirty(obj)
    obj:__disable_dirty()
end

function M.get_dirty_info(obj)
    return Dirty.get_dirty_info(obj)
end
function M.clear_dirty_info(obj)
    return Dirty.clear_dirty_info(obj)
end
function M.get_mongo_dirty_data(obj)
    return Dirty.get_mongo_dirty_data(obj)
end

-- 提供用于全量存盘
function M.clone_mongodata(obj)
    return Dirty.clone_mongodata(obj)
end

return M
