--[[
*  @Company     : JunhaiGame
*  @Author      : huangchanglong
*  @Email       : huangchanglong@ijunhai.com
*  @Date        : 2022-12-22 18:26
*  LastEditors  : huangchanglong
*  LastEditTime : 2022-12-22 18:26
*  @Description : description
--]]

local orm = require 'orm'
tprint = require('utils').dump

local type_list = (require 'typedef').parse('test.sproto', "./test")

--tprint(type_list)

print('[TC]: type init')
orm.init(type_list)

tprint(orm.g_cls_map, nil, 10)
--tprint(orm.g_cls_ref_map)

--print('[TC]: struct init')
local obj_a = orm.create('class_a')
--tprint(obj_a)

