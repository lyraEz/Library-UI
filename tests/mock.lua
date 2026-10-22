--[[
    A small Roblox stand-in for running Lyra UI with the plain Luau CLI.

    It is not an engine: there is no rendering and no real layout. It exists to execute the library's code
    paths and fail loudly on the mistakes that matter outside Studio: unknown classes, misspelled
    properties or enum items, wrong value types, writes to read-only properties, use of destroyed
    instances and errors inside callbacks or tasks.

    tests/build.sh concatenates this file, src/Lyra.lua, the examples and tests/run.lua into one chunk,
    so everything below is a local that the library sees as its globals.
]]

local Mock = {Errors = {}, Warnings = {}, Files = {}, Clipboard = nil, Now = 0, Module = nil}
local realOs = os
local os = setmetatable({clock = function() return Mock.Now end}, {__index = realOs})

local function fail(message) error(message, 3) end

-- -----------------------------------------------------------------------------
-- typeof and data types
-- -----------------------------------------------------------------------------
local function typeof(value)
    local meta = getmetatable(value)
    if type(meta) == "table" and meta.__type then return meta.__type end
    return type(value)
end
local function strict(typeName, fields, methods)
    local meta = {__type = typeName}
    meta.__index = function(self, key)
        if methods and methods[key] then return methods[key] end
        if fields and fields[key] then return fields[key](self) end
        fail(tostring(key) .. " is not a valid member of " .. typeName)
    end
    meta.__newindex = function(_, key) fail(typeName .. "." .. tostring(key) .. " cannot be assigned to") end
    return meta
end
local function expect(value, typeName, where)
    if typeof(value) ~= typeName then fail(where .. " expects " .. typeName .. ", got " .. typeof(value)) end
end
local function number(value, where)
    if type(value) ~= "number" then fail(where .. " expects a number, got " .. typeof(value)) end
    if value ~= value then fail(where .. " got NaN") end
    return value
end

local Vector2Meta
local function v2(x, y) return setmetatable({X = number(x or 0, "Vector2.new"), Y = number(y or 0, "Vector2.new")}, Vector2Meta) end
Vector2Meta = strict("Vector2", {Magnitude = function(self) return math.sqrt(self.X * self.X + self.Y * self.Y) end})
Vector2Meta.__add = function(a, b) expect(a, "Vector2", "Vector2 +"); expect(b, "Vector2", "Vector2 +"); return v2(a.X + b.X, a.Y + b.Y) end
Vector2Meta.__sub = function(a, b) expect(a, "Vector2", "Vector2 -"); expect(b, "Vector2", "Vector2 -"); return v2(a.X - b.X, a.Y - b.Y) end
Vector2Meta.__mul = function(a, b)
    if type(a) == "number" then return v2(a * b.X, a * b.Y) end
    if type(b) == "number" then return v2(a.X * b, a.Y * b) end
    return v2(a.X * b.X, a.Y * b.Y)
end
Vector2Meta.__div = function(a, b)
    if type(b) == "number" then return v2(a.X / b, a.Y / b) end
    return v2(a.X / b.X, a.Y / b.Y)
end
Vector2Meta.__unm = function(a) return v2(-a.X, -a.Y) end
Vector2Meta.__eq = function(a, b) return a.X == b.X and a.Y == b.Y end
Vector2Meta.__tostring = function(a) return a.X .. ", " .. a.Y end
local Vector2 = {new = v2, zero = v2(0, 0), one = v2(1, 1)}

local Vector3Meta
local function v3(x, y, z) return setmetatable({X = number(x or 0, "Vector3.new"), Y = number(y or 0, "Vector3.new"), Z = number(z or 0, "Vector3.new")}, Vector3Meta) end
Vector3Meta = strict("Vector3", {Magnitude = function(self) return math.sqrt(self.X ^ 2 + self.Y ^ 2 + self.Z ^ 2) end,
    Unit = function(self) local m = math.sqrt(self.X ^ 2 + self.Y ^ 2 + self.Z ^ 2); return m > 0 and v3(self.X / m, self.Y / m, self.Z / m) or v3() end})
Vector3Meta.__add = function(a, b) return v3(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
Vector3Meta.__sub = function(a, b) return v3(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
Vector3Meta.__mul = function(a, b)
    if type(a) == "number" then return v3(a * b.X, a * b.Y, a * b.Z) end
    if type(b) == "number" then return v3(a.X * b, a.Y * b, a.Z * b) end
    return v3(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end
Vector3Meta.__div = function(a, b) return v3(a.X / b, a.Y / b, a.Z / b) end
Vector3Meta.__eq = function(a, b) return a.X == b.X and a.Y == b.Y and a.Z == b.Z end
local Vector3 = {new = v3, zero = v3(), one = v3(1, 1, 1)}

local CFrameMeta
local function cf(position, look) return setmetatable({Position = position or v3(), LookVector = look or v3(0, 0, -1)}, CFrameMeta) end
CFrameMeta = strict("CFrame", nil, {Inverse = function(self) return self end})
CFrameMeta.__mul = function(a) return a end
local CFrame = {
    new = function(x, y, z) return cf(v3(x or 0, y or 0, z or 0)) end,
    lookAt = function(at, target) expect(at, "Vector3", "CFrame.lookAt"); expect(target, "Vector3", "CFrame.lookAt"); return cf(at, (target - at).Unit) end,
}

local UDimMeta = strict("UDim")
UDimMeta.__eq = function(a, b) return a.Scale == b.Scale and a.Offset == b.Offset end
local function udim(scale, offset) return setmetatable({Scale = number(scale or 0, "UDim.new"), Offset = math.floor(number(offset or 0, "UDim.new"))}, UDimMeta) end
local UDim = {new = udim}

local UDim2Meta
local function udim2(xs, xo, ys, yo)
    local x, y = udim(xs, xo), udim(ys, yo)
    return setmetatable({X = x, Y = y, Width = x, Height = y}, UDim2Meta)
end
UDim2Meta = strict("UDim2")
UDim2Meta.__eq = function(a, b) return a.X == b.X and a.Y == b.Y end
UDim2Meta.__add = function(a, b) return udim2(a.X.Scale + b.X.Scale, a.X.Offset + b.X.Offset, a.Y.Scale + b.Y.Scale, a.Y.Offset + b.Y.Offset) end
UDim2Meta.__sub = function(a, b) return udim2(a.X.Scale - b.X.Scale, a.X.Offset - b.X.Offset, a.Y.Scale - b.Y.Scale, a.Y.Offset - b.Y.Offset) end
local UDim2 = {
    new = function(xs, xo, ys, yo) return udim2(xs, xo, ys, yo) end,
    fromOffset = function(x, y) return udim2(0, x, 0, y) end,
    fromScale = function(x, y) return udim2(x, 0, y, 0) end,
}

local Color3Meta
local function color(r, g, b)
    for _, value in ipairs({r or 0, g or 0, b or 0}) do number(value, "Color3.new") end
    return setmetatable({R = r or 0, G = g or 0, B = b or 0}, Color3Meta)
end
Color3Meta = strict("Color3", nil, {Lerp = function(a, b, t)
    expect(b, "Color3", "Color3:Lerp")
    return color(a.R + (b.R - a.R) * t, a.G + (b.G - a.G) * t, a.B + (b.B - a.B) * t)
end})
Color3Meta.__eq = function(a, b) return a.R == b.R and a.G == b.G and a.B == b.B end
local Color3 = {new = color, fromRGB = function(r, g, b) return color((r or 0) / 255, (g or 0) / 255, (b or 0) / 255) end}

local function opaque(typeName, check)
    return {new = function(...) if check then check(...) end; return setmetatable({Values = {...}}, strict(typeName)) end}
end
local ColorSequence = opaque("ColorSequence", function(a, b)
    if typeof(a) == "Color3" then if b ~= nil then expect(b, "Color3", "ColorSequence.new") end; return end
    if type(a) ~= "table" then fail("ColorSequence.new expects Color3 or keypoints") end
end)
local ColorSequenceKeypoint = opaque("ColorSequenceKeypoint", function(t, c) number(t, "ColorSequenceKeypoint.new"); expect(c, "Color3", "ColorSequenceKeypoint.new") end)
local NumberSequence = opaque("NumberSequence")
local NumberSequenceKeypoint = opaque("NumberSequenceKeypoint", function(t, v) number(t, "NumberSequenceKeypoint.new"); number(v, "NumberSequenceKeypoint.new") end)
local TweenInfoMeta = strict("TweenInfo")
local TweenInfo = {new = function(time, style, direction)
    if style ~= nil then expect(style, "EnumItem", "TweenInfo.new") end
    if direction ~= nil then expect(direction, "EnumItem", "TweenInfo.new") end
    return setmetatable({Time = number(time or 1, "TweenInfo.new"), EasingStyle = style, EasingDirection = direction}, TweenInfoMeta)
end}

-- -----------------------------------------------------------------------------
-- Enums: only the items listed here exist, so a typo fails like it would in Roblox.
-- -----------------------------------------------------------------------------
local ENUMS = {
    Font = {"Gotham", "GothamBold", "GothamMedium", "Code", "BuilderSans", "BuilderSansMedium", "BuilderSansBold", "SourceSans"},
    AutomaticSize = {"None", "X", "Y", "XY"},
    TextXAlignment = {"Left", "Center", "Right"},
    TextYAlignment = {"Top", "Center", "Bottom"},
    TextTruncate = {"None", "AtEnd", "SplitWord"},
    SortOrder = {"LayoutOrder", "Name"},
    FillDirection = {"Horizontal", "Vertical"},
    HorizontalAlignment = {"Left", "Center", "Right"},
    VerticalAlignment = {"Top", "Center", "Bottom"},
    ScrollingDirection = {"X", "Y", "XY"},
    ElasticBehavior = {"WhenScrollable", "Always", "Never"},
    ZIndexBehavior = {"Global", "Sibling"},
    EasingStyle = {"Linear", "Sine", "Back", "Quad", "Quart", "Quint", "Bounce", "Elastic", "Exponential", "Circular", "Cubic"},
    EasingDirection = {"In", "Out", "InOut"},
    ScaleType = {"Stretch", "Slice", "Tile", "Fit", "Crop"},
    ApplyStrokeMode = {"Contextual", "Border"},
    UserInputType = {"MouseButton1", "MouseButton2", "MouseMovement", "MouseWheel", "Touch", "Keyboard", "Focus", "Gamepad1", "None"},
    UserInputState = {"Begin", "Change", "End", "Cancel", "None"},
    KeyCode = {"Unknown", "Escape", "Return", "Space", "Tab", "Backspace", "Slash", "LeftControl", "RightControl", "LeftShift", "RightShift",
        "LeftAlt", "RightAlt", "Insert", "Delete", "Home", "End", "PageUp", "PageDown", "Up", "Down", "Left", "Right",
        "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z",
        "F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9", "F10", "F11", "F12", "One", "Two", "Three"},
    PlaybackState = {"Begin", "Playing", "Paused", "Completed", "Cancelled"},
    HumanoidRigType = {"R6", "R15"},
}
local EnumItemMeta = {__type = "EnumItem", __tostring = function(self) return "Enum." .. self.EnumType .. "." .. self.Name end}
EnumItemMeta.__index = function(_, key) fail(tostring(key) .. " is not a valid member of EnumItem") end
local Enum = {}
for enumName, items in pairs(ENUMS) do
    local enum, index = {}, {}
    for position, itemName in ipairs(items) do
        local item = setmetatable({Name = itemName, EnumType = enumName, Value = position - 1}, EnumItemMeta)
        enum[itemName] = item
        table.insert(index, item)
    end
    setmetatable(enum, {__index = function(_, key)
        if key == "GetEnumItems" then return function() return index end end
        fail(tostring(key) .. " is not a valid EnumItem of Enum." .. enumName)
    end})
    Enum[enumName] = enum
end
setmetatable(Enum, {__index = function(_, key) fail(tostring(key) .. " is not a valid Enum") end})

-- -----------------------------------------------------------------------------
-- Scheduler: task.* on a virtual clock. Mock.advance(seconds) runs everything due by then.
-- -----------------------------------------------------------------------------
local Queue = {}
local sequence = 0
local function report(thread, problem)
    local trace = debug.traceback(thread, tostring(problem))
    table.insert(Mock.Errors, trace)
end
local function resume(thread, ...)
    local ok, problem = coroutine.resume(thread, ...)
    if not ok then report(thread, problem) end
    return thread
end
local function schedule(at, thread, ...)
    sequence = sequence + 1
    table.insert(Queue, {At = at, Seq = sequence, Thread = thread, Args = table.pack(...)})
end
local function threadOf(fn)
    if type(fn) == "thread" then return fn end
    if type(fn) ~= "function" then fail("task expects a function or thread, got " .. typeof(fn)) end
    return coroutine.create(fn)
end
local task = {}
function task.spawn(fn, ...) return resume(threadOf(fn), ...) end
function task.defer(fn, ...) local thread = threadOf(fn); schedule(Mock.Now, thread, ...); return thread end
function task.delay(seconds, fn, ...) local thread = threadOf(fn); schedule(Mock.Now + (seconds or 0), thread, ...); return thread end
function task.wait(seconds)
    local thread = coroutine.running()
    if not thread or not coroutine.isyieldable() then fail("task.wait called outside a yieldable thread") end
    seconds = math.max(seconds or 0.03, 0.001)
    schedule(Mock.Now + seconds, thread, seconds)
    return coroutine.yield()
end
function task.cancel(thread) for i = #Queue, 1, -1 do if Queue[i].Thread == thread then table.remove(Queue, i) end end end
function Mock.advance(seconds)
    local target = Mock.Now + (seconds or 0)
    while true do
        local best, bestIndex
        for index, item in ipairs(Queue) do
            if item.At <= target and (not best or item.At < best.At or (item.At == best.At and item.Seq < best.Seq)) then best, bestIndex = item, index end
        end
        if not best then break end
        table.remove(Queue, bestIndex)
        Mock.Now = math.max(Mock.Now, best.At)
        if coroutine.status(best.Thread) == "suspended" then resume(best.Thread, table.unpack(best.Args, 1, best.Args.n)) end
    end
    Mock.Now = target
end

-- -----------------------------------------------------------------------------
-- Signals
-- -----------------------------------------------------------------------------
local SignalMeta = {__type = "RBXScriptSignal"}
SignalMeta.__index = SignalMeta
local function signal(name) return setmetatable({Name = name, Connections = {}}, SignalMeta) end
function SignalMeta:Connect(fn)
    if type(fn) ~= "function" then fail("Connect expects a function") end
    local connection = {Connected = true, Fn = fn}
    function connection.Disconnect(item) item.Connected = false end
    setmetatable(connection, {__type = "RBXScriptConnection"})
    table.insert(self.Connections, connection)
    return connection
end
SignalMeta.connect = SignalMeta.Connect
function SignalMeta:Fire(...)
    local list = table.clone(self.Connections)
    for _, connection in ipairs(list) do
        if connection.Connected then task.spawn(connection.Fn, ...) end
    end
end
function SignalMeta:DisconnectAll() for _, connection in ipairs(self.Connections) do connection.Connected = false end; self.Connections = {} end
function SignalMeta:Count()
    local count = 0
    for _, connection in ipairs(self.Connections) do if connection.Connected then count = count + 1 end end
    return count
end

-- -----------------------------------------------------------------------------
-- Instances
-- -----------------------------------------------------------------------------
local GROUPS = {
    Instance = {props = {"Name", "Parent", "ClassName", "Archivable"}, readonly = {ClassName = true},
        events = {"Changed", "ChildAdded", "ChildRemoved", "DescendantAdded", "Destroying", "AncestryChanged"}},
    GuiBase2d = {props = {"AbsoluteSize", "AbsolutePosition", "AbsoluteRotation"}, readonly = {AbsoluteSize = true, AbsolutePosition = true, AbsoluteRotation = true}},
    GuiObject = {props = {"Active", "AnchorPoint", "AutomaticSize", "BackgroundColor3", "BackgroundTransparency", "BorderColor3", "BorderSizePixel", "ClipsDescendants",
        "LayoutOrder", "Position", "Rotation", "Selectable", "Size", "Visible", "ZIndex", "Interactable"},
        types = {Position = "UDim2", Size = "UDim2", AnchorPoint = "Vector2", BackgroundColor3 = "Color3", BackgroundTransparency = "number", Visible = "boolean",
            ZIndex = "number", LayoutOrder = "number", AutomaticSize = "EnumItem", Rotation = "number", BorderSizePixel = "number", Active = "boolean", ClipsDescendants = "boolean"},
        events = {"InputBegan", "InputChanged", "InputEnded", "MouseEnter", "MouseLeave", "MouseMoved", "TouchTap"}},
    Text = {props = {"Font", "RichText", "Text", "TextColor3", "TextScaled", "TextSize", "TextTransparency", "TextTruncate", "TextWrapped", "TextXAlignment",
        "TextYAlignment", "LineHeight", "TextStrokeTransparency", "ContentText", "TextBounds", "TextFits"},
        readonly = {ContentText = true, TextBounds = true, TextFits = true},
        types = {Font = "EnumItem", Text = "string", TextColor3 = "Color3", TextSize = "number", TextTransparency = "number", TextWrapped = "boolean", RichText = "boolean",
            TextXAlignment = "EnumItem", TextYAlignment = "EnumItem", TextTruncate = "EnumItem"}},
    TextBox = {props = {"ClearTextOnFocus", "CursorPosition", "MultiLine", "PlaceholderColor3", "PlaceholderText", "SelectionStart", "TextEditable", "ShowNativeInput"},
        types = {PlaceholderColor3 = "Color3", PlaceholderText = "string", MultiLine = "boolean", TextEditable = "boolean", ClearTextOnFocus = "boolean"},
        events = {"Focused", "FocusLost"}},
    GuiButton = {props = {"AutoButtonColor", "Modal", "Selected"}, types = {AutoButtonColor = "boolean"},
        events = {"Activated", "MouseButton1Click", "MouseButton1Down", "MouseButton1Up"}},
    Image = {props = {"Image", "ImageColor3", "ImageRectOffset", "ImageRectSize", "ImageTransparency", "ScaleType", "SliceCenter", "ResampleMode"},
        types = {Image = "string", ImageColor3 = "Color3", ImageRectOffset = "Vector2", ImageRectSize = "Vector2", ScaleType = "EnumItem"}},
    ScrollingFrame = {props = {"AbsoluteCanvasSize", "AbsoluteWindowSize", "AutomaticCanvasSize", "CanvasPosition", "CanvasSize", "ElasticBehavior", "ScrollBarImageColor3",
        "ScrollBarImageTransparency", "ScrollBarThickness", "ScrollingDirection", "ScrollingEnabled", "VerticalScrollBarInset"},
        readonly = {AbsoluteCanvasSize = true, AbsoluteWindowSize = true},
        types = {CanvasSize = "UDim2", CanvasPosition = "Vector2", ScrollBarImageColor3 = "Color3", ScrollingEnabled = "boolean", AutomaticCanvasSize = "EnumItem",
            ScrollingDirection = "EnumItem", ElasticBehavior = "EnumItem", ScrollBarThickness = "number"}},
    CanvasGroup = {props = {"GroupColor3", "GroupTransparency"}, types = {GroupTransparency = "number"}},
    ViewportFrame = {props = {"Ambient", "CurrentCamera", "ImageColor3", "ImageTransparency", "LightColor", "LightDirection"},
        types = {Ambient = "Color3", LightColor = "Color3", LightDirection = "Vector3"}},
    ScreenGui = {props = {"DisplayOrder", "Enabled", "IgnoreGuiInset", "ResetOnSpawn", "ZIndexBehavior", "ScreenInsets"},
        types = {DisplayOrder = "number", ResetOnSpawn = "boolean", IgnoreGuiInset = "boolean", ZIndexBehavior = "EnumItem"}},
    UICorner = {props = {"CornerRadius"}, types = {CornerRadius = "UDim"}},
    UIStroke = {props = {"ApplyStrokeMode", "Color", "Enabled", "LineJoinMode", "Thickness", "Transparency"}, types = {Color = "Color3", Thickness = "number", Transparency = "number"}},
    UIScale = {props = {"Scale"}, types = {Scale = "number"}},
    UIGradient = {props = {"Color", "Enabled", "Offset", "Rotation", "Transparency"}, types = {Color = "ColorSequence", Rotation = "number", Transparency = "NumberSequence"}},
    UIListLayout = {props = {"FillDirection", "HorizontalAlignment", "Padding", "SortOrder", "VerticalAlignment", "Wraps", "AbsoluteContentSize"},
        readonly = {AbsoluteContentSize = true}, types = {Padding = "UDim", FillDirection = "EnumItem", SortOrder = "EnumItem"}},
    UIGridLayout = {props = {"CellPadding", "CellSize", "FillDirection", "FillDirectionMaxCells", "HorizontalAlignment", "SortOrder", "StartCorner", "VerticalAlignment", "AbsoluteContentSize"},
        readonly = {AbsoluteContentSize = true}, types = {CellPadding = "UDim2", CellSize = "UDim2", FillDirectionMaxCells = "number"}},
    UIPadding = {props = {"PaddingBottom", "PaddingLeft", "PaddingRight", "PaddingTop"}, types = {PaddingBottom = "UDim", PaddingLeft = "UDim", PaddingRight = "UDim", PaddingTop = "UDim"}},
    UISizeConstraint = {props = {"MaxSize", "MinSize"}, types = {MaxSize = "Vector2", MinSize = "Vector2"}},
    BlurEffect = {props = {"Enabled", "Size"}, types = {Size = "number", Enabled = "boolean"}},
    Camera = {props = {"CFrame", "FieldOfView", "Focus", "CameraType"}, types = {CFrame = "CFrame", FieldOfView = "number"}},
    TextChatCommand = {props = {"Enabled", "PrimaryAlias", "SecondaryAlias", "AutocompleteVisible"}, types = {PrimaryAlias = "string"}, events = {"Triggered"}},
    BasePart = {props = {"Anchored", "CFrame", "Position", "Size", "CanCollide", "Transparency"}, types = {Anchored = "boolean"}},
    Model = {props = {"PrimaryPart", "WorldPivot"}},
    Player = {props = {"UserId", "DisplayName", "Character"}, events = {"Chatted"}},
}
local CLASSES = {
    Folder = {groups = {}, isa = {}},
    Frame = {groups = {"GuiBase2d", "GuiObject"}, isa = {"GuiBase2d", "GuiObject"}},
    CanvasGroup = {groups = {"GuiBase2d", "GuiObject", "CanvasGroup"}, isa = {"GuiBase2d", "GuiObject"}},
    ScrollingFrame = {groups = {"GuiBase2d", "GuiObject", "ScrollingFrame"}, isa = {"GuiBase2d", "GuiObject"}},
    TextLabel = {groups = {"GuiBase2d", "GuiObject", "Text"}, isa = {"GuiBase2d", "GuiObject", "GuiLabel"}},
    TextButton = {groups = {"GuiBase2d", "GuiObject", "Text", "GuiButton"}, isa = {"GuiBase2d", "GuiObject", "GuiButton"}},
    TextBox = {groups = {"GuiBase2d", "GuiObject", "Text", "TextBox"}, isa = {"GuiBase2d", "GuiObject"}},
    ImageLabel = {groups = {"GuiBase2d", "GuiObject", "Image"}, isa = {"GuiBase2d", "GuiObject", "GuiLabel"}},
    ImageButton = {groups = {"GuiBase2d", "GuiObject", "Image", "GuiButton"}, isa = {"GuiBase2d", "GuiObject", "GuiButton"}},
    ViewportFrame = {groups = {"GuiBase2d", "GuiObject", "ViewportFrame"}, isa = {"GuiBase2d", "GuiObject"}},
    ScreenGui = {groups = {"GuiBase2d", "ScreenGui"}, isa = {"GuiBase2d", "LayerCollector"}},
    UICorner = {groups = {"UICorner"}, isa = {"UIComponent"}},
    UIStroke = {groups = {"UIStroke"}, isa = {"UIComponent"}},
    UIScale = {groups = {"UIScale"}, isa = {"UIComponent"}},
    UIGradient = {groups = {"UIGradient"}, isa = {"UIComponent"}},
    UIListLayout = {groups = {"UIListLayout"}, isa = {"UIComponent", "UILayout", "UIGridStyleLayout"}},
    UIGridLayout = {groups = {"UIGridLayout"}, isa = {"UIComponent", "UILayout", "UIGridStyleLayout"}},
    UIPadding = {groups = {"UIPadding"}, isa = {"UIComponent"}},
    UISizeConstraint = {groups = {"UISizeConstraint"}, isa = {"UIComponent", "UIConstraint"}},
    BlurEffect = {groups = {"BlurEffect"}, isa = {"PostEffect"}},
    WorldModel = {groups = {}, isa = {"WorldRoot", "Model"}},
    Camera = {groups = {"Camera"}, isa = {}},
    TextChatCommand = {groups = {"TextChatCommand"}, isa = {}},
    Model = {groups = {"Model"}, isa = {"PVInstance"}},
    Part = {groups = {"BasePart"}, isa = {"BasePart", "PVInstance"}},
    Player = {groups = {"Player"}, isa = {}, internal = true},
    PlayerGui = {groups = {}, isa = {"BasePlayerGui"}, internal = true},
    Service = {groups = {}, isa = {}, internal = true},
}
local DEFAULTS = {
    Name = nil, Archivable = true, Visible = true, Active = false, AnchorPoint = Vector2.new(), AutomaticSize = Enum.AutomaticSize.None,
    BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0, BorderSizePixel = 1, ClipsDescendants = false, LayoutOrder = 0,
    Position = UDim2.new(), Rotation = 0, Selectable = false, Size = UDim2.new(), ZIndex = 1, Interactable = true,
    Font = Enum.Font.SourceSans, RichText = false, Text = "", TextColor3 = Color3.new(0, 0, 0), TextScaled = false, TextSize = 14, TextTransparency = 0,
    TextTruncate = Enum.TextTruncate.None, TextWrapped = false, TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Center,
    ClearTextOnFocus = true, CursorPosition = -1, MultiLine = false, PlaceholderColor3 = Color3.new(0.7, 0.7, 0.7), PlaceholderText = "", SelectionStart = -1, TextEditable = true,
    AutoButtonColor = true, Image = "", ImageColor3 = Color3.new(1, 1, 1), ImageRectOffset = Vector2.new(), ImageRectSize = Vector2.new(), ImageTransparency = 0, ScaleType = Enum.ScaleType.Stretch,
    AutomaticCanvasSize = Enum.AutomaticSize.None, CanvasPosition = Vector2.new(), CanvasSize = UDim2.new(0, 0, 2, 0), ElasticBehavior = Enum.ElasticBehavior.WhenScrollable,
    ScrollBarImageColor3 = Color3.new(1, 1, 1), ScrollBarThickness = 12, ScrollingDirection = Enum.ScrollingDirection.XY, ScrollingEnabled = true,
    GroupTransparency = 0, DisplayOrder = 0, Enabled = true, IgnoreGuiInset = false, ResetOnSpawn = true, ZIndexBehavior = Enum.ZIndexBehavior.Global,
    CornerRadius = UDim.new(0, 8), Color = Color3.new(0, 0, 0), Thickness = 1, Transparency = 0, Scale = 1, Padding = UDim.new(), FillDirection = Enum.FillDirection.Vertical,
    SortOrder = Enum.SortOrder.Name, CellSize = UDim2.fromOffset(100, 100), CellPadding = UDim2.fromOffset(5, 5), FillDirectionMaxCells = 0,
    PaddingTop = UDim.new(), PaddingBottom = UDim.new(), PaddingLeft = UDim.new(), PaddingRight = UDim.new(), FieldOfView = 70, CFrame = CFrame.new(),
    Anchored = false, PrimaryAlias = "", SecondaryAlias = "",
}

local Data = setmetatable({}, {__mode = "k"})
local InstanceMeta = {__type = "Instance"}
local SCREEN = Vector2.new(1280, 720)
Mock.Screen = SCREEN
local Methods = {}
local function info(instance) return Data[instance] end
local function classInfo(className) return CLASSES[className] end
local function memberOf(className, key)
    local class = CLASSES[className]
    for _, groupName in ipairs({"Instance", table.unpack(class.groups)}) do
        local group = GROUPS[groupName]
        if group.props then for _, prop in ipairs(group.props) do if prop == key then return "prop", group end end end
        if group.events then for _, event in ipairs(group.events) do if event == key then return "event", group end end end
    end
    return nil
end
local function isA(instance, className)
    local data = info(instance)
    if data.ClassName == className or className == "Instance" then return true end
    return table.find(CLASSES[data.ClassName].isa, className) ~= nil
end
local function isGui(instance) return instance ~= nil and info(instance) ~= nil and isA(instance, "GuiBase2d") end
local absoluteSize, absolutePosition
local function scaleOf(instance)
    local data = info(instance)
    for _, child in ipairs(data.Children) do if info(child).ClassName == "UIScale" then return info(child).Props.Scale end end
    return 1
end
function absoluteSize(instance)
    local data = info(instance)
    if data.ClassName == "ScreenGui" then return SCREEN end
    local parent = data.Parent
    if not isGui(parent) or not data.Props.Size then return Vector2.new() end
    local base = absoluteSize(parent)
    local size = data.Props.Size
    local result = Vector2.new(size.X.Scale * base.X + size.X.Offset, size.Y.Scale * base.Y + size.Y.Offset)
    return result * scaleOf(instance)
end
function absolutePosition(instance)
    local data = info(instance)
    if data.ClassName == "ScreenGui" then return Vector2.new() end
    local parent = data.Parent
    if not isGui(parent) or not data.Props.Position then return Vector2.new() end
    local base, size = absolutePosition(parent), absoluteSize(parent)
    local position = data.Props.Position
    local anchor = data.Props.AnchorPoint or Vector2.new()
    local own = absoluteSize(instance)
    return base + Vector2.new(position.X.Scale * size.X + position.X.Offset, position.Y.Scale * size.Y + position.Y.Offset) - Vector2.new(anchor.X * own.X, anchor.Y * own.Y)
end

local function newInstance(className, internal)
    local class = CLASSES[className]
    if not class or (class.internal and not internal) then fail("Unable to create an Instance of type \"" .. tostring(className) .. "\"") end
    local instance = setmetatable({}, InstanceMeta)
    local props = {}
    for _, groupName in ipairs({"Instance", table.unpack(class.groups)}) do
        for _, prop in ipairs(GROUPS[groupName].props or {}) do
            local default = DEFAULTS[prop]
            if default ~= nil then props[prop] = default end
        end
    end
    if className == "BlurEffect" then props.Size = 24 end
    if className == "UIStroke" then props.Color = Color3.new(0, 0, 0) end
    props.Name = className
    Data[instance] = {ClassName = className, Props = props, Children = {}, Signals = {}, PropSignals = {}, Parent = nil, Destroyed = false, Attributes = {}}
    return instance
end
local function signalFor(instance, name)
    local data = info(instance)
    data.Signals[name] = data.Signals[name] or signal(name)
    return data.Signals[name]
end
local function setParent(instance, parent)
    local data = info(instance)
    if data.Destroyed then fail("The Parent property of " .. data.Props.Name .. " is locked, current parent: NULL, new parent " .. tostring(parent and info(parent).Props.Name)) end
    if parent ~= nil and typeof(parent) ~= "Instance" then fail("Parent expects an Instance, got " .. typeof(parent)) end
    if parent == instance then fail("Attempt to set " .. data.Props.Name .. " as its own parent") end
    if parent and info(parent).Destroyed then fail("Attempt to parent to a destroyed instance") end
    local old = data.Parent
    if old == parent then return end
    if old then
        local siblings = info(old).Children
        local index = table.find(siblings, instance)
        if index then table.remove(siblings, index) end
    end
    data.Parent = parent
    if parent then table.insert(info(parent).Children, instance) end
    signalFor(instance, "AncestryChanged"):Fire(instance, parent)
end

InstanceMeta.__index = function(instance, key)
    local data = info(instance)
    if Methods[key] then return Methods[key] end
    if key == "Parent" then return data.Parent end
    if key == "ClassName" then return data.ClassName end
    if key == "AbsoluteSize" or key == "AbsoluteWindowSize" or key == "AbsoluteCanvasSize" then
        if not isA(instance, "GuiBase2d") then fail(key .. " is not a valid member of " .. data.ClassName) end
        return absoluteSize(instance)
    end
    if key == "AbsolutePosition" then return absolutePosition(instance) end
    if data.ClassName == "Service" or data.ClassName == "Player" or data.ClassName == "PlayerGui" then
        if data.Props[key] ~= nil then return data.Props[key] end
        if data.Extra and data.Extra[key] ~= nil then return data.Extra[key] end
        if data.Signals[key] then return data.Signals[key] end
    end
    local kind = memberOf(data.ClassName, key)
    if kind == "prop" then return data.Props[key] end
    if kind == "event" then return signalFor(instance, key) end
    for _, child in ipairs(data.Children) do if info(child).Props.Name == key then return child end end
    fail(tostring(key) .. " is not a valid member of " .. data.ClassName .. " \"" .. tostring(data.Props.Name) .. "\"")
end
InstanceMeta.__newindex = function(instance, key, value)
    local data = info(instance)
    if key == "Parent" then setParent(instance, value); return end
    local kind, group = memberOf(data.ClassName, key)
    if kind ~= "prop" then fail(tostring(key) .. " is not a valid member of " .. data.ClassName) end
    if group.readonly and group.readonly[key] then fail("Unable to assign property " .. key .. ". Property is read only") end
    local expected = group.types and group.types[key]
    if expected and typeof(value) ~= expected and not (expected == "string" and type(value) == "number") then
        fail("Unable to assign property " .. key .. ". " .. expected .. " expected, got " .. typeof(value))
    end
    if expected == "string" and type(value) == "number" then value = tostring(value) end
    if key == "Font" then
        if value.EnumType ~= "Font" then fail("Font expects Enum.Font") end
    end
    local old = data.Props[key]
    data.Props[key] = value
    if old ~= value then
        local propSignal = data.PropSignals[key]
        if propSignal then propSignal:Fire() end
        local changed = data.Signals.Changed
        if changed then changed:Fire(key) end
    end
end
InstanceMeta.__tostring = function(instance) return tostring(info(instance).Props.Name) end

function Methods.IsA(instance, className) return isA(instance, className) end
function Methods.FindFirstChild(instance, name)
    for _, child in ipairs(info(instance).Children) do if info(child).Props.Name == name then return child end end
    return nil
end
function Methods.FindFirstChildOfClass(instance, className)
    for _, child in ipairs(info(instance).Children) do if info(child).ClassName == className then return child end end
    return nil
end
function Methods.FindFirstChildWhichIsA(instance, className)
    for _, child in ipairs(info(instance).Children) do if isA(child, className) then return child end end
    return nil
end
function Methods.WaitForChild(instance, name) return Methods.FindFirstChild(instance, name) end
function Methods.GetChildren(instance) return table.clone(info(instance).Children) end
function Methods.GetDescendants(instance)
    local result = {}
    local function walk(item) for _, child in ipairs(info(item).Children) do table.insert(result, child); walk(child) end end
    walk(instance)
    return result
end
function Methods.IsDescendantOf(instance, ancestor)
    local parent = info(instance).Parent
    while parent do if parent == ancestor then return true end; parent = info(parent).Parent end
    return false
end
function Methods.GetPropertyChangedSignal(instance, prop)
    local data = info(instance)
    local known = prop == "AbsoluteSize" or prop == "AbsolutePosition" or memberOf(data.ClassName, prop) == "prop"
    if not known then fail(tostring(prop) .. " is not a valid property name.") end
    data.PropSignals[prop] = data.PropSignals[prop] or signal(prop)
    return data.PropSignals[prop]
end
function Methods.Destroy(instance)
    local data = info(instance)
    if data.Destroyed then return end
    signalFor(instance, "Destroying"):Fire()
    for _, child in ipairs(table.clone(data.Children)) do Methods.Destroy(child) end
    if data.Parent then
        local siblings = info(data.Parent).Children
        local index = table.find(siblings, instance)
        if index then table.remove(siblings, index) end
    end
    data.Parent = nil
    data.Destroyed = true
    for _, item in pairs(data.Signals) do item:DisconnectAll() end
    for _, item in pairs(data.PropSignals) do item:DisconnectAll() end
end
function Methods.ClearAllChildren(instance) for _, child in ipairs(table.clone(info(instance).Children)) do Methods.Destroy(child) end end
function Methods.GetAttribute(instance, name) return info(instance).Attributes[name] end
function Methods.SetAttribute(instance, name, value) info(instance).Attributes[name] = value end
function Methods.GetFullName(instance)
    local names, item = {}, instance
    while item do table.insert(names, 1, tostring(info(item).Props.Name)); item = info(item).Parent end
    return table.concat(names, ".")
end
function Methods.CaptureFocus(instance)
    if info(instance).ClassName ~= "TextBox" then fail("CaptureFocus is not a valid member") end
    Mock.Focused = instance
    signalFor(instance, "Focused"):Fire()
end
function Methods.ReleaseFocus(instance, submitted)
    if Mock.Focused == instance then Mock.Focused = nil end
    signalFor(instance, "FocusLost"):Fire(submitted == true)
end
function Methods.GetBoundingBox(instance)
    if not isA(instance, "Model") then fail("GetBoundingBox is not a valid member") end
    return CFrame.new(0, 3, 0), Vector3.new(4, 6, 2)
end
function Methods.Clone(instance)
    local data = info(instance)
    local copy = newInstance(data.ClassName, true)
    for key, value in pairs(data.Props) do info(copy).Props[key] = value end
    for _, child in ipairs(data.Children) do Methods.Clone(child).Parent = copy end
    return copy
end

local Instance = {new = function(className, parent)
    local instance = newInstance(className)
    if parent ~= nil then instance.Parent = parent end
    return instance
end}
Mock.newInstance = newInstance
Mock.info = info
Mock.signalFor = signalFor

-- -----------------------------------------------------------------------------
-- Services, player and executor functions
-- -----------------------------------------------------------------------------
local services = {}
local function service(name, extra, signals)
    local instance = newInstance("Service", true)
    local data = info(instance)
    data.Props.Name = name
    data.Extra = extra or {}
    for _, signalName in ipairs(signals or {}) do data.Signals[signalName] = signal(signalName) end
    services[name] = instance
    return instance
end

local function jsonEncode(value)
    local kind = type(value)
    if kind == "nil" then return "null" end
    if kind == "boolean" then return tostring(value) end
    if kind == "number" then
        if value ~= value or value == math.huge or value == -math.huge then error("JSON cannot encode NaN or infinity") end
        if math.floor(value) == value and math.abs(value) < 1e15 then return string.format("%d", value) end
        return string.format("%.14g", value)
    end
    if kind == "string" then
        local map = {['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t"}
        return '"' .. value:gsub('[%c"\\]', function(c) return map[c] or string.format("\\u%04x", c:byte()) end) .. '"'
    end
    if kind == "table" then
        if next(value) == nil then return "[]" end
        if #value > 0 then
            local parts = {}
            for _, item in ipairs(value) do table.insert(parts, jsonEncode(item)) end
            return "[" .. table.concat(parts, ",") .. "]"
        end
        local keys = {}
        for key in pairs(value) do
            if type(key) ~= "string" then error("JSON object keys must be strings") end
            table.insert(keys, key)
        end
        table.sort(keys)
        local parts = {}
        for _, key in ipairs(keys) do table.insert(parts, jsonEncode(key) .. ":" .. jsonEncode(value[key])) end
        return "{" .. table.concat(parts, ",") .. "}"
    end
    error("JSON cannot encode a " .. typeof(value))
end
local function jsonDecode(text)
    local position = 1
    local function skip() position = text:find("[^%s]", position) or #text + 1 end
    local parseValue
    local function parseString()
        local result, i = {}, position + 1
        while true do
            local c = text:sub(i, i)
            if c == "" then error("unterminated string") end
            if c == '"' then position = i + 1; return table.concat(result) end
            if c == "\\" then
                local n = text:sub(i + 1, i + 1)
                local map = {n = "\n", r = "\r", t = "\t", ['"'] = '"', ["\\"] = "\\", ["/"] = "/", b = "\b", f = "\f"}
                if n == "u" then table.insert(result, utf8.char(tonumber(text:sub(i + 2, i + 5), 16))); i = i + 6
                else table.insert(result, map[n] or n); i = i + 2 end
            else
                table.insert(result, c); i = i + 1
            end
        end
    end
    function parseValue()
        skip()
        local c = text:sub(position, position)
        if c == "{" then
            local result = {}
            position = position + 1; skip()
            if text:sub(position, position) == "}" then position = position + 1; return result end
            while true do
                skip()
                local key = parseString()
                skip()
                if text:sub(position, position) ~= ":" then error("expected ':' at " .. position) end
                position = position + 1
                result[key] = parseValue()
                skip()
                local d = text:sub(position, position)
                position = position + 1
                if d == "}" then return result end
                if d ~= "," then error("expected ',' or '}' at " .. position) end
            end
        elseif c == "[" then
            local result = {}
            position = position + 1; skip()
            if text:sub(position, position) == "]" then position = position + 1; return result end
            while true do
                table.insert(result, parseValue())
                skip()
                local d = text:sub(position, position)
                position = position + 1
                if d == "]" then return result end
                if d ~= "," then error("expected ',' or ']' at " .. position) end
            end
        elseif c == '"' then return parseString()
        elseif text:sub(position, position + 3) == "true" then position = position + 4; return true
        elseif text:sub(position, position + 4) == "false" then position = position + 5; return false
        elseif text:sub(position, position + 3) == "null" then position = position + 4; return nil
        else
            local literal = text:match("^-?%d+%.?%d*[eE]?[-+]?%d*", position)
            if not literal or literal == "" then error("unexpected character at " .. position) end
            position = position + #literal
            return tonumber(literal)
        end
    end
    local result = parseValue()
    skip()
    if position <= #text then error("trailing characters in JSON") end
    return result
end

local playerGui = newInstance("PlayerGui", true)
info(playerGui).Props.Name = "PlayerGui"
local player = newInstance("Player", true)
info(player).Props.Name = "LyraTester"
info(player).Props.UserId = 1
info(player).Props.DisplayName = "Lyra Tester"
playerGui.Parent = player
local camera = newInstance("Camera", true)
local workspaceService = service("Workspace", {CurrentCamera = camera})

service("Players", {LocalPlayer = player, GetPlayers = function() return {player} end}, {"PlayerAdded", "PlayerRemoving"})
service("RunService", nil, {"RenderStepped", "Heartbeat", "Stepped"})
local inputService = service("UserInputService", {KeyboardEnabled = true, TouchEnabled = false, MouseEnabled = true,
    GetFocusedTextBox = function() return Mock.Focused end}, {"InputBegan", "InputChanged", "InputEnded"})
service("GuiService", nil, {"MenuOpened", "MenuClosed"})
service("Lighting")
service("TextService", {GetTextSize = function(_, text, size, font, frame)
    expect(font, "EnumItem", "TextService:GetTextSize font")
    expect(frame, "Vector2", "TextService:GetTextSize frameSize")
    local width = #tostring(text) * size * 0.52
    local lines = math.max(1, math.ceil(width / math.max(1, frame.X)))
    return Vector2.new(math.min(width, frame.X), lines * size * 1.2)
end})
service("HttpService", {
    JSONEncode = function(_, value) return jsonEncode(value) end,
    JSONDecode = function(_, text) return jsonDecode(text) end,
    GenerateGUID = function() sequence = sequence + 1; return "GUID-" .. sequence end,
})
local tweens = service("TweenService", {Create = function(_, instance, tweenInfo, goal)
    expect(instance, "Instance", "TweenService:Create")
    expect(tweenInfo, "TweenInfo", "TweenService:Create")
    for key, value in pairs(goal) do
        local current = instance[key]
        if typeof(current) ~= typeof(value) then fail("TweenService:Create property " .. key .. " expects " .. typeof(current) .. ", got " .. typeof(value)) end
    end
    local tween = {Completed = signal("Completed"), PlaybackState = Enum.PlaybackState.Begin}
    local thread
    function tween.Play(self)
        self.PlaybackState = Enum.PlaybackState.Playing
        thread = task.delay(tweenInfo.Time, function()
            if info(instance).Destroyed then return end
            for key, value in pairs(goal) do instance[key] = value end
            self.PlaybackState = Enum.PlaybackState.Completed
            self.Completed:Fire(Enum.PlaybackState.Completed)
        end)
    end
    function tween.Cancel(self)
        if thread then task.cancel(thread); thread = nil end
        if self.PlaybackState == Enum.PlaybackState.Playing then
            self.PlaybackState = Enum.PlaybackState.Cancelled
            self.Completed:Fire(Enum.PlaybackState.Cancelled)
        end
    end
    return setmetatable(tween, {__type = "Instance"})
end})
local chatService = service("TextChatService", {
    CanUserChatAsync = function() task.wait(0.2); return true end,
}, {"MessageReceived"})
local commands = newInstance("Folder", true)
commands.Name = "TextChatCommands"
info(commands).Parent = chatService
table.insert(info(chatService).Children, commands)
local emote = newInstance("TextChatCommand", true)
emote.Name = "RBXEmoteCommand"
emote.Parent = commands
service("CoreGui")

local game = setmetatable({}, {__index = function(_, key)
    if key == "GetService" then
        return function(_, name)
            local found = services[name]
            if not found then fail("'" .. tostring(name) .. "' is not a valid Service name") end
            return found
        end
    end
    if key == "HttpGet" then return function(_, url) return "-- source of " .. tostring(url) end end
    if key == "PlaceId" then return 1 end
    fail(tostring(key) .. " is not a valid member of DataModel")
end, __type = "Instance"})
local workspace = workspaceService

local function warn(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
    table.insert(Mock.Warnings, table.concat(parts, " "))
end
local genv = {}
local function getgenv() return genv end
local function writefile(path, data) assert(type(data) == "string", "writefile expects a string"); Mock.Files[path] = data end
local function readfile(path) local data = Mock.Files[path]; if not data then error("file not found: " .. path) end; return data end
local function isfile(path) return Mock.Files[path] ~= nil end
local function isfolder(path) return Mock.Files[path .. "/"] ~= nil end
local function makefolder(path) Mock.Files[path .. "/"] = "" end
local function getcustomasset(path) assert(Mock.Files[path], "getcustomasset: no file " .. path); return "rbxasset://custom/" .. path end
local function setclipboard(text) Mock.Clipboard = text end
local function loadstring(source)
    return function() return Mock.Module end
end

-- -----------------------------------------------------------------------------
-- Test helpers: input simulation and queries.
-- -----------------------------------------------------------------------------
local function inputObject(kind, position, keyCode)
    return setmetatable({UserInputType = Enum.UserInputType[kind], Position = position or Vector3.new(), KeyCode = keyCode or Enum.KeyCode.Unknown,
        UserInputState = Enum.UserInputState.Begin, Delta = Vector3.new()}, {__type = "Instance"})
end
Mock.input = inputObject
function Mock.click(button)
    local data = info(button)
    assert(isA(button, "GuiButton"), "Mock.click needs a GuiButton, got " .. data.ClassName)
    assert(not data.Destroyed, "Mock.click on a destroyed button")
    local center = button.AbsolutePosition + button.AbsoluteSize / 2
    local input = inputObject("MouseButton1", Vector3.new(center.X, center.Y, 0))
    signalFor(button, "MouseEnter"):Fire()
    signalFor(button, "InputBegan"):Fire(input)
    signalFor(button, "InputEnded"):Fire(input)
    signalFor(button, "Activated"):Fire(input, 1)
    signalFor(button, "MouseLeave"):Fire()
end
function Mock.key(name, processed)
    local input = inputObject("Keyboard", nil, Enum.KeyCode[name])
    inputService.InputBegan:Fire(input, processed == true)
    inputService.InputEnded:Fire(input, processed == true)
end
-- Presses on target, moves by the given steps and releases.
function Mock.drag(target, from, to, steps, touch)
    local kind = touch and "Touch" or "MouseButton1"
    local input = inputObject(kind, Vector3.new(from.X, from.Y, 0))
    signalFor(target, "InputBegan"):Fire(input)
    steps = steps or 4
    for i = 1, steps do
        local point = from + (to - from) * (i / steps)
        local move = touch and input or inputObject("MouseMovement", Vector3.new(point.X, point.Y, 0))
        if touch then input.Position = Vector3.new(point.X, point.Y, 0) end
        inputService.InputChanged:Fire(move)
    end
    local finish = touch and input or inputObject("MouseButton1", Vector3.new(to.X, to.Y, 0))
    inputService.InputEnded:Fire(finish)
end
function Mock.wheel(target, up)
    signalFor(target, "InputChanged"):Fire(inputObject("MouseWheel", Vector3.new(0, 0, up and 1 or -1)))
end
function Mock.type(box, text, enter)
    Methods.CaptureFocus(box)
    box.Text = text
    Methods.ReleaseFocus(box, enter)
end
function Mock.fireProperty(instance, prop)
    local data = info(instance)
    if data.PropSignals[prop] then data.PropSignals[prop]:Fire() end
end
-- First TextLabel/TextButton/TextBox under root whose Text matches (plain or as a Lua pattern).
function Mock.findText(root, text, plain)
    for _, item in ipairs(Methods.GetDescendants(root)) do
        local data = info(item)
        if (data.ClassName == "TextLabel" or data.ClassName == "TextButton" or data.ClassName == "TextBox") then
            local value = data.Props.Text
            if value == text or (not plain and type(value) == "string" and value:find(text)) then return item end
        end
    end
    return nil
end
-- The clickable button that holds a label with this text (the label's parent button, or the label itself).
function Mock.button(root, text)
    local label = Mock.findText(root, text, true)
    assert(label, "No element with text \"" .. tostring(text) .. "\"")
    if isA(label, "GuiButton") then return label end
    local parent = info(label).Parent
    while parent and not isA(parent, "GuiButton") do parent = info(parent).Parent end
    assert(parent, "Text \"" .. tostring(text) .. "\" is not inside a button")
    return parent
end
function Mock.count(root, className)
    local count = 0
    for _, item in ipairs(Methods.GetDescendants(root)) do if info(item).ClassName == className then count = count + 1 end end
    return count
end
Mock.Services = services
Mock.InputService = inputService
Mock.ChatService = chatService
Mock.EmoteCommand = emote
Mock.Player = player
Mock.PlayerGui = playerGui
