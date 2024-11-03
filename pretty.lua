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

---@param value number
local function checkUsingIntegerFormatter(value)
    if value == 0 then return string.sub(tostring(value), 1, 2) ~= "-0" end
    if value ~= value and value * 0.5 == value then return false end
    return isInteger(value)
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

---@generic T
---@type fun(value:T):T
local function copyTable(value)
    local ret = {}
    for k, v in pairs(value) do ret[k] = v end
    return ret
end


---Convert a number to a string.
---@type fun(value:number):string
local function num2string(value)
    if checkUsingIntegerFormatter(value) then
        return ("%d"):format(value)
    else
        return ("%.14g"):format(value)
    end
end

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

---@param x any
---@return string
local function addressFormatter(x) return "<" .. tostring(x) .. ">" end

---@class _InnerPrettyOption
---@field nil fun(x:nil):string
---@field number fun(x:number):string
---@field string fun(x:string):string
---@field boolean fun(x:boolean):string
---@field function fun(x:function):string
---@field userdata fun(x:userdata):string
---@field thread fun(x:thread):string
---@field table fun(x:table):string
---@field cycleTableFormatter fun(x:table):string
---@field indentString string
---@field lineBreakLimit integer
---@field maximumNilNumberAllowed number
---@field numberFormatter nil|fun(x:number):nil
---@field integerFormatter nil|fun(x:integer):nil

local backupGlobalPrettyOption = {
    ["nil"] = function() return "nil" end,
    ["number"] = num2string,
    ["string"] = function(x) return "\"" .. escapeString(x) .. "\"" end,
    ["boolean"] = function(x) return (x and "true") or "false" end,
    ["function"] = addressFormatter,
    ["userdata"] = addressFormatter,
    ["thread"] = addressFormatter,
    ["table"] = addressFormatter,
    cycleTableFormatter = function(x) return "<cycle " .. tostring(x) .. ">" end,
    indentString = "  ",
    lineBreakLimit = 64,
    maximumNilNumberAllowed = 0,
    numberFormatter = nil,
    integerFormatter = nil,
}

---@type _InnerPrettyOption
local globalPrettyOption = copyTable(backupGlobalPrettyOption)

---@param value any
---@param option _InnerPrettyOption
---@return string
local function writeDirect(value, option) return option[type(value)](value) end

---@param tab any[]
---@param maximumNilNumberAllowed integer
---@return integer
local function getArraySize(tab, maximumNilNumberAllowed)
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
---@param lineBreakLimit integer
---@return string|nil
local function maybeShortTable(item, leadingSpaceLength, trimSpaceLength, lineBreakLimit)
    local arr = {} ---@type string[]
    local size = 4 + leadingSpaceLength ---@type integer
    for _, str in ipairs(item) do
        local s = string.sub(str, trimSpaceLength + 1)
        size = size + #s + 1
        table.insert(arr, s)
        if size >= lineBreakLimit then return nil end
    end
    if arr[1] == nil then return "{ }" end
    return "{ " .. table.concat(arr, " ") .. " }"
end

---@param value any
---@param option _InnerPrettyOption
---@return string|string[]
local function writeInternal(value, option)
    if type(value) ~= "table" then return writeDirect(value, option) end
    local lineBreakLimit = option.lineBreakLimit
    local indentString = option.indentString
    local maximumNilNumberAllowed = option.maximumNilNumberAllowed

    local tableVisit = {} ---@type table<table, boolean>
    local integerSet = {} ---@type table<integer, boolean>

    ---@param leadingSpace string
    ---@return string|string[]
    local function subWrite(tab, leadingSpace)
        local typ = type(tab)
        if typ ~= "table" then return writeDirect(tab, option) end
        if tableVisit[tab] then return option.cycleTableFormatter(tab) end
        tableVisit[tab] = true
        if #leadingSpace >= lineBreakLimit then
            error("leading space is too long")
        end

        local integerSize = getArraySize(tab, maximumNilNumberAllowed)
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
                local s = maybeShortTable(item, #leadingSpace + #preffix, #newLeadingSpace, lineBreakLimit)
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
            push(subWrite(tab[key], newLeadingSpace), string.format("[%s] = ", writeDirect(key, option)))
        end

        if line[2] ~= nil then
            line[#line] = nil
            table.insert(ret, table.concat(line))
        elseif #ret ~= 0 then
            ret[#ret] = string.sub(ret[#ret], -2)
        end
        tableVisit[tab] = nil
        return ret
    end

    local ret = subWrite(value, indentString)
    if type(ret) == "string" then return ret end
    local s = maybeShortTable(ret, 0, #indentString, lineBreakLimit)
    return s or string.format("{\n%s\n}", table.concat(ret, "\n"))
end

---@param value any
---@param option _InnerPrettyOption
local function printOne(value, option)
    local ret = writeInternal(value, option)
    if type(ret) == "string" then
        io.write(ret)
        return
    end
    local s = maybeShortTable(ret, 0, #option.indentString, option.lineBreakLimit)
    if s ~= nil then io.write(s) end
    io.write("{\n")
    for _, v in ipairs(ret) do
        io.write(v)
        io.write("\n")
    end
    io.write("\n}")
end

---@class PrettyOption
---@field integerFormatter nil|fun(x:integer):string
---@field numberFormatter nil|fun(x:number):string
---@field stringFormatter nil|fun(x:string):string
---@field booleanFormatter nil|fun(x:boolean):string
---@field functionFormatter nil|fun(x:function):string
---@field userdataFormatter nil|fun(x:userdata):string
---@field threadFormatter nil|fun(x:thread):string
---@field indentWidth nil|integer
---@field lineBreakLimit nil|integer
---@field maximumNilNumberAllowed nil|number

---@generic T
---@param func fun(value:T):any
---@return fun(value:T):string
local function wrapFunction(func) return function(x) return tostring(func(x)) end end

---@param option _InnerPrettyOption
---@return nil
local function checkOption(option)
    if not (type(option.lineBreakLimit) == 'number'
            and option.lineBreakLimit >= 4
            and option.lineBreakLimit <= maxSafeInteger / 2
            and option.lineBreakLimit / 2 >= #option.indentString) then
        error("\"lineBreakLimit\" is illegal")
    end
    if not (type(option.maximumNilNumberAllowed) == 'number'
            and option.maximumNilNumberAllowed >= 0
            and option.maximumNilNumberAllowed <= maxSafeInteger) then
        error("\"maximumNilNumberAllowed\" is illegal")
    end
end

---@param indentWidth any
---@return string
local function makeIndentString(indentWidth)
    local num = tonumber(indentWidth)
    if num == nil then error("not a number") end
    return string.rep(" ", indentWidth)
end

---@param numberFormatter fun(value:number):string
---@param integerFormatter fun(value:integer):string
---@return fun(value:number):string
local function makeNumberFormatter(numberFormatter, integerFormatter)
    if numberFormatter == nil and integerFormatter == nil then
        return num2string
    end
    numberFormatter = (numberFormatter ~= nil and wrapFunction(numberFormatter)) or num2string
    integerFormatter = (integerFormatter ~= nil and wrapFunction(integerFormatter)) or num2string
    return function(value)
        return (checkUsingIntegerFormatter(value) and integerFormatter(value)) or numberFormatter(value)
    end
end

---@param option PrettyOption|nil
---@return _InnerPrettyOption
local function mergeOption(option)
    if option == nil then return globalPrettyOption end
    if type(option) ~= 'table' then error("`option` is not a table") end
    local retOption = copyTable(globalPrettyOption)
    retOption["number"] = makeNumberFormatter(option.numberFormatter, option.integerFormatter)
    if option.stringFormatter ~= nil then
        retOption["string"] = wrapFunction(option.stringFormatter)
    end
    if option.booleanFormatter ~= nil then
        retOption["boolean"] = wrapFunction(option.booleanFormatter)
    end
    if option.functionFormatter ~= nil then
        retOption["function"] = wrapFunction(option.functionFormatter)
    end
    if option.userdataFormatter ~= nil then
        retOption["userdata"] = wrapFunction(option.userdataFormatter)
    end
    if option.threadFormatter ~= nil then
        retOption["thread"] = wrapFunction(option.threadFormatter)
    end
    if option.indentWidth ~= nil then
        retOption.indentString = makeIndentString(option.indentWidth)
    end
    if option.lineBreakLimit ~= nil then
        retOption.lineBreakLimit = tonumber(option.lineBreakLimit) or error("not an integer")
    end
    if option.maximumNilNumberAllowed ~= nil then
        retOption.maximumNilNumberAllowed = tonumber(option.maximumNilNumberAllowed) or error("not an integer")
    end
    checkOption(retOption)
    return retOption
end

---@param option PrettyOption
---@return nil
local function updateOption(option) globalPrettyOption = mergeOption(option) end

---@return nil
local function resetOption() globalPrettyOption = copyTable(backupGlobalPrettyOption) end

---Convert value to a pretty string.
---@param value any
---@param option PrettyOption|nil
---@return string
local function write(value, option)
    local mergedOption = mergeOption(option)
    local ret = writeInternal(value, mergedOption)
    if type(ret) == "string" then return ret end
    local s = maybeShortTable(ret, 0, #mergedOption.indentString, mergedOption.lineBreakLimit)
    return s or string.format("{\n%s\n}", table.concat(ret, "\n"))
end

---Set the line break limit.
---Note: this limit can only control the line breaks of tables,
---  it cannot absolutely control the maximum length of each line.
---@param limit integer
---@return nil
local function setLineBreakLimit(limit) updateOption({ lineBreakLimit = limit }) end

---Set the indentation width.
---@param width integer
---@return nil
local function setIndentWidth(width) updateOption({ indentWidth = width }) end

---Set the maximum number of consecutive nil values allowed in an array;
---values exceeding this limit will be considered as part of the table.
---@param num integer
local function setMaximumNilNumberAllowed(num) updateOption({ maximumNilNumberAllowed = num }) end

---@param option PrettyOption|nil
---@return fun(...):nil
local function makePrinter(option)
    local mergedOption = mergeOption(option)
    return function(...)
        local data, dataLen = { ... }, select("#", ...)
        if dataLen >= 1 then
            printOne(data[1], mergedOption)
            for i = 2, dataLen do
                io.write("\t")
                printOne(data[i], mergedOption)
            end
        end
        io.write("\n")
    end
end

---Pretty print output.
---@param ... any
---@return nil
local function prettyPrint(...)
    local data, dataLen = { ... }, select("#", ...)
    if dataLen >= 1 then
        printOne(data[1], globalPrettyOption)
        for i = 2, dataLen do
            io.write("\t")
            printOne(data[i], globalPrettyOption)
        end
    end
    io.write("\n")
end

local M = {
    write = write,
    setColumnLimit = setLineBreakLimit,
    setTabWidth = setIndentWidth,
    setMaximumNilNumberAllowed = setMaximumNilNumberAllowed,
    updateOption = updateOption,
    resetOption = resetOption,
    print = prettyPrint,
    makePrinter = makePrinter,
}
return setmetatable(M, {
    __call = function(_, ...) return prettyPrint(...) end
})
