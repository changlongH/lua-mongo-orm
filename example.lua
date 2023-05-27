local Utils = require("utils")
local Typedef = require("typedef")

local Schema = [[
.Prop {
    id : integer
    name : string
    exp : double
    birthday : date
    newbie : boolean
}

.Bag {
    name : string
    items : <integer, integer> # 道具ID和数量字典
}

.Player {
    prop : Prop
    sign : binary
    storage : *Bag # 背包列表
    # 私有field
    .device {
        anme : string
        net : string
        # other
    }
}
]]

-- 导出schema
local typeList = Typedef.parse_text(Schema)
Utils.dump(typeList)

local ORM = require("orm")
-- 初始化ORM 全局
ORM.init(typeList)

local rawData = {
    prop = {id = 1001, name = "Anni", exp = 100.10, newbie = false},
    sign = nil,
    storage = {
        {name = "bag1", items = {[1001] = 10}},
        {name = "bag2", items = {[1002] = 30}}
    },
    device = {},
}

-- 创建数据管理对象
local player = ORM.create("Player", rawData)

-- 启动脏数据管理
ORM.enable_dirty(player)
player.prop.id = 123
player.prop.exp = 11.221
player.storage[1] = ORM.clone_mongodata(player.storage[2])
player.storage[2].name = "bag2new" -- 非循环引用
Utils.dump(player)

-- 获取脏数据结构
local dirtyInfo = ORM.get_dirty_info(player)
Utils.dump(dirtyInfo)

-- 序列化脏数据成mongo语句
local dirtyMongo = ORM.get_mongo_dirty_data(player)
Utils.dump(dirtyMongo)

-- 完成一次存盘后清理dirty标记
ORM.clear_dirty_info(player)

-- 关闭存盘数据管理
ORM.disable_dirty(player)

-- 获取原始数据
local data = ORM.clone_mongodata(player)
Utils.dump(data)
