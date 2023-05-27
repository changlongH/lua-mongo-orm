# lua_mongo_orm #

> lua table ORM 可生成mongo语句（非必须）

> schema 参考CloudWu Sproto(https://github.com/cloudwu/sproto)

> lua 通过代理table __newindex 触发add/set/del监控和值类型检查

> MongoBD 数据类型支持(String/Integer/Boolean/Arrays/Binary/Double/Date)

## install ##
```
make -C lpeg-1.0.2/ linux (macosx) # lpeg.so
lua example.lua
```

## Schema 文本处理 API ##

- `Typedef.parse_text(text)` 通过schema text文本导出type list结构
- `Typedef.parse_file(filename, dir)` 通过schema 文件导出type list 支持`#include`

## ORM API ##
- `ORM.init(type_list)` 初始化全局schema，不支持初始化多次
- `ORM.create(typename, data)` schema中定义的root type name和初始化原始data
- `ORM.enable_dirty(player)` 启动player的脏数据管理模式，不启动则也会校验合法性
- `ORM.get_dirty_info(player)` 获取player脏数据，flag标记SET/ADD/DEL(0/1/2) 数据结构为`{key1=1, key2=2, key3={a=0, b=1, c=0}}`
- `ORM.get_mongo_dirty_data(player)` 获取player脏数据mongo 语句`{$set={k.a.c=1}, $unset={k2=1}, cnt=2}`
- `ORM.clear_dirty_info(player)` 每次完成存盘后清理脏标记
- `ORM.disable_dirty(player)` 关闭脏数据管理模式
- `ORM.clone_mongodata` 获取player原始结构数据

## 类型检测和值校验 ##
ORM 对值类型检测和合法性校验，异常则抛出error。
1. integer做math.tointeger值转化。
2. double做合法性校验`inf/nan`检测。
3. list插入必须连续，每次插入数据都会对数组连续性进行校验。
4. 不存在字段赋值,视为不合法。
5. 避免循环引用问题，对于引用table赋值给另外一个字段时需要使用`ORM.clone_mongodata(obj)`。同时规避dict整数key问题。
6. value如果是table赋值给key时，以clone方式实现。注意赋值后重新get key的值。
```
local prop = {id = 1, name = "anni"}
player.prop = prop
# 此时再修改原prop 不产生脏数据
prop.name = "invalid"
# 重新获取属性修改才生效
prop = player.prop
prop.name = "newAnni"
```

## schema ##

- 导出基本字段
  - `type`必定存在值为struct/dict/list/integer/引用类型 等。
  - `name`全局field必定有值，私有field则不存在。
  - `attr` 只有struct使用
  - `item` 只有list使用
  - `key/value` 只有dict使用

- `struct`导出结构`{type="struct", name="Player", attr={key1={}, key2={}}}`
- `list`导出结构`{type="list", name="x", item={}}`
- `dict`导出结构`{type="dict", name="x", key={}, value={}}`
- 引用类型type值为引用的结构体`{type="Item"}`
- 原子类型只有type字段

## mongo ##
> 生成mongo语句时需要对key进行深度遍历（不断查询parent直到root）。拼接生成存盘key例如`{a.b.c.e=1}`。

> lua 字符串拼接消耗比较大，生成大量临时字符串。需要业务优化，并加速GC

- table中整数key处理`{1001 = 1, 1002 = 1}`转为`{i@1001 = 1, i@1002 = 1}`存盘，create时反解析。
- date为bson.date 不做严格校验

## lua dirty manager 设计 ##

- dirty数据结构
```
__dirty = {
    root = root_obj,
    parent = parent_obj,
    self = obj,
    skey = skey,
    dirty_node = {},

    # 根结点才有
    dirty_root = {
        node_cnt = 0,
        # 不需要关注顺序,生成语句后merge
        node_map = {
            [dirty_node] = true,
        },
    }
}
dirty_node = {
    mng_ptr = __dirty, # 指向__dirty本身方便迭代node_map时获取dirty_node.mng_ptr.self
    op_map = {key = ADD/SET/DEL},
    op_cnt = 0, # 脏数据条数
}
```

- dirty node
1. 非atom类型必须重写`pairs/__index/__newindex`，list额外重写`__ipairs/__len/__concat`。
2. 每个脏结点都存在四个属性`{__data = {}, __ref = false, __cls = {}, __dirty={}}`, `__ref`解决循环引用问题。
3. dirty node 值被覆盖或者其父类被覆盖时，old_table:__disable_dirty() 会通过尾递归方式释放结点并且清理dirty_root.node_map记录数据

- dirty root
> get dirty info 时通过遍历node_map生成脏数据信息

## example ##

参考`example.lua` 用例
