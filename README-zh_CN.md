#  pretty-lua: Lua的美化字符串库

[English](./README.md) [简体中文](./README-zh_CN.md)

- 格式化Lua的数据
- 自动换行

## 安装

只需要拷贝pretty.lua到您的项目中。

## API浏览

```lua
---将value转化为美化的字符串。
---@param value any
---@return string
function write(value) end

---设置换行限制。
---注意：这个限制只能控制table的换行，无法绝对控制每行的最大长度
---@param limit integer
---@return nil
function setLineBreakLimit(limit) end

---设置缩进宽度。
---@param width integer
---@return nil
function setIndentWidth(width) end

---设置数组中允许的最大连续nil数量，超出部分视为表部分。
---@param num integer
local function setMaximumNilNumberAllowed(num) end

---美化输出。
---@param ... any
---@return nil
local function prettyPrint(...) end
```

## 样例

基本输出：

```lua
print(write(nil))
-- output: nil

print(write(true))
-- output: true

print(write(1919))
-- output: 1919

print(write(1145.14))
-- output: 1145.14

print(write("12"))
-- output: "12"

print(write("ABC\x01"))
-- output: "ABC\x01"

print(write(function() end))
-- example output: <function 000001F6B5888A20>
```

数组输出：

```lua
print(write({ 1, 2, 3 }))
--[[output:
{ 1, 2, 3 }
]]

print(write({ 1000, 1001, 1002, 1003, 1004, 1005, 1006, 1007, 1008, 1009, 1010, 1011 }))
--[[output:
{
  1000, 1001, 1002, 1003, 1004, 1005, 1006, 1007, 1008, 1009,
  1010
}
]]

do
    local s = {}
    for i = 1, 64 do table.insert(s, i) end
    print(write(s))
end
--[[output:
{
  1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18,
  19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33,
  34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48,
  49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63,
  64
}
]]

setMaximumNilNumberAllowed(3);
print(write({ 1, 2, nil, 3, nil, nil, 4, nil, nil, nil, 5, nil, nil, nil, nil, 6 }))
--[[output:
{ 1, 2, nil, 3, nil, nil, 4, nil, nil, nil, 5, [16] = 6 }
]]
```

表输出：

```lua
print(write({
    a = 1,
    b = true,
    c = function() end,
    d = { 1, 2 },
    e = { 1000, 1001, 1002, 1003, 1004, 1005, 1006, 1007, 1008, 1009, 1010, 1011 }
}))
--[[output:
{
  ["a"] = 1, ["b"] = true, ["c"] = <function: 000001E2AF53CAF0>,
  ["d"] = { 1, 2 }, ["e"] = {
    1000, 1001, 1002, 1003, 1004, 1005, 1006, 1007, 1008, 1009,
    1010, 1011
  }
}
]]

do
    local s = { 12, 13 }
    local t = { s }
    s[3] = t
    print(write(t))
end
--[[output:
{ { 12, 13, <cycle table: 000001FBF3F9F780> } }
]]

do
    local s = { {} }
    for i = 2, 64 do
        s[i] = { s[i - 1] }
    end
    print(write(s[64]))
end
--[[error output:
D:\Programs\lua54\lua.exe: .\pretty.lua:219: leading space is too long
stack traceback:
        [C]: in function 'error'
        .\pretty.lua:219: in upvalue 'subWrite'
        .\pretty.lua:270: in upvalue 'subWrite'
        .\pretty.lua:270: in upvalue 'subWrite'
        .\pretty.lua:270: in upvalue 'subWrite'
        .\pretty.lua:270: in upvalue 'subWrite'
        .\pretty.lua:270: in upvalue 'subWrite'
        .\pretty.lua:270: in upvalue 'subWrite'
        .\pretty.lua:270: in upvalue 'subWrite'
        .\pretty.lua:270: in upvalue 'subWrite'
        ...     (skipping 14 levels)
        .\pretty.lua:270: in upvalue 'subWrite'
        .\pretty.lua:270: in upvalue 'subWrite'
        .\pretty.lua:270: in upvalue 'subWrite'
        .\pretty.lua:270: in upvalue 'subWrite'
        .\pretty.lua:270: in upvalue 'subWrite'
        .\pretty.lua:270: in upvalue 'subWrite'
        .\pretty.lua:270: in upvalue 'subWrite'
        .\pretty.lua:270: in local 'subWrite'
        .\pretty.lua:303: in function 'pretty.write'
        example.lua:47: in main chunk
        [C]: in ?
]]
```

