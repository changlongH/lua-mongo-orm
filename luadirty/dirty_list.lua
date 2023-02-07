--[[
*  @Company     : JunhaiGame
*  @Author      : huangchanglong
*  @Email       : huangchanglong@ijunhai.com
*  @Date        : 2023-02-06 20:46
*  LastEditors  : huangchanglong
*  LastEditTime : 2023-02-06 20:46
*  @Description : dirty list 类
--]]

local Consts = require("dirty_consts")
local Util = require("dirty_util")

local DIRTY_SET = Consts.DIRTY_SET
--local DIRTY_ADD = Consts.DIRTY_ADD
local DIRTY_DEL = Consts.DIRTY_DEL

-- DirtyWrap
local WRAP_RAW_LIST = Consts.WRAP_RAW_DICT
local WRAP_DIRTY_MNG = Consts.WRAP_DIRTY_MNG
local WRAP_REF = Consts.WRAP_REF

-- DirtyManage
local MNG_PARENT = Consts.MNG_PARENT
local MNG_SELF_KEY = Consts.MNG_SELF_KEY
local MNG_DIRTY_NODE = Consts.MNG_DIRTY_NODE

-- DirtyNode
local NODE_DIRTY_OP_DICT = Consts.NODE_DIRTY_OP_DICT

local rawget = rawget
local rawset = rawset
local type = type

local List = {}

local function setDirtyList(wrap, key, op, oldValue)
    local mng = wrap:__get_manage()
    if not mng then
        return
    end

    local dirtyNode = mng[MNG_DIRTY_NODE]
    if not dirtyNode then
        dirtyNode = Util.initDirtyNode(mng)
    end

    local recycle = oldValue and type(oldValue) == 'table'
    local has = Util.dirtyNodeMapHasKey(dirtyNode, key)

    if has then
        if recycle then
            -- 解除引用
            rawset(oldValue, WRAP_REF, nil)
            oldValue:__disable_dirty()
        end
        Util.overwriteMapDirtyKey(dirtyNode, key, op)
    else
        Util.dirtyNodeInsertMapKey(dirtyNode, key, op)
        if recycle then
            -- 解除引用
            rawset(oldValue, WRAP_REF, nil)
            oldValue:__disable_dirty()
        end
    end
end

local function onListModify(wrap, index, value)
    local rawList = wrap:__get_data()
    local size = #rawList
    local oldValue = rawList[index]
    if value ~= nil then
        if value == oldValue then
            return
        end
        -- set/add 数据校验数组连续性
        if index > (size + 1) then
            assert(false, "dirty list not support sparse. overload size")
        end
        if type(value) == 'table' then
            Util.assertInvalidValue(value)
            -- 引用标记
            rawset(value, WRAP_REF, true)
        end
    else
        -- 移除数据,校验数组连续性
        if index ~= #rawList then
            assert(false, "dirty list not support sparse. remove lastest")
        end
    end

    rawset(rawList, index,  value)
    if not wrap:__get_manage() then
        return
    end
    -- 全部设置为set
    setDirtyList(wrap, index, DIRTY_SET, oldValue)
end

local Meta = {
    __index = function(wrap, index)
        --print(wrap, key)
        return wrap[WRAP_RAW_LIST][index]
    end,

    __newindex = function(wrap, index, value)
        onListModify(wrap, index, value)
    end,

    __ipairs = function(wrap)
        local function iter(a, i)
            i = i + 1
            local v = a[i]
            if v then
                return i, v
            end
        end
        return iter, wrap[WRAP_RAW_LIST], 0
    end,
    __pairs = function(wrap)
        return next, wrap[WRAP_RAW_LIST], nil
    end,

    -- 自定义方法
    __get_raw_list = function(wrap)
        return rawget(wrap, WRAP_RAW_LIST)
    end,
    __get_manage = function(wrap)
        return rawget(wrap, WRAP_DIRTY_MNG)
    end,
    __get_dirty = function(wrap, ret)
        local mng = wrap:__get_manage()
        if mng == nil then
            return ret
        end
        -- 当前节点没有脏数据
        local dirtyNode = mng[MNG_DIRTY_NODE]
        if not dirtyNode or next(dirtyNode[NODE_DIRTY_OP_DICT]) == nil then
            return ret
        end

        -- 反向递归构建ret的path
        local function reverseMakeNodePath(_wrap, root)
            local _mng = _wrap:__get_manage()
            local parent = _mng[MNG_PARENT]
            if not parent then
                return root
            end
            local _ret = reverseMakeNodePath(parent, root)
            local skey = _mng[MNG_SELF_KEY]
            if not _ret[skey] then
                _ret[skey] = {}
            end
            return _ret[skey]
        end
        local dirtyRet = reverseMakeNodePath(wrap, ret)
        for dk, op in pairs(dirtyNode[NODE_DIRTY_OP_DICT]) do
            dirtyRet[dk] = op
        end

    end,
    __clear_dirty = function(wrap)
        local mng = wrap:__get_manage()
        local dirtyNode = mng and mng[MNG_DIRTY_NODE]
        if dirtyNode == nil then
            return
        end
        local rawList = wrap:__get_data()
        -- 清理脏数据时，先把后面add/set的node enable
        for dk, op in pairs(dirtyNode[NODE_DIRTY_OP_DICT]) do
            if op ~= DIRTY_DEL then
                local v = rawList[dk]
                if type(v) == 'table' then
                    v:__enable_dirty(wrap, dk)
                end
            end
        end
        -- 销毁当前节点的脏数据
        Util.destroyDirtyNode(mng)
    end,
    __enable_dirty = function(wrap, parent, skey)
        if wrap:__get_manage() then
            return false
        end
        local mng = Util.newDirtyManage(wrap, parent, skey)
        rawset(wrap, WRAP_DIRTY_MNG, mng)
        local rawList = wrap:__get_data()
        for k, v in ipairs(rawList) do
            if type(v) == 'table' then
                v:__enable_dirty(wrap, k)
            end
        end
        return true
    end,
    __disable_dirty = function(wrap)
        if not wrap:__get_manage() then
            return
        end
        local rawList = wrap:__get_data()
        for _, v in ipairs(rawList) do
            if type(v) == 'table' then
                v:__disable_dirty()
            end
        end
        -- 尾递归清理
        Util.freeDirtyManage(wrap)
    end,
}

function List.new()
    local wrap = {
        [WRAP_RAW_LIST] = {},
        __get_data = Meta.__get_raw_list,
        __get_manage = Meta.__get_manage,
        __get_dirty = Meta.__get_dirty,
        __clear_dirty = Meta.__clear_dirty,
        __enable_dirty = Meta.__enable_dirty,
        __disable_dirty = Meta.__disable_dirty,
    }
    setmetatable(wrap, Meta)
    return wrap
end

return List
