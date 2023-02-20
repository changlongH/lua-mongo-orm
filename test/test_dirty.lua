local ORM = require("orm")
local tprint = require('utils').dump

local DirtyTest = {}

function DirtyTest.enable(player, pt)
    ORM.enable_dirty(player)
    player.prop.name = "大聪明enable"
    player.sign = "xxxxxxxxxxxx"
    player.org.id = 1003
    player.org.name = "舔狗联盟"

    assert(ORM.get_dirty_info(player.prop) == nil, "root 才有dirty info")

    player.bag2 = {name = "背包2", items = {}}
    player.bag2.items['coin'] = 100
    player.bag2.items['stone'] = 100
    player.bag2.items['stone'] = nil

    local ret = ORM.get_dirty_info(player)
    assert(type(ret['bag2']) == 'number', "子节点不产生脏数据")

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
    assert(update ~= nil, "获取脏数据异常")

    player.bag2.items['coin'] = 200
    player.bag2.items['stone'] = 300
    player.bag2.items['stone'] = nil
    ret = ORM.get_dirty_info(player)
    items = ret['bag2']['items']
    assert(items['coin'] == 0 and items['stone'] == nil, "add/del 不产生脏数据")

    player.bag2 = {name = "碎片背包"}
    player.bag2.name = "碎片背包2"
    player.bag2.items = {stone = 100, coin = 100}
    ret = ORM.get_dirty_info(player)
    assert(ret['bag2'] == 0, "子节点脏数据被清空")

    -- 清理之后子节点变更也会触发脏数据
    ORM.clear_dirty_info(player)
    player.bag2.items.stone = 101
    player.bag2.items.coin = 101

    ret = ORM.get_dirty_info(player)
    assert(ret['bag2']['items']['stone'] == 0, "子节点有数据")
    assert(ret['bag2']['items']['coin'] == 0, "子节点有数据")

    -- 关闭脏数据管理
    ORM.disable_dirty(player)
    player.prop.name = "大聪明disable"
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
    player.groups[1] = {info = {[1001] = 100}, mail = {id=1001, title="数组下标深度邮件1"}}
    player.groups[2] = {info = {[1001] = 100}, mail = {id=1002, title="数组下标深度邮件2"}}
    local update = ORM.get_mongo_dirty_data(player)
    if pt then
        tprint(update)
    end
    ORM.clear_dirty_info(player)

    player.groups[1].info[1002] = 90
    player.groups[1].info[1001] = nil

    player.groups[1].mail.id = "new1001"
    player.groups[1].mail.title = "数组下标深度邮件1new"

    player.groups[2].info[1001] = 90

    update = ORM.get_mongo_dirty_data(player)
    if pt then
        tprint(update)
    end

    ORM.clear_dirty_info(player)
    -- list 添加和删除测试
    player.groups[3] = {info = {[1001] = 100}, mail = {id=1003, title="数组下标深度邮件3"}}
    player.groups[4] = {info = {[1001] = 100}, mail = {id=1004, title="数组下标深度邮件4"}}
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
