--[[
*  @Company     : JunhaiGame
*  @Author      : huangchanglong
*  @Email       : huangchanglong@ijunhai.com
*  @Date        : 2023-02-04 19:11
*  LastEditors  : huangchanglong
*  LastEditTime : 2023-02-04 19:11
*  @Description : description
--]]

local Consts = {
    -- wrap 属性
    WRAP_DIRTY_MNG = '__dirty_mng',
    WRAP_REF = '__ref',
    WRAP_RAW_DICT = '__dict',
    WRAP_RAW_LIST = '__list',

    -- DirtyManage 属性
    MNG_ROOT = 'root',
    MNG_PARENT = 'parent',
    MNG_SELF = 'self',
    MNG_SELF_KEY = 'skey', -- 当前字段key name
    MNG_DIRTY_NODE = 'dirty_node', -- 脏数据节点结构
    MNG_DIRTY_ROOT = 'dirty_root', -- 只有root才有 root数据结构

    -- DirtyRoot 属性
    RTNODE_DIRTY_NODE_CNT = 'cnt', -- 脏节点数量
    RTNODE_DIRTY_NODE_MAP = 'map', -- 脏节点管理map

    -- DirtyNode 属性
    NODE_MNG_PTR = 'mng', -- 指向mng的地址
    NODE_DIRTY_OP_DICT = 'kop_map', -- {name:SET,lv:DEL}
    NODE_DIRTY_OP_CNT = 'kop_cnt',


    -- 脏标记常量
    DIRTY_SET = 0,
    DIRTY_ADD = 1,
    DIRTY_DEL = 2,
}

return Consts
