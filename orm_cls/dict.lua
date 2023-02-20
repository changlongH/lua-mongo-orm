--[[
*  @Author      : huangchanglong
*  @Date        : 2023-02-08 15:18
*  LastEditors  : huangchanglong
*  LastEditTime : 2023-02-08 15:18
*  @Description : orm dict 实现
--]]

local Dirty = require('dirty')

local setmetatable = setmetatable
local type = type
local rawset = rawset
local rawget = rawget
local string_find = string.find
local string_sub = string.sub

local DIRTY_SET = Dirty.DIRTY_SET
local DIRTY_ADD = Dirty.DIRTY_ADD
local DIRTY_DEL = Dirty.DIRTY_DEL
local NUMBER_KEY_SUB_CNT = Dirty.NUMBER_KEY_SUB_CNT
local NUMBER_KEY_PRE_MATCH = Dirty.NUMBER_KEY_PRE_MATCH

local set_dirty_map = Dirty.set_dirty_map


local Dict = {
    is_atom = false,
    default = nil,
}

local function _cls_parse_error(cls, data, msg)
    local s = string.format("dict parse: <%s> <%s> %s", cls.name, data, msg)
    error(s)
end

-- copy data
function Dict.new(cls, data)
    local obj = {
        ['__data'] = {},
        --['__ref'] = nil
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

function Dict.setfield(obj, k, v)
    local cls = obj.__cls
    if not cls then
        error(string.format("cls map not define. set <unknow.%s>:<%s>", k, tostring(v)))
    end

    local v_cls = cls.value
    -- 转换key类型
    k = cls.key:parse(k)

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

    -- add/set
    if type(v) == 'table' and v.__cls ~= nil then
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

function Dict.parse(cls, data)
    if data == nil then
        return cls:new()
    end

    if type(data) ~= 'table' then
        _cls_parse_error(cls, data, "is not table")
    end

    --local cls_name = cls.name
    local k_cls = cls.key
    local v_cls = cls.value

    -- 整数类型key需要额外处理前缀
    -- 可以选择bson层处理，但是需要注意稀疏数组
    local unpack_key = false
    if k_cls['type'] == 'integer' then
        unpack_key = true
    end

    local ret = {}
    for k_data, v_data in pairs(data) do
        if unpack_key and string_find(k_data, NUMBER_KEY_PRE_MATCH) then
            k_data = string_sub(k_data, NUMBER_KEY_SUB_CNT)
        end
        ret[k_cls:parse(k_data)] = v_cls:parse(v_data)
    end
    return cls:new(ret)
end

return Dict
