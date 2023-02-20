local lpeg = require "lpeg"
local P = lpeg.P
local R = lpeg.R
local S = lpeg.S
local C = lpeg.C
local Ct = lpeg.Ct
local V = lpeg.V
local Cc = lpeg.Cc
local Cg = lpeg.Cg
local Carg = lpeg.Carg

local line_infos = {}
local function count_lines(_,pos, parser_state)
    if parser_state.pos < pos then
        parser_state.line = parser_state.line + 1
        parser_state.pos = pos
    end
    return pos
end


local color = {
    red = 31,
    green = 32,
    blue = 36,
    yellow = 33,
    other = 37
}
local function highlight(s, c)
    c = c or "red"
    return string.format("\x1b[1;%dm%s\x1b[0m", color[c], tostring(s))
end

local function highlight_type(s)
    return highlight(s, "green")
end

local function highlight_tag(s)
    return highlight(s, "yellow")
end

local exception = lpeg.Cmt(
    Carg(1),
    function(_, pos, parser_state)
        local line_info = line_infos[parser_state.line]
        local s = highlight(string.format("syntax error at %s:%d line", line_info.file, line_info.line))
        error(s)
        return pos
    end
)

local eof = P(-1)
local newline = lpeg.Cmt((P"\n" + "\r\n") * Carg(1) ,count_lines)
local line_comment = "#" * (1 - newline) ^0 * (newline + eof)
local blank = S" \t" + newline + line_comment
local blank0 = blank ^ 0
local blanks = blank ^ 1
local alpha = R"az" + R"AZ" + "_"
local alnum = alpha + R"09"
local word = alpha * alnum ^ 0
local name = C(word)
local typename = C(word * ("." * word) ^ 0)
--local tag = R"09" ^ 1 / tonumber
--local mainkey = "(" * blank0 * name * blank0 * ")"
--local decimal = "(" * blank0 * C(tag) * blank0 * ")"

local function metapatt(_)
    local patt = lpeg.Cmt(
        Carg(1),
        function(_, pos, parser_state)
            local info = line_infos[parser_state.line]
            setmetatable(info, {__tostring = function(v)
                return highlight(string.format("at %s:%d line", v.file, v.line))
            end})
            return pos, info
        end
    )
    return patt
end

local function multipat(pat)
    return Ct(blank0 * (pat * blanks) ^ 0 * pat^0 * blank0)
end

local function namedpat(patname, pat)
    local pattype = Cg(Cc(patname), "type")
    local meta = Cg(metapatt(patname), "meta")
    return Ct(pattype * meta * Cg(pat))
end

local typedef = P {
    "ALL",

    FIELD = namedpat(
        "field",
        (name * blanks * ":" * blank0 *
             (
                 namedpat(
                     "ref",
                     typename
                 ) +

                 namedpat(
                     "list",
                     '*' * blank0 * typename
                 ) +

                 namedpat(
                     "map",
                      P"<" * blank0 * typename * blank0 * "," * blank0 * typename * blank0 * P">"
                 )
             )
        )
        +
        (P"." * name * blanks *
            namedpat(
                "struct",
                P"{" * multipat(V"FIELD") * P"}"
            )
        )
    ),

    STRUCT = namedpat(
        "struct",
        blank0 * P"." * name * blank0 * P"{" * multipat(V"FIELD") * P"}"
    ),

    LIST = namedpat(
        "list",
        blank0 * name * blank0 * ":" * blank0 * "*" * blank0 * typename
    ),

    MAP = namedpat(
        "map",
        blank0 * name * blank0 * ":" *
            blank0 * P"<" * blank0 * typename * blank0 * "," * blank0 * typename * blank0 * P">"
    ),

    ALL = multipat(V"STRUCT" + V"LIST" + V"MAP"),
}

local schema = blank0 * typedef * blank0

local function preprocess(filename, dir)
    local text = {}
    local path = dir .. "/" .. filename
    line_infos = {}
    local idx = 0
    for line in io.lines(path) do
        idx = idx + 1
        local include = string.match(line, "^%s*#include%s+([^%s]+)%s*")
        if not include then
            local _idx = #text + 1
            text[_idx] = line
            line_infos[_idx] = {line = idx, file=path}
        else
            local _idx = 0
            include = dir .. "/" .. include
            for _line in io.lines(include) do
                _idx = _idx + 1
                local len = #text+1
                text[len] = _line
                line_infos[len] = {line = _idx, file=include}
            end
        end
    end
    return table.concat(text, "\n")
end

local KEYWORD_MAP = {
    -- 类型关键词
    boolean = true,
    integer = true,
    string = true,
    struct = true,
    list = true,
    map = true,
    double = true,
    binary = true,
    date = true,

    -- 业务属性关键词禁止定义为key
    __cls = true,
}

local function has_type(type, extra_types)
    if not type then
        return false
    end
    if KEYWORD_MAP[type] then
        return true
    end
    return extra_types[type] and true or false
end

local convert = {}
function convert.struct(obj, set)
    local type_name = obj[1]
    if KEYWORD_MAP[type_name] then
        error(string.format("type_name<%s> is keyword", highlight_type(type_name)))
    end

    local field_map = {}
    for _, f in ipairs(obj[2]) do
        local field_name = f[1]
        local field_data = f[2]
        if(type(field_data) ~= 'table') then
            field_data = f[3]
        end

        if field_data == '*' then
            field_data = f[4]
        end
        local field_data_type = field_data.type

        if KEYWORD_MAP[field_name] then
            error(string.format("struct %s field %s is keyword", highlight_type(type_name), highlight_tag(field_name)))
        end

        if field_map[field_name] then
            error(string.format("struct %s field %s is redefined", highlight_type(type_name), highlight_tag(field_name)))
        end

        local field = {}
        if field_data_type == 'ref' then
            if not has_type(field_data[1], set) then
                error(string.format("Undefined type <%s> %s", highlight_type(field_data[1]), tostring(obj.meta)))
            end
            field.type = field_data[1]
        elseif field_data_type == 'map' then
            field.type = 'map'

            if not has_type(field_data[1], set) then
                error(string.format("Undefined key type <%s> in %s", highlight_type(field_data[1]), tostring(obj.meta)))
            end
            if not has_type(field_data[2], set) then
                error(string.format("Undefined value type <%s> in %s", highlight_type(field_data[2]), tostring(obj.meta)))
            end

            field.key = {type = field_data[1]}
            field.value = {type = field_data[2]}

        elseif field_data_type == 'list' then
            field.type = 'list'
            if not has_type(field_data[1], set) then
                error(string.format("Undefined type <%s> in %s", highlight_type(field_data[1]), tostring(obj.meta)))
            end
            field.item = {type = field_data[1]}

        elseif field_data_type == 'struct' then
            local sub_struct_obj = {field_name, field_data[1], type = 'struct', meta = field_data.meta}
            for k, v in pairs(convert.struct(sub_struct_obj, set)) do
                field[k] = v
            end
            field.name = nil
        else
            error(string.format("struct %s field %s unknown type", highlight_type(type_name), highlight_tag(field_name)))
        end

        field_map[field_name] = field
    end

    return {
        type = 'struct',
        name = type_name,
        attrs = field_map,
    }
end

function convert.list(obj, set)
    local type_name = obj[1]
    if KEYWORD_MAP[type_name] then
        error(string.format("type_name<%s> is keyword", highlight_type(type_name)))
    end

    if not has_type(obj[4], set) then
        error(string.format("Undefined type <%s> in %s", highlight_type(obj[4]), tostring(obj.meta)))
    end

    return {
        type = 'list',
        name = type_name,
        item = {type = obj[4]},
    }
end

function convert.map(obj, set)
    local type_name = obj[1]
    if KEYWORD_MAP[type_name] then
        error(string.format("type_name<%s> is keyword", highlight_type(type_name)))
    end

    if not has_type(obj[4], set) then
        error(string.format("Undefined key type <%s> in %s", highlight_type(obj[5]), tostring(obj.meta)))
    end
    if not has_type(obj[5], set) then
        error(string.format("Undefined value type <%s> in %s", highlight_type(obj[4]), tostring(obj.meta)))
    end

    return {
        type = 'map',
        name = type_name,
        key = {type = obj[4]},
        value = {type = obj[5]},
    }
end

--local tprint = require('utils').dump
local function parse(pattern, filename, dir)
    assert(type(filename) == "string")
    local text = preprocess(filename, dir)
    local state = {file = filename, pos = 0, line = 1}
    local r = lpeg.match(pattern * -1 + exception, text, 1, state)
    local ret = {}
    -- optimize 可以考虑支持namespace 同一个namespac下禁止同名
    local set = {}
    for _, item in ipairs(r) do
        local type_name = item[1]
        if set[type_name] ~= nil then
            local meta_info = tostring(item.meta)
            assert(false, string.format("redefine <%s> %s", highlight_type(type_name), highlight(meta_info)))
        end
        table.insert(ret, convert[item.type](item, set))
        set[type_name] = true
    end

    return ret
end


local M = {}
function M.parse(...)
    return parse(schema, ...)
end

return M
