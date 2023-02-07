--[[
*  @Company     : JunhaiGame
*  @Author      : huangchanglong
*  @Email       : huangchanglong@ijunhai.com
*  @Date        : 2023-02-01 14:08
*  LastEditors  : huangchanglong
*  LastEditTime : 2023-02-01 14:08
*  @Description : lua脏数据管理
--]]

package.path = package.path ..";" .. "../?.lua"
local Dirty = require("dirty")
local Utils = require("utils")
dump = Utils.dump

local M = {}

function M.testDict()
    local m = Dirty.newDict()
    m["name"] = "pony"
    local m2 = Dirty.newDict()
    Dirty.enableDirty(m)

    m['items'] = m2
    m['items'] = 100
    m['items2'] = m2

    m2['super'] = false
    m["name"] = "pony"
    m['items'] = 0

    dump(Dirty.getDirtyInfo(m))
    Dirty.clearDirty(m)
    --Dirty.disableDirty(m)
    m['items2'] = m2
    m['items'] = 0

    m["id"] = 123
    m['sex'] = "男"
    m2['gold'] = 100
    m2['stone'] = 200

    dump(Dirty.getDirtyInfo(m))
    --Dirty.clearDirty(m)

    --dump(m)

    Dirty.enableDirty(m)
    print("---------modify dict-------")
    m['sex'] = '女'
    m['id'] = nil
    m2['coin'] = 100
    m['items'] = false
    dump(Dirty.getDirtyInfo(m))
end

function M.testList()
    local list = Dirty.newList()
    list[1] = 1
    dump(list)
    list[2] = 2

    Dirty.enableDirty(list)
    list[1] = "id"
    list[3] = "name"
    --list[2] = nil
    --list[5] = "lv"
    dump(Dirty.getDirtyInfo(list))
    Dirty.clearDirty(list)

    Dirty.enableDirty(list)
    list[1] = "coin"
    dump(Dirty.getDirtyInfo(list))
end

M.testDict()
M.testList()

return M
