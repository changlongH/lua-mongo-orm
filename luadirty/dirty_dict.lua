--[[
*  @Company     : JunhaiGame
*  @Author      : huangchanglong
*  @Email       : huangchanglong@ijunhai.com
*  @Date        : 2023-02-01 15:05
*  LastEditors  : huangchanglong
*  LastEditTime : 2023-02-01 15:05
*  @Description : dirty dict 类
--]]

local Consts = require("dirty_consts")
local Util = require("dirty_util")

local next = next
local rawset = rawset
local type = type

local DIRTY_SET = Consts.DIRTY_SET
local DIRTY_ADD = Consts.DIRTY_ADD
local DIRTY_DEL = Consts.DIRTY_DEL

-- DirtyWrap
local WRAP_RAW_DICT = Consts.WRAP_RAW_DICT
local WRAP_DIRTY_MNG = Consts.WRAP_DIRTY_MNG
local WRAP_REF = Consts.WRAP_REF

-- DirtyManage
local MNG_PARENT = Consts.MNG_PARENT
local MNG_SELF_KEY = Consts.MNG_SELF_KEY
local MNG_DIRTY_NODE = Consts.MNG_DIRTY_NODE

-- DirtyNode
local NODE_DIRTY_OP_DICT = Consts.NODE_DIRTY_OP_DICT

local Dict = {}

local assertInvalidValue = Util.assertInvalidValue

local function setDirtyMap(wrap, key, op, oldValue)
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
        -- 先回收，然后修改脏标记
        if recycle then
            -- 解除引用
            rawset(oldValue, WRAP_REF, nil)
            oldValue:__disable_dirty()
        end
        Util.overwriteMapDirtyKey(dirtyNode, key, op)
    else
        -- 先插入脏标记，然后回收
        Util.dirtyNodeInsertMapKey(dirtyNode, key, op)
        if recycle then
            rawset(oldValue, WRAP_REF, nil)
            oldValue:__disable_dirty()
        end
    end
end

local function onDictModify(wrap, key, value)
    local rawDict = wrap:__get_data()
    local oldValue = rawDict[key]
    if value ~= nil then
        -- 重复赋值不处理
        if value == oldValue then
            return
        end
        if type(value) == 'table' then
            assertInvalidValue(value, Dict.init)
            -- 引用标记
            rawset(value, WRAP_REF, true)
        end
    end

    if not wrap:__get_manage() then
        rawset(rawDict, key, value)
        return
    end

    if value == nil then
        -- 不存在 无需处理
        if oldValue then
            setDirtyMap(wrap, key, DIRTY_DEL, oldValue);
            rawset(rawDict, key, value)
        end
    else
        rawset(rawDict, key, value)
        if oldValue then
            setDirtyMap(wrap, key, DIRTY_SET, oldValue)
        else
            setDirtyMap(wrap, key, DIRTY_ADD)
        end
    end
end

local Meta = {
    __index = function(wrap, key)
        --print(wrap, key)
        return wrap[WRAP_RAW_DICT][key]
    end,
    __newindex = function(wrap, key, value)
        --print(wrap, key, value)
        onDictModify(wrap, key, value)
    end,
    --[[
    __ipairs = function()
        assert(false, "dict type not support ipairs")
    end,
    --]]
    __pairs = function(wrap)
        return next, wrap[WRAP_RAW_DICT], nil
    end,

    -- 自定义方法
    __get_raw_dict = function(wrap)
        return rawget(wrap, WRAP_RAW_DICT)
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

        local rawDict = wrap:__get_data()
        -- 清理脏数据时，先把后面add/set的node enable
        for dk, op in pairs(dirtyNode[NODE_DIRTY_OP_DICT]) do
            if op ~= DIRTY_DEL then
                local v = rawDict[dk]
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
            return
        end
        local mng = Util.newDirtyManage(wrap, parent, skey)
        rawset(wrap, WRAP_DIRTY_MNG, mng)
        local rawDict = wrap:__get_data()
        for k, v in pairs(rawDict) do
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
        local rawDict = wrap:__get_data()
        for _, v in pairs(rawDict) do
            if type(v) == 'table' then
                v:__disable_dirty()
            end
        end
        -- 尾递归清理
        Util.freeDirtyManage(wrap)
    end,
}

function Dict.init(wrap)
    -- assert(next(wrap) == nil, "wrap must eq {}")
    wrap[WRAP_RAW_DICT] = {}
    wrap.__get_data = Meta.__get_raw_dict
    wrap.__get_manage = Meta.__get_manage
    wrap.__get_dirty = Meta.__get_dirty
    wrap.__clear_dirty = Meta.__clear_dirty
    wrap.__enable_dirty = Meta.__enable_dirty
    wrap.__disable_dirty = Meta.__disable_dirty
    setmetatable(wrap, Meta)
    return wrap
end

function Dict.new()
    local wrap = {
        [WRAP_RAW_DICT] = {},
        __get_data = Meta.__get_raw_dict,
        __get_manage = Meta.__get_manage,
        __get_dirty = Meta.__get_dirty,
        __clear_dirty = Meta.__clear_dirty,
        __enable_dirty = Meta.__enable_dirty,
        __disable_dirty = Meta.__disable_dirty,
    }
    setmetatable(wrap, Meta)
    return wrap
end

return Dict
