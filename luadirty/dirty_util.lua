--[[
*  @Company     : JunhaiGame
*  @Author      : huangchanglong
*  @Email       : huangchanglong@ijunhai.com
*  @Date        : 2023-02-02 09:13
*  LastEditors  : huangchanglong
*  LastEditTime : 2023-02-02 09:13
*  @Description : description
--]]

local Consts = require("dirty_consts")

local Util = {}

local DIRTY_SET = Consts.DIRTY_SET
local DIRTY_ADD = Consts.DIRTY_ADD
local DIRTY_DEL = Consts.DIRTY_DEL

-- wrap
local WRAP_DIRTY_MNG = Consts.WRAP_DIRTY_MNG
local WRAP_REF = Consts.WRAP_REF
local WRAP_RAW_DICT = Consts.WRAP_RAW_DICT
local WRAP_RAW_LIST = Consts.WRAP_RAW_LIST

-- DirtyManage
local MNG_SELF = Consts.MNG_SELF
local MNG_ROOT = Consts.MNG_ROOT
local MNG_PARENT = Consts.MNG_PARENT
local MNG_SELF_KEY = Consts.MNG_SELF_KEY
local MNG_DIRTY_NODE = Consts.MNG_DIRTY_NODE
local MNG_DIRTY_ROOT = Consts.MNG_DIRTY_ROOT


-- DirtyRoot
local RTNODE_DIRTY_NODE_CNT = Consts.RTNODE_DIRTY_NODE_CNT
local RTNODE_DIRTY_NODE_MAP = Consts.RTNODE_DIRTY_NODE_MAP

-- DirtyNode
local NODE_MNG_PTR = Consts.NODE_MNG_PTR
local NODE_DIRTY_OP_DICT = Consts.NODE_DIRTY_OP_DICT
local NODE_DIRTY_OP_CNT = Consts.NODE_DIRTY_OP_CNT

local function isDirtyDict(wrap)
    return rawget(wrap, WRAP_RAW_DICT) and true or false
end
Util.isDirtyDict = isDirtyDict

local function isDirtyList(wrap)
    return rawget(wrap, WRAP_RAW_LIST) and true or false
end
Util.isDirtyList = isDirtyList

local function dirtyRootAdd(dirtyRoot, dirtyNode)
    dirtyRoot[RTNODE_DIRTY_NODE_MAP][dirtyNode] = true

    local cnt = dirtyRoot[RTNODE_DIRTY_NODE_CNT]
    dirtyRoot[RTNODE_DIRTY_NODE_CNT] = cnt + 1
end
Util.dirtyRootAdd = dirtyRootAdd

local function dirtyRootRemove(dirtyRoot, dirtyNode)
    dirtyRoot[RTNODE_DIRTY_NODE_MAP][dirtyNode] = nil

    local cnt = dirtyRoot[RTNODE_DIRTY_NODE_CNT]
    dirtyRoot[RTNODE_DIRTY_NODE_CNT] = cnt - 1
end
Util.dirtyRootRemove = dirtyRootRemove

local function destroyDirtyNode(mng)
    local dirtyNode = mng[MNG_DIRTY_NODE]
    -- root 中移除
    local rootManage = mng[MNG_ROOT]:__get_manage()
    local dirtyRoot = rootManage[MNG_DIRTY_ROOT]
    dirtyRootRemove(dirtyRoot, dirtyNode)

    -- TODO 使用node pool 回收
    -- 解引用
    dirtyNode[NODE_MNG_PTR] = nil
    -- 内存回收
    mng[MNG_DIRTY_NODE] = nil
end
Util.destroyDirtyNode = destroyDirtyNode

-------- dirty manage begin -----
local function dirtyManageInit(self, root, parent, skey)
    local mng = {
        [MNG_SELF] = self, -- 目前是指向数据块
        [MNG_ROOT] = root,
        [MNG_PARENT] = parent,
        [MNG_SELF_KEY] = skey,
        [MNG_DIRTY_NODE] = nil, -- 惰性初始化
    }
    return mng
end

local function dirtyRootInit(mng)
    mng[MNG_DIRTY_ROOT] = {
        [RTNODE_DIRTY_NODE_CNT] = 0,
        [RTNODE_DIRTY_NODE_MAP] = {},
    }
end

function Util.newDirtyManage(wrap, pwrap, skey)
    local mng
    if pwrap == nil then
        mng = dirtyManageInit(wrap, wrap, pwrap, skey)
        dirtyRootInit(mng)
    else
        local parentManage = pwrap:__get_manage()
        mng = dirtyManageInit(wrap, parentManage[MNG_ROOT], pwrap, skey)
    end
    return mng
end

local function freeDirtyManage(wrap)
    local mng = wrap:__get_manage()
    print(mng[MNG_SELF_KEY])
    local dirtyNode = mng[MNG_DIRTY_NODE]
    if dirtyNode then
        destroyDirtyNode(mng)
    end

    -- 避免内存泄露
    mng[MNG_SELF] = nil
    mng[MNG_ROOT] = nil
    mng[MNG_PARENT] = nil
    mng[MNG_SELF_KEY] = nil
    mng[MNG_DIRTY_ROOT] = nil

    rawset(wrap, WRAP_REF, nil)
    rawset(wrap, WRAP_DIRTY_MNG, nil)
end
Util.freeDirtyManage = freeDirtyManage
-------- dirty manage  end  -----

--------- dirty node begin ----------
function Util.initDirtyNode(mng)
    local dirtyNode = {
        [NODE_MNG_PTR] = mng,
        [NODE_DIRTY_OP_DICT] = {},
        [NODE_DIRTY_OP_CNT] = 0,
    }
    -- 根据root获取root->dirty_manage
    -- dirtyNode 插入道rootManage 的dirtyRoot中管理
    local rootManage = mng[MNG_ROOT]:__get_manage()
    Util.dirtyRootAdd(rootManage[MNG_DIRTY_ROOT], dirtyNode)
    mng[MNG_DIRTY_NODE] = dirtyNode
    return dirtyNode
end

function Util.dirtyNodeMapHasKey(dirtyNode, key)
    return dirtyNode[NODE_DIRTY_OP_DICT][key] and true or false
end
function Util.dirtyNodeInsertMapKey(dirtyNode, key, op)
    dirtyNode[NODE_DIRTY_OP_DICT][key] = op
    dirtyNode[NODE_DIRTY_OP_CNT] = dirtyNode[NODE_DIRTY_OP_CNT] + 1
end
function Util.dirtyNodeRemoveMapKey(dirtyNode, key)
    dirtyNode[NODE_DIRTY_OP_DICT][key] = nil
    dirtyNode[NODE_DIRTY_OP_CNT] = dirtyNode[NODE_DIRTY_OP_CNT] - 1
end
--------- dirty node  end  ----------

-- merge标记
function Util.overwriteMapDirtyKey(dirtyNode, key, newOp)
    local dirtyOpMap = dirtyNode[NODE_DIRTY_OP_DICT]
    local dkop = dirtyOpMap[key]
    if dkop == newOp then
        return
    end

    if dkop == DIRTY_DEL then
        if newOp == DIRTY_ADD then
            -- 先del 后add 视为set
            dkop = DIRTY_SET
        else
            dkop = newOp -- DIRTY_SET
        end
    elseif dkop == DIRTY_ADD then
        if newOp == DIRTY_DEL then
            -- 先add 后del 视为key无脏数据
            Util.dirtyNodeRemoveMapKey(dirtyNode, key)
        end
        -- 其他情况都保持为add
        return
    else
        dkop = newOp -- set
    end

    -- 覆盖写不需要修改计数器
    dirtyOpMap[key] = dkop
end

local function assertInvalidValue(value)
    -- 有get_manage 方法表示是dirty wrap
    if rawget(value, '__get_manage') then
        -- 禁止dirty table重复挂载
        -- 无论是root还是普通的节点
        local mng = value:__get_manage()
        if mng then
            assert(false, "enable dirty table can not assign to another node")
        end
        if rawget(value, WRAP_REF) then
            assert(false, "dirty table forbid assign to another node")
        end
    else
        -- 禁止挂载原生类型非空table
        -- 如果支持非空类型table挂载，需要深度遍历构建，并且业务使用时很容易持有
        --if next(value) ~= nil then
            assert(false, "lua table can not assign. use Dirty.newDict/newList")
        --end
    end

    return true
end
Util.assertInvalidValue = assertInvalidValue

return Util
