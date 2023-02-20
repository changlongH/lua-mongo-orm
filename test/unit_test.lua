local ORM = require 'orm'
local typedef = require 'typedef'

local tprint = require('utils').dump

local type_list = typedef.parse('player.sproto', "./sproto")

--tprint(type_list)

--print('[TC]: type init')
ORM.init(type_list)

--tprint(ORM.g_cls_map, nil, 10)
--tprint(ORM.g_cls_ref_map)

--prop.c = {'name'}
local player = ORM.create('Player')

local function genHero(id, name, pos)
    return { id = id, name = name, pos = pos}
end
local function genMail(id, title)
    return {id = id, title = title}
end

-- 引用测试
local function testDictRef()
    local ashe = genHero(1001, "艾希", {x=1, y=2})
    local annie = genHero(1002, "安妮", {x=1, y=2})
    local garen = genHero(1003, "盖伦", {x=1, y=3})

    -- 赋值方式为copy 不是直接引用
    local heroes = {}
    player.heroes = heroes
    heroes.ashe = ashe
    assert(player.heroes.ashe == nil, "clone赋值不直接持有heroes对象")

    heroes = player.heroes -- 赋值后重新需要重新引用

    heroes.ashe = ashe
    heroes.annie = ashe
    assert(heroes.ashe ~= heroes.annie, "ashe 是原生lua表，赋值时会被clone")

    assert(rawget(heroes.ashe, '__ref'), "heroes.ashe 被标记为引用")
    local ok = pcall(function()
        heroes.garen = heroes.ashe
    end)
    assert(ok == false, "赋值失败 因为heroes.ashe 是dirty对象")

    -- 赋值被回收后清空引用
    heroes.annie = annie
    annie = heroes.annie
    assert(rawget(annie, '__ref'), "annie 是dirty对象被标记为引用状态")
    heroes.annie = garen
    assert(rawget(annie, '__ref') == nil, "annie 被释放收，引用标记解除")

    -- 类型对象重新赋值是直接引用 不需要clone
    heroes.annie = annie -- 最后可以重新挂载回来
    annie.name = "安妮2"
    assert(heroes.annie == annie and heroes.annie.name == "安妮2", "dirty 类型对象重新赋值是直接引用")

    ok = pcall(function()
        heroes.garen = annie
    end)
    assert(ok == false, "赋值失败 因为annie 是orm创建的dirty对象")

    -- 重复赋值自身多次不会生成脏数据
    heroes.garen = garen
    heroes.garen = garen
end

local function testStructRef()
    --print('[TC]: struct init')
    local prop = ORM.create('Prop')
    local frames = {"fs101","fs121"}

    -- 基本类型测试
    prop.uid = 1001
    prop.name = "大聪明"
    prop.exp = 0.01
    prop.items = {
        coin = 100,
        stone = 100
    }
    prop.frames = frames
    prop.create_time = 12121
    player.sign = "xfasd"

    -- 全局结构体赋值
    player.prop = prop

    -- 私有结构体赋值
    player.org = {}
    player.org.id = 1001
    player.org.name = "海王军团"
    player.org.members = {cnt = 0, info = {}}

    -- 测试引用
    prop.uid = 1002
    assert(player.prop.uid == 1002, "prop是orm create对象直接引用")

    frames[1] = "fs0001"
    assert(player.prop.frames[1] == "fs101", "frames是lua原生表clone赋值，不直接持有")

    -- 测试背包引用
    local bag = {name = "背包1", items = {}}
    player.bag1 = bag
    player.bag2 = bag
    assert(player.bag1 ~= player.bag2, "bag 是lua原生表，clone方式挂载")
    local ok = pcall(function()
        player.bag2 = player.bag1
    end)
    assert(ok == false, "player持有的对象是orm创建的引用对象禁止重复赋值")
    local bag2 = player.bag2
    assert(rawget(bag2, '__ref'), "此时bag2对象有引用标记")
    player.bag2 = nil
    assert(rawget(bag2, '__ref') == nil, "bag2释放后引用标记清除")
end

local function testListRef()
    local rawmail = genMail(1001, "欢迎邮件")
    player.mails = {rawmail, rawmail, rawmail}
    assert(player.mails[1] ~= rawmail and player.mails[1] ~= player.mails[2], "mail是lua原生表 clone引用")

    local mail = ORM.create("Mail", genMail(1002, "测试邮件"))
    local ok = pcall(function()
        player.mails = {mail, mail, mail}
    end)
    assert(ok == true, "mail虽然orm创建。但是list初始化时迭代clone(item)构建")

    ok = pcall(function()
        player.mails[4] = mail
        player.mails[5] = mail
    end)
    assert(ok == false, "此时赋值是直接引用")

    ok = pcall(function()
        player.mails[2] = nil
    end)
    assert(ok == false, "禁止稀疏数组")

    ok = pcall(function()
        player.mails[7] = genMail(1001, "稀疏邮件")
    end)
    assert(ok == false, "禁止稀疏数组")

    -- 移除最后一个释放引用
    local size = #player.mails
    local tailmail = player.mails[size]
    assert(rawget(tailmail, '__ref'), "此时有引用标记")
    player.mails[#player.mails] = nil
    assert(rawget(tailmail, '__ref') == nil, "此时解除引用标记")

    local cnt = 0
    for _, mail in ipairs(player.mails) do
        --print(i, mail.id)
        cnt = cnt + 1
    end
    assert(cnt == #player.mails, "ipairs和len")

    player.mails = {}
end

-- 字典测试
testDictRef()

-- 结构体测试
testStructRef()

-- 数组测试
testListRef()

-- 脏数据测试
local DirtyTest = require("test.test_dirty")
DirtyTest.enable(player, false)

DirtyTest.mongo_dirty(player, false)

-- 序列化测试
local mongodata = ORM.clone_mongodata(player)
--[[
local bson = require("bson")
bson.encode(mongodata)
--]]

player = ORM.create("Player", mongodata)


-- CPU 性能测试
local heroes = {}
local mails = {}
for i = 1, 1000 do
    table.insert(heroes, genHero(i, "hero_" .. i, {x=i, y=i}))
    table.insert(mails, genMail(i, "测试邮件_" ..  i))
end

-- 5k * 100 = 50w
local bt = os.clock()
ORM.enable_dirty(player)
local dirty_cnt = 0
for i = 0, 500000 do
    local index = math.random(1, 1000)
    if math.random(2) > 1 then
        player.heroes[i] = heroes[index]
        player.org.members.info[i] = 1
        player.org.members.cnt = i
    else
        if not player.groups then
            player.groups = {}
        end
        table.insert(player.groups, {info = {[i] = 100}, mail = mails[index]})
    end
    player.prop.name = i
    if i % 200 == 0 then
        local ret = ORM.get_mongo_dirty_data(player)
        dirty_cnt = dirty_cnt + ret.cnt
        ORM.clear_dirty_info(player)
    end
end

ORM.get_mongo_dirty_data(player)
ORM.clear_dirty_info(player)
local et = os.clock()
print(string.format("test CPU dirty cnt:%s time:%s", dirty_cnt, et - bt))

--tprint(player)
