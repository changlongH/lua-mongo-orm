## MongoBD 数据类型支持 ##
- 已经支持的数据类型
  - String − 这是存储数据最常用的数据类型。字符串在 MongoDB 必须是UTF-8有效。
  - Integer − 此类型用于存储数值。整数可以是32位 或 64位，具体取决于您的服务器。
  - Boolean −此类型用于存储布尔（true / false）值。
  - Arrays −此类型用于将数组或列表或多个值存储到一个键中。
  - Binary −此数据类型用于存储二进制数据。
  - Double − 此类型用于存储浮点值。
  - Date − 此数据类型用于以UNIX时间格式存储当前日期或时间。您可以通过创建 Date 对象并将日期，月份，年份递到其中来指定自己的日期时间。

- 待支持类型
  - Timestamp− ctimestamp（时间戳）。当文档被修改或添加时，这可以方便地进行记录。
  - Date - 需要完善类型校验

- 暂时不支持数据类型
  - Min/ Max keys −该类型用于将值与最低和最高的BSON元素进行比较。
  - Object −此数据类型用于嵌入式文档。
  - Null −此类型用于存储 Null 值。
  - Symbol−此数据类型与字符串使用相同;但是，它通常是为使用特定符号类型的语言保留的。
  - Object ID −此数据类型用于存储文档的ID。
  - Code −此数据类型用于将JavaScript代码存储到文档中。
  - Regular expression −此数据类型用于存储正则表达式。

## 文件结构描述 ##
- 数据结构描述文件`schema`
  - schema.user.*.sp 玩家数据结构文件路径
  - schema.rank.*.sp 排行榜数据结构文件路径

- 数据结构导出二进制文件`spb`
  - user.spb 玩家数据结构描述
  - rank.spb 排行榜数据结构描述


## 未校验 struct name是否存在##
