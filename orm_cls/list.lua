--[[
*  @Author      : huangchanglong
*  @Date        : 2023-02-08 15:27
*  LastEditors  : huangchanglong
*  LastEditTime : 2023-02-08 15:27
*  @Description : orm list 实现
--]]

local Dirty = require("dirty")

local setmetatable = setmetatable
local type = type
local rawset = rawset
local rawget = rawget
local tointeger = math.tointeger

local DIRTY_SET = Dirty.DIRTY_SET
--local DIRTY_ADD = Dirty.DIRTY_ADD
local DIRTY_DEL = Dirty.DIRTY_DEL
local set_dirty_map = Dirty.set_dirty_map


local List = {
    is_atom = false,
    default = nil,
}

local function _cls_parse_error(cls, data, msg)
    local s = string.format("cls parse: <%s> <%s> %s", cls.name, data, msg)
    error(s)
end

function List.new(cls, data)
    local obj = {
        ['__data'] = {},
        ['__ref'] = nil
    }
    setmetatable(obj, cls.mt)

    if data == nil then
        return obj
    end

    for idx, item in ipairs(data) do
        obj[idx] = item -- 触发元表
    end
    return obj
end

function List.setfield(obj, k, v)
    local cls = obj.__cls
    if not cls then
        error(string.format("list no cls define. set attr<%s>:<%s>", tostring(k), tostring(v)))
    end

    local index = tointeger(k)
    if k ~= index then
        local s = string.format('cls list: <%s.%s> = %s index is not integer', cls.name, k, v)
        error(s)
    end

    local old_v = rawget(obj.__data, index)
    if old_v == v then
        return
    end
    local v_cls = cls.item
    local size = #obj.__data

    local dirty_op
    if v == nil then
        -- remove 移除数据,校验数组连续性
        if index ~= size then
            local s = string.format("cls list not support sparse. can not remove index<%d> maxsize<%d>", index, size)
            error(s)
        end
        dirty_op = DIRTY_DEL
    else
        -- add/set不能越界
        if index > (size + 1) then
            local s = string.format("cls list not support sparse. can set index<%d> maxsize<%d>", index, size)
            error(s)
        end

        if type(v) == 'table' and v.__cls ~= nil then
            local ref = rawget(v, '__ref')
            if ref or v_cls.id.name ~= v.__cls.name then
                local s = string.format(
                'cls list: <%s.%s> value error. need<%s> give<%s> ref<%s>',
                cls.name, k, v_cls.id.name, v.__cls.name, tostring(ref)
                )
                error(s)
            end
        else
            v = v_cls:parse(v)
        end
        dirty_op = DIRTY_SET
    end

    rawset(obj.__data, index, v)
    if not v_cls.is_atom then
        if v then
            rawset(v, '__ref', true)
        end
        if old_v then
            rawset(old_v, '__ref', nil)
            old_v:__disable_dirty()
        end
    end
    -- set 不存在的字段 set语句不会生成
    -- unset 一个不存在的字段 执行无异常
    set_dirty_map(obj, index, dirty_op)
end

function List.parse(cls, data)
    if data == nil then
        return cls:new()
    end

    if type(data) ~= 'table' then
        _cls_parse_error(cls, data, "is not table")
    end
    -- 校验数据连续性
    local size = #data

    local index = 0
    local ret = {}
    local item_cls = cls.item
    for _, item in ipairs(data) do
        index = index + 1
        table.insert(ret, item_cls:parse(item))
    end

    if size ~= index then
        local s = string.format("cls list not support sparse. maxsize<%d> index<%d> is nil", size, index+1)
        error(s)
    end
    return cls:new(ret)
end

return List
