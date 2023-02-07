--[[
*  @Company     : JunhaiGame
*  @Author      : huangchanglong
*  @Email       : huangchanglong@ijunhai.com
*  @Date        : 2023-02-04 19:09
*  LastEditors  : huangchanglong
*  LastEditTime : 2023-02-04 19:09
*  @Description : 脏数据管理对外接口
--]]

local Consts = require("dirty_consts")
local DirtyDict = require("dirty_dict")
local DirtyList = require("dirty_list")

--local rawget = rawget
--local rawset = rawset
--local type = type

local Dirty = {}

-- DirtyManage
local MNG_SELF = Consts.MNG_SELF
local MNG_DIRTY_ROOT = Consts.MNG_DIRTY_ROOT

-- DirtyRoot
local RTNODE_DIRTY_NODE_CNT = Consts.RTNODE_DIRTY_NODE_CNT
local RTNODE_DIRTY_NODE_MAP = Consts.RTNODE_DIRTY_NODE_MAP

-- DirtyNode
local NODE_MNG_PTR = Consts.NODE_MNG_PTR

function Dirty.getDirtyInfo(wrap)
    local mng = wrap:__get_manage()
    if mng == nil then
        error("getDirtyInfo fail, not enable dirty")
        return nil
    end

    local dirtyRoot = mng[MNG_DIRTY_ROOT]
    if dirtyRoot == nil then
        error("getDirtyInfo fail, this not dirty root node")
        return nil
    end

    local amount = dirtyRoot[RTNODE_DIRTY_NODE_CNT]
    local ret = {}
    local cnt = 0
    for dirtyNode in pairs(dirtyRoot[RTNODE_DIRTY_NODE_MAP]) do
        cnt = cnt + 1
        local self = dirtyNode[NODE_MNG_PTR][MNG_SELF]
        self:__get_dirty(ret)
    end
    if amount ~= cnt then
        local errmsg = string.format("dirty node cnt error. expect<%d> get<%d>", amount, cnt)
        assert(false, errmsg)
    end
    return ret
end

function Dirty.clearDirty(wrap)
    local mng = wrap:__get_manage()
    if mng == nil then
        return false
    end

    local dirtyRoot = mng[MNG_DIRTY_ROOT]
    if dirtyRoot == nil then
        return false
    end

    local amount = dirtyRoot[RTNODE_DIRTY_NODE_CNT]

    -- 从根节点开始清理脏数据
    local cnt = 0
    while true do
        local dirtyNode = next(dirtyRoot[RTNODE_DIRTY_NODE_MAP])
        if dirtyNode == nil then
            break
        end
        cnt = cnt + 1
        local self = dirtyNode[NODE_MNG_PTR][MNG_SELF]
        self:__clear_dirty()
    end

    local left = dirtyRoot[RTNODE_DIRTY_NODE_CNT]
    if amount ~= cnt and left ~= 0 then
        local errmsg = string.format("clear dirty node error. expect<%d> clear<%d> left<%d>", amount, cnt, left)
        assert(false, errmsg)
    end
end

function Dirty.enableDirty(wrap)
    wrap:__enable_dirty(nil, nil)
end

function Dirty.disableDirty(wrap)
    wrap:__disable_dirty()
end

function Dirty.newDict()
    return DirtyDict.new()
end

function Dirty.newList()
    return DirtyList.new()
end

return Dirty
