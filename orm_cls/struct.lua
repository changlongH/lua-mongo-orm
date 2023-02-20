--[[
*  @Author      : huangchanglong
*  @Date        : 2023-02-08 13:47
*  LastEditors  : huangchanglong
*  LastEditTime : 2023-02-08 13:47
*  @Description : orm struct实现
--]]

local Dirty = require("dirty")

local setmetatable = setmetatable
local type = type
local rawset = rawset
local rawget = rawget

local DIRTY_SET = Dirty.DIRTY_SET
local DIRTY_ADD = Dirty.DIRTY_ADD
local DIRTY_DEL = Dirty.DIRTY_DEL
local set_dirty_map = Dirty.set_dirty_map

local Struct = {
    is_atom = false,
    default = nil,
}

local function _cls_parse_error(cls, data, msg)
    local s = string.format("list parse: <%s> <%s> %s", cls.name, tostring(data), msg)
    error(s)
end

-- copy data
function Struct.new(cls, data)
    local obj = {
        ['__data'] = {},
        ['__ref'] = nil
    }
    setmetatable(obj, cls.mt)

    if data == nil then
        return obj
    end
    for k, v in pairs(data) do
        obj[k] = v -- 触发元表
    end
    return obj
end

function Struct.setfield(obj, k, v)
    local cls = obj.__cls
    if not cls then
        error(string.format("cls struct not define. set unknow cls attr<%s>:<%s>", k, tostring(v)))
    end

    local v_cls = cls.attrs[k]
    if not v_cls then
        error(string.format('cls struct: <%s> has no attr<%s>', cls.name, k))
    end

    local old_v = rawget(obj.__data, k)
    if old_v == v then
        return
    end

    -- remove
    if v == nil then
        rawset(obj.__data, k, nil)
        if (not v_cls.is_atom) and old_v then
            rawset(old_v, '__ref', nil)
            old_v:__disable_dirty()
        end
        set_dirty_map(obj, k, DIRTY_DEL)
        return
    end

    -- set/add
    if type(v) == 'table' and v.__cls ~= nil then
        -- value 是一个 <cls object> 校验<class id/name>
        local ref = rawget(v, '__ref')
        if ref or v_cls.id.name ~= v.__cls.name then
            local s = string.format(
                'cls struct: <%s.%s> value error. need<%s> give<%s> ref<%s>',
                cls.name, k, v_cls.id.name, v.__cls.name, tostring(ref)
            )
            error(s)
        end
    else
        v = v_cls:parse(v)
    end

    -- 先赋值
    rawset(obj.__data, k, v)

    -- 新值标记引用/旧值解除引用
    if not v_cls.is_atom then
        rawset(v, '__ref', true)
        if old_v then
            rawset(old_v, '__ref', nil)
            old_v:__disable_dirty()
        end
    end

    -- 标记脏数据
    if old_v then
        set_dirty_map(obj, k, DIRTY_SET)
    else
        set_dirty_map(obj, k, DIRTY_ADD)
    end
end

function Struct.parse(cls, data)
    if data == nil then
        return cls:new()
    end

    if type(data) ~= 'table' then
        _cls_parse_error(cls, data, "is not table")
    end

    local ret = {}
    for attr_name, attr_cls in pairs(cls.attrs) do
        local attr_data = data[attr_name]
        if attr_data ~= nil then
            -- 有数据必然初始化
            ret[attr_name] = attr_cls:parse(attr_data)
        else
            -- 没有数据，非原子类型也需要初始化
            if (not attr_cls.is_atom) then
                ret[attr_name] = attr_cls:parse(attr_data)
            end
        end
    end
    -- 多一次copy
    return cls:new(ret)
end

return Struct
