---Check if the value is an integer.
---For Lua versions before 5.3, an integer is a number without a fractional part;
---for Lua 5.3 and later, use the built-in function `math.type` to determine.
---@type fun(value:number):boolean
local isInteger
do
    local majorVersion, minorVersion = string.match(_VERSION, "(%d+).(%d+)")
    if majorVersion == nil or minorVersion == nil then error("unknown lua version") end
    if majorVersion ~= "5" then error("unsupported lua version") end
    if tonumber(minorVersion) < 3 then
        isInteger = function(value) return math.floor(value) == value end
    else
        isInteger = function(value) return math.type(value) == "integer" end
    end
end

---Convert a number to a string.
---@type fun(value:number):string
local function num2string(value)
    if value ~= value then
        return "NaN"
    elseif value == math.huge then
        return "Inf"
    elseif value == -math.huge then
        return "-Inf"
    elseif isInteger(value) then
        return ("%d"):format(value)
    else
        return ("%.14g"):format(value)
    end
end

---The largest integer that can be represented without loss of precision.
---@type integer
local maxSafeInteger = (function()
    if math.maxinteger then return math.maxinteger end -- Lua 5.3 and above
    local val ---@type number

    if 1 / 2 == 0 then -- no floating point number
        val = math.huge
        if val - 1 == val then
            error(
                "It seems there's no floating-point number, but `math.huge` is not likely to be a valid integer")
        end
        return val
    end

    local function testFloat(val)
        if val - 2 == val or val - 1 == val then return false end
        if val - 2 == val - 1 then return false end
        return true
    end

    val = 2.0 ^ 113
    if testFloat(val) then return val end -- IEEE-754 binary128
    val = 2.0 ^ 64
    if testFloat(val) then return val end -- Intel 80-bit extended precision
    val = 2.0 ^ 53
    if testFloat(val) then return val end -- IEEE-754 binary64
    val = 2.0 ^ 24
    if testFloat(val) then return val end -- IEEE-754 binary32
    val = 2.0 ^ 11
    if testFloat(val) then return val end -- IEEE-754 binary16
    val = 2.0 ^ 8
    if testFloat(val) then return val end -- bfloat16
end)()

---@type table<integer, string>
local stringQuoteTable = {}
do
    stringQuoteTable[0] = "\\0"
    stringQuoteTable[39] = "\\\'"
    stringQuoteTable[34] = "\\\""
    stringQuoteTable[7] = "\\a"
    stringQuoteTable[8] = "\\b"
    stringQuoteTable[12] = "\\f"
    stringQuoteTable[10] = "\\n"
    stringQuoteTable[13] = "\\r"
    stringQuoteTable[9] = "\\t"
    stringQuoteTable[11] = "\\v"
    stringQuoteTable[92] = "\\\\"
    for i = 32, 126 do
        if stringQuoteTable[i] == nil then
            stringQuoteTable[i] = string.char(i)
        end
    end
    for i = 1, 255 do
        if stringQuoteTable[i] == nil then
            stringQuoteTable[i] = string.format("\\x%02x", i)
        end
    end
end

---Escape string, replacing special characters in the string with escape sequences.
---@param str string The string to be escaped
---@param quote string|nil The quote string; no quotes will be added if `quote` == `nil`
---@return string
local function escapeString(str, quote)
    local pattern = "[\x7F-\xFF\1-\x1F\\\"\'=\20]"
    if string.find(str, pattern) == nil then
        return str
    end

    local pos = 0
    local retTable = {}
    if quote ~= nil then table.insert(retTable, quote) end
    repeat
        local nextPos = string.find(str, pattern, pos)
        if nextPos then
            table.insert(retTable, string.sub(str, pos, nextPos - 1))
            table.insert(retTable, stringQuoteTable[string.byte(str, nextPos)])
            pos = nextPos + 1
            if pos > #str then
                break
            end
        else
            table.insert(retTable, string.sub(str, pos))
            break
        end
    until false
    if quote ~= nil then table.insert(retTable, quote) end
    return table.concat(retTable)
end

local lineBreakLimit = 64 ---@type integer
local indentString = "  " ---@type string
local indentWidth = 2 ---@type integer
local maximumNilNumberAllowed = 0 ---@type integer

---@param value any
---@return string
local function writeDirect(value)
    local typ = type(value)
    if typ == "nil" then
        return "nil"
    elseif typ == "number" then
        return num2string(value)
    elseif typ == "string" then
        return "\"" .. escapeString(value) .. "\""
    elseif typ == "boolean" then
        return (value and "true") or "false"
    else
        return "<" .. tostring(value) .. ">"
    end
end

---@param tab any[]
---@return integer
local function getArraySize(tab)
    local integerLimit = 1
    local nilNumber = 0
    while integerLimit < maxSafeInteger do
        if tab[integerLimit] == nil then
            if nilNumber >= maximumNilNumberAllowed then
                integerLimit = integerLimit - nilNumber
                break
            end
            nilNumber = nilNumber + 1
        else
            nilNumber = 0
        end
        integerLimit = integerLimit + 1
    end
    return integerLimit - 1
end

local typeOrder = {
    ["number"] = 0,
    ["string"] = 1,
    ["boolean"] = 2,
    ["table"] = 3,
    ["function"] = 4,
    ["userdata"] = 5,
    ["thread"] = 6,
}

---@param item string[]
---@param leadingSpaceLength integer
---@param trimSpaceLength integer
---@return string|nil
local function maybeShortTable(item, leadingSpaceLength, trimSpaceLength)
    local arr = {} ---@type string[]
    local size = 4 + leadingSpaceLength ---@type integer
    for _, str in ipairs(item) do
        local s = string.sub(str, trimSpaceLength + 1)
        size = size + #s + 1
        table.insert(arr, s)
        if size >= lineBreakLimit then return nil end
    end
    if arr[1] == nil then
        return "{ }"
    end
    return "{ " .. table.concat(arr, " ") .. " }"
end

---@param value any
---@return string|string[]
local function writeInternal(value)
    if type(value) ~= "table" then
        return writeDirect(value)
    end

    local tableVisit = {} ---@type table<table, boolean>
    local integerSet = {} ---@type table<integer, boolean>

    ---@param leadingSpace string
    ---@return string|string[]
    local function subWrite(tab, leadingSpace)
        local typ = type(tab)
        if typ ~= "table" then
            return writeDirect(tab)
        end
        if tableVisit[tab] then
            return "<cycle " .. tostring(tab) .. ">"
        end
        tableVisit[tab] = true
        if #leadingSpace >= lineBreakLimit then
            error("leading space is too long")
        end

        local integerSize = getArraySize(tab)
        local newLeadingSpace = leadingSpace .. indentString

        local ret = {} ---@type string[]
        local line = { leadingSpace } ---@type string[]
        local line_size = #leadingSpace ---@type integer

        local function resetLine() line, line_size = { leadingSpace }, #leadingSpace end
        local function nextLine()
            line[#line] = ","
            table.insert(ret, table.concat(line))
            line, line_size = { leadingSpace }, #leadingSpace
        end

        ---@param str string
        ---@return nil
        local function pushString(str)
            if #str >= lineBreakLimit - line_size then nextLine() end
            table.insert(line, str)
            table.insert(line, ", ")
            line_size = line_size + #str + #indentString
        end

        ---@param item string|string[]
        ---@param preffix string
        ---@return nil
        local function push(item, preffix)
            if type(item) == "string" then
                pushString(preffix .. item)
                return
            end
            do
                local s = maybeShortTable(item, #leadingSpace + #preffix, #newLeadingSpace)
                if s ~= nil then
                    pushString(preffix .. s)
                    return
                end
            end
            table.insert(line, preffix)
            table.insert(line, "{")
            table.insert(ret, table.concat(line))
            resetLine()
            table.move(item, 1, #item, #ret + 1, ret)
            pushString("}")
        end

        for i = 1, integerSize do
            integerSet[i] = true
            push(subWrite(tab[i], newLeadingSpace), "")
        end

        ---@type any[]
        local keyArray = {}
        for key, _ in pairs(tab) do
            if not integerSet[key] then
                table.insert(keyArray, key)
            end
        end
        table.sort(keyArray, function(lhs, rhs)
            local lhsType, rhsType = type(lhs), type(rhs)
            if lhsType == rhsType then
                return lhs < rhs
            else
                return typeOrder[lhsType] < typeOrder[rhsType]
            end
        end)

        for _, key in pairs(keyArray) do
            push(subWrite(tab[key], newLeadingSpace), string.format("[%s] = ", writeDirect(key)))
        end

        if line[2] ~= nil then
            line[#line] = nil
            table.insert(ret, table.concat(line))
        else
            ret[#ret] = string.sub(ret[#ret], -2)
        end
        tableVisit[tab] = nil
        return ret
    end

    local ret = subWrite(value, indentString)
    if type(ret) == "string" then return ret end
    local s = maybeShortTable(ret, 0, indentWidth)
    return s or string.format("{\n%s\n}", table.concat(ret, "\n"))
end

local function printOne(value)
    local ret = writeInternal(value)
    if type(ret) == "string" then
        io.write(ret)
        return
    end
    local s = maybeShortTable(ret, 0, indentWidth)
    if s ~= nil then io.write(s) end
    io.write("{\n")
    for _, v in ipairs(ret) do
        io.write(v)
        io.write('\n')
    end
    io.write("\n}")
end


---Convert value to a pretty string.
---@param value any
---@return string
local function write(value)
    local ret = writeInternal(value)
    if type(ret) == "string" then return ret end
    local s = maybeShortTable(ret, 0, indentWidth)
    return s or string.format("{\n%s\n}", table.concat(ret, "\n"))
end

---Set the line break limit.
---Note: this limit can only control the line breaks of tables,
---  it cannot absolutely control the maximum length of each line.
---@param limit integer
---@return nil
local function setLineBreakLimit(limit)
    if limit * 2 >= maxSafeInteger then error("limit is too large") end
    if limit <= 3 then error("limit is too small") end
    if limit / 2 < indentWidth then error("limit is too small") end
    lineBreakLimit = limit
end

---Set the indentation width.
---@param width integer
---@return nil
local function setIndentWidth(width)
    if width <= 0 then error("width is too small") end
    if width * 2 >= lineBreakLimit then error("width is too large") end
    indentWidth = width
    indentString = string.rep(" ", width)
end

---Set the maximum number of consecutive nil values allowed in an array;
---values exceeding this limit will be considered as part of the table.
---@param num integer
local function setMaximumNilNumberAllowed(num)
    if num < 0 then error("num is too small") end
    if num >= maxSafeInteger then error("num is too large") end
    maximumNilNumberAllowed = num
end

---Pretty print output.
---@param ... any
---@return nil
local function prettyPrint(...)
    local data = { ... }
    for i = 1, #data do
        if i > 1 then io.write("\t") end
        printOne(data[i])
    end
    io.write("\n")
end

local M = {
    write = write,
    setColumnLimit = setLineBreakLimit,
    setTabWidth = setIndentWidth,
    setMaximumNilNumberAllowed = setMaximumNilNumberAllowed,
    print = prettyPrint
}
return setmetatable(M, {
    __call = function(_, ...) return prettyPrint(...) end
})
