local ORM = require("orm")
local tprint = require('utils').dump

local DirtyTest = {}

function DirtyTest.enable(player, pt)
    ORM.enable_dirty(player)
    player.prop.name = "PlayerA_Enable"
    player.sign = "====sign-string====="
    player.org.id = 1003
    player.org.name = "allianceA"

    assert(ORM.get_dirty_info(player.prop) == nil, "dirty node not root")

    player.bag2 = {name = "bag2", items = {}}
    player.bag2.items['coin'] = 100
    player.bag2.items['stone'] = 100
    player.bag2.items['stone'] = nil

    local ret = ORM.get_dirty_info(player)
    assert(type(ret['bag2']) == 'number', "sub node dirty")

    local update = ORM.get_mongo_dirty_data(player)
    if pt then
        tprint(update)
    end
    ORM.clear_dirty_info(player)

    -- 测试深度变更
    player.org.members = {}
    player.org.members.info = {}
    ORM.clear_dirty_info(player)

    player.org.members.cnt = 50
    player.org.members.info[1001] = 100
    player.org.members.info[1002] = 101
    player.org.members.info[1003] = 103
    player.org.members.info[1004] = 90
    update = ORM.get_mongo_dirty_data(player)
    if pt then
        tprint(update)
    end
    assert(update ~= nil, "invalid dirty update")

    player.bag2.items['coin'] = 200
    player.bag2.items['stone'] = 300
    player.bag2.items['stone'] = nil
    ret = ORM.get_dirty_info(player)
    items = ret['bag2']['items']
    assert(items['coin'] == 0 and items['stone'] == nil, "add first then del not dirty")

    player.bag2 = {name = "heroBag2"}
    player.bag2.name = "heroBag2"
    player.bag2.items = {stone = 100, coin = 100}
    ret = ORM.get_dirty_info(player)
    assert(ret['bag2'] == 0, "sub node dirty clear")

    -- 清理之后子节点变更也会触发脏数据
    ORM.clear_dirty_info(player)
    player.bag2.items.stone = 101
    player.bag2.items.coin = 101

    ret = ORM.get_dirty_info(player)
    assert(ret['bag2']['items']['stone'] == 0, "sub node dirty")
    assert(ret['bag2']['items']['coin'] == 0, "sub node dirty")

    -- 关闭脏数据管理
    ORM.disable_dirty(player)
    player.prop.name = "PlayerA_Disable"
    ret = ORM.get_dirty_info(player)
    assert(ret == nil, "not enable dirty")

    -- 重启启动脏数据管理
    ORM.enable_dirty(player)
    ret = ORM.get_dirty_info(player)
    assert(next(ret) == nil, "not enable dirty")
    ORM.clear_dirty_info(player)
    ORM.disable_dirty(player)
end

function DirtyTest.mongo_dirty(player, pt)
    ORM.enable_dirty(player)
    player.groups = {}
    player.groups[1] = {info = {[1001] = 100}, mail = {id=1001, title="array index1"}}
    player.groups[2] = {info = {[1001] = 100}, mail = {id=1002, title="array index2"}}
    local update = ORM.get_mongo_dirty_data(player)
    if pt then
        tprint(update)
    end
    ORM.clear_dirty_info(player)

    player.groups[1].info[1002] = 90
    player.groups[1].info[1001] = nil

    player.groups[1].mail.id = "new1001"
    player.groups[1].mail.title = "array index1 new"

    player.groups[2].info[1001] = 90

    update = ORM.get_mongo_dirty_data(player)
    if pt then
        tprint(update)
    end

    ORM.clear_dirty_info(player)
    -- list 添加和删除测试
    player.groups[3] = {info = {[1001] = 100}, mail = {id=1003, title="array index3"}}
    player.groups[4] = {info = {[1001] = 100}, mail = {id=1004, title="array index4"}}
    if pt then
        tprint(ORM.get_mongo_dirty_data(player))
    end

    player.groups[4] = nil
    player.groups[3] = nil
    player.groups[2] = nil
    if pt then
        tprint(ORM.get_mongo_dirty_data(player))
    end

    ORM.clear_dirty_info(player)
    ORM.disable_dirty(player)
end

return DirtyTest
