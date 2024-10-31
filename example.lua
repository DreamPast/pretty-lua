local pt = require("pretty")
local write = pt.write;
local setMaximumNilNumberAllowed = pt.setMaximumNilNumberAllowed;


print(write(nil))
print(write(true))
print(write(1919))
print(write(1145.14))
print(write("12"))
print(write("ABC\x01"))
print(write(function() end))


print(write({ 1, 2, 3 }))
print(write({ 1000, 1001, 1002, 1003, 1004, 1005, 1006, 1007, 1008, 1009, 1010, 1011 }))
do
    local s = {}
    for i = 1, 64 do table.insert(s, i) end
    print(write(s))
end
do
    setMaximumNilNumberAllowed(3);
    print(write({ 1, 2, nil, 3, nil, nil, 4, nil, nil, nil, 5, nil, nil, nil, nil, 6 }))
end


setMaximumNilNumberAllowed(0)
print(write({
    a = 1,
    b = true,
    c = function() end,
    d = { 1, 2 },
    e = { 1000, 1001, 1002, 1003, 1004, 1005, 1006, 1007, 1008, 1009, 1010, 1011 }
}))
do
    local s = { 12, 13 }
    local t = { s }
    s[3] = t
    print(write(t))
end
do
    local s = { {} }
    for i = 2, 64 do
        s[i] = { s[i - 1] }
    end
    print(write(s[64]))
end
