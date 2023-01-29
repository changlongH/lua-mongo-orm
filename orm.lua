-- lua function enable_oldindex can enable or disable metamethod __oldindex
local enable_oldindex = enable_oldindex or (function() end)

local tonumber = tonumber
local tostring = tostring

local KEYWORD_ATTRS = {
    ['__cls'] = true
}

-- 业务注册对应类型 integer boolean string binary map list struct date
local KEYWORD_MAP = {}
local function register_atom_type(cls_type, parse, default)
    KEYWORD_MAP[cls_type] = {is_atom = true, parse = parse, default = default}
end
local function register_complex_type(cls_type, new, parse)
    KEYWORD_MAP[cls_type] = {is_atom = false, new = new, parse = parse, default = nil}
end

local function has_cls_type(cls_type)
    return KEYWORD_MAP[cls_type]
end

local function get_register_cls(cls_type)
    return KEYWORD_MAP[cls_type]
end

local function get_default(cls_type)
    return KEYWORD_MAP[cls_type].default
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

------------ parse begin -----------
local function _cls_parse_error(cls, data, msg)
    local s = string.format("cls parse: <%s> <%s> %s", cls.name, data, msg)
    error(s)
end

local function parse_boolean(_, s)
    return s == true
end

local function parse_string(_, s)
    return tostring(s)
end

local function parse_integer(cls, s)
    local value = math.tointeger(s)
    if value == nil then
        _cls_parse_error(cls, s, "is not integer")
    end

    return value
end

local function parse_double(cls, s)
    local value = tonumber(s)
    if value == nil then
        _cls_parse_error(cls, s, "is not double")
    end
    return value
end

local function parse_binary(_, s)
    return s
end

local function parse_date(_, s)
    return s
end

local function parse_struct(cls, data)
    if data == nil then
        return cls:new()
    end

    if type(data) ~= 'table' then
        _cls_parse_error(cls, data, "is not table")
    end

    local ret = {}
    for attr_name, attr_cls in pairs(cls.attrs) do
        local attr_data = data[attr_name]
        -- 没有数据且原子类型情况下不需要初始化
        if not (attr_data == nil and attr_cls.is_atom) then
            ret[attr_name] = attr_cls:parse(attr_data)
        end
    end
    -- print('parse struct create obj', cls.name, ret)
    return cls:new(ret)
end

local function parse_list(cls, data)
    if data == nil then
        return cls:new()
    end

    if type(data) ~= 'table' then
        _cls_parse_error(cls, data, "is not table")
    end

    local ret = {}
    local item_cls = cls.item
    for _, _data in ipairs(data) do
        table.insert(ret, item_cls:parse(_data))
    end
    return cls:new(ret)
end

local function parse_map(cls, data)
    if data == nil then
        return cls:new()
    end

    if type(data) ~= 'table' then
        _cls_parse_error(cls, data, "is not table")
    end

    --local cls_name = cls.name
    local k_cls = cls.key
    local v_cls = cls.value
    local ret = {}
    for k_data, v_data in pairs(data) do
        ret[k_cls:parse(k_data)] = v_cls:parse(v_data)
    end
    return cls:new(ret)
end
------------ parse end -----------

---------------create begin ---------------
local function create_struct(cls, data)
    local obj = {}
    enable_oldindex(obj, true)
    setmetatable(obj, cls.mt)

    if data == nil then
        for k, v in pairs(cls.attrs) do
            if not v.is_atom then
                -- 深度初始化非原子类型数据
                -- 触发struct_setfield
                obj[k] = nil
            end
        end
    else
        for k, v in pairs(cls.attrs) do
            local k_data = data[k]
            -- 原子类型且无数据则不赋值
            if not (k_data == nil and v.is_atom) then
                obj[k] = k_data
            end
        end
    end
    return obj
end

local function create_list(cls, data)
    local obj = {}
    enable_oldindex(obj, true)
    setmetatable(obj, cls.mt)

    if data == nil then
        return obj
    end

    for idx, item in ipairs(data) do
        obj[idx] = item
    end
    return obj
end

local function create_map(cls, data)
    local obj = {}
    enable_oldindex(obj, true)
    setmetatable(obj, cls.mt)

    if data == nil then
        return obj
    end

    for k, v in pairs(data) do
        obj[k] = v
    end
    return obj
end
---------------create finish ---------------

--------------- setfield begin ------------
local function struct_setfield(obj, k, v)
    local cls = obj.__cls
    if not cls then
        error(string.format("struct no cls info"))
    end

    local v_cls = cls.attrs[k]
    if not v_cls then
        error(string.format('cls struct: <%s> has no attr<%s>', cls.name, k))
    end

    -- optimize, trust cls obj by name
    if type(v) == 'table' and v.__cls ~= nil then
        if v_cls.id == v.__cls.id then
            rawset(obj, k, v)
            return
        end
        local s = string.format(
            'cls struct: <%s.%s> value type not match need<%s> give<%s>',
            cls.name, k, v_cls.id.name, v.__cls.name
        )
        error(s)
    end

    -- if v == nil, set node default
    -- print('-- struct, paser ', cls.name, k, v, v_cls.name, v_cls.parse)
    if v == nil and v_cls.is_atom then
        rawset(obj, k, nil)
        return
    end

    rawset(obj, k, v_cls:parse(v))
end

local function list_setfield(obj, k, v)
    -- print('list __newindex', obj, k, v)
    local cls = obj.__cls
    if not cls then
        error(string.format("list no cls info"))
    end

    if k ~= math.tointeger(k) then
        local s = string.format('cls list: <%s.%s> = %s is not integer index', cls.name, k, v)
        error(s)
    end

    if v == nil then -- if v == nil, remove node
        rawset(obj, k, nil)
        return
    end

    local v_cls = cls.item
    -- optimize, trust cls obj by name
    if type(v) == 'table' and v.__cls ~= nil then
        if v_cls.id == v.__cls.id then
            -- print(
            --     '-- list trust cls obj',
            --     cls.name, k, v_cls.name, v.__cls
            -- )
            rawset(obj, k, v)
            return
        end
        local s = string.format(
            'cls list: <%s.%s> value type not match need<%s> give<%s>',
            cls.name, k, v_cls.id.name, v.__cls.name
        )
        error(s)
    end

    rawset(obj, k, v_cls:parse(v))
end

local function map_setfield(obj, k, v)
    -- print('map __newindex', obj, k, v)
    local cls = obj.__cls
    if not cls then
        error(string.format("cls map invalid to set <nil.%s> = %s", k, v))
    end

    local k_data = cls.key:parse(k)
    if v == nil then
        -- remove node
        rawset(obj, k_data, nil)
        return
    end

    local v_cls = cls.value
    -- optimize, trust cls obj by name
    if type(v) == 'table' and v.__cls ~= nil then
        if v_cls.id == v.__cls.id then
            -- print(
            --     '-- map trust cls obj',
            --     cls.name, k, v_cls.name, v.__cls
            -- )
            rawset(obj, k_data, v)
            return
        end

        local s = string.format(
            'cls map:<%s.%s> value type not match need<%s> give<%s>',
            cls.name, k_data, v_cls.id.name, v.__cls.name
        )
        error(s)
    end

    rawset(obj, k_data, v_cls:parse(v))
end
------------- setfield end ---------


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

    local reg_cls = get_register_cls(cls_type)
    if not (reg_cls and reg_cls.parse) then
        error(string.format("data type <%s> <%s> no parse", cls_name, cls_type))
        return nil
    end

    check_ref(cls_name, parent_name)

    cls.id = cls
    cls.parse = reg_cls.parse
    cls.is_atom = reg_cls.is_atom

    if cls.is_atom then
        return cls
    end

    if cls_type == 'struct' then
        cls.new = reg_cls.new
        local mt_index = {__cls = cls}
        cls.mt = {
            __index = mt_index,
            __newindex = struct_setfield,
            __oldindex = struct_setfield,
        }
        assert(cls.attrs, "not attrs")
        local attrs = {}
        for k, v in pairs(cls.attrs) do
            if KEYWORD_ATTRS[k] then
                error(string.format("class <%s> define key attr <%s>", cls_name, k))
            end
            v.name = k
            local v_cls = create_cls(v, cls_name)
            if v_cls.is_atom then
                -- set default in meta index
                mt_index[k] = get_default(v_cls.type)
            end
            attrs[k] = v_cls
        end
        cls.attrs = attrs
        return cls
    end

    if cls_type == 'list' then
        cls.new = reg_cls.new
        cls.mt = {
            __index = {__cls = cls},
            __newindex = list_setfield,
            __oldindex = list_setfield,
        }
        cls.item.name = 'item'
        cls.item = create_cls(cls.item, cls_name)
        return cls
    end

    if cls_type == 'map' then
        cls.new = reg_cls.new
        cls.mt = {
            __index = {__cls = cls},
            __newindex = map_setfield,
            __oldindex = map_setfield,
        }
        cls.key.name = 'key'
        cls.key = create_cls(cls.key, cls_name)
        cls.value.name = 'value'
        cls.value = create_cls(cls.value, cls_name)
        return cls
    end
    error(string.format("unsupport cls type<%s>", cls_type))
end

register_atom_type("boolean", parse_boolean, false)
register_atom_type("integer", parse_integer, 0)
register_atom_type("double", parse_double, 0)
register_atom_type("string", parse_string, "")
register_atom_type("binary", parse_binary, "")
register_atom_type("date", parse_date, nil) -- mongodb ISODate bson.date(timestamp)

register_complex_type("map", create_map, parse_map)
register_complex_type("list", create_list, parse_list)
register_complex_type("struct", create_struct, parse_struct)

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

return M
