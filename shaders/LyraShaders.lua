--[[
    LYRA SHADERS  ·  v1.0.0
    Client-side shaders for Roblox, with a Lyra UI panel: colour grading, LUTs, ambient occlusion,
    real-time reflections, global illumination, depth of field, eye adaptation, lens flares and more.

        loadstring(game:HttpGet("https://raw.githubusercontent.com/lyraEz/Library-UI/main/shaders/LyraShaders.lua"))()

    Everything runs on this device only: other players never see the effects, and turning the engine
    off (or unloading it) puts the game's own lighting back the way the game has it.

    Roblox does not let scripts run pixel shaders, so every effect is rebuilt from what the engine
    exposes: post-processing effects, lighting properties, ViewportFrames, surface overlays, highlights
    and lights. shaders/README.md explains how each effect works and where its limits are.
]]

local VERSION = "1.0.0"
local LYRA_URL = "https://raw.githubusercontent.com/lyraEz/Library-UI/main/src/Lyra.lua"
local TAG = "LyraShaders"

-- Running the script again replaces the previous copy instead of stacking a second one.
local Genv = (type(getgenv) == "function" and getgenv()) or _G
if type(Genv.LyraShaders) == "table" and type(Genv.LyraShaders.Unload) == "function" then
    pcall(Genv.LyraShaders.Unload)
end

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")
local HttpService = game:GetService("HttpService")

local LocalPlayer = Players.LocalPlayer
while not LocalPlayer do
    Players:GetPropertyChangedSignal("LocalPlayer"):Wait()
    LocalPlayer = Players.LocalPlayer
end

-- =============================================================================
-- SMALL HELPERS
-- =============================================================================
local WHITE, BLACK = Color3.new(1, 1, 1), Color3.new(0, 0, 0)
local UP = Vector3.new(0, 1, 0)

local function clamp(x, low, high)
    if x < low then return low elseif x > high then return high end
    return x
end
local function lerp(a, b, t) return a + (b - a) * t end
-- Frame-rate independent smoothing toward a target.
local function approach(current, target, rate, dt) return current + (target - current) * (1 - math.exp(-rate * dt)) end
local function luminance(c) return 0.2126 * c.R + 0.7152 * c.G + 0.0722 * c.B end
local function rgb(r, g, b) return Color3.new(clamp(r, 0, 1), clamp(g, 0, 1), clamp(b, 0, 1)) end
local function scaleColor(c, k) return rgb(c.R * k, c.G * k, c.B * k) end
local function addColor(a, b, k) k = k or 1; return rgb(a.R + b.R * k, a.G + b.G * k, a.B + b.B * k) end
local function mulColor(a, b) return rgb(a.R * b.R, a.G * b.G, a.B * b.B) end
local function lerpColor(a, b, t) return a:Lerp(b, clamp(t, 0, 1)) end
local function saturateColor(c, amount)
    local l = luminance(c)
    return rgb(l + (c.R - l) * amount, l + (c.G - l) * amount, l + (c.B - l) * amount)
end
local function hueColor(hue, saturation, value) return Color3.fromHSV((hue % 360) / 360, clamp(saturation, 0, 1), clamp(value, 0, 1)) end

-- Black-body colour of a light at the given temperature (Tanner Helland's fit), 0-1 per channel.
local function kelvinColor(kelvin)
    local t = clamp(kelvin, 1000, 40000) / 100
    local r, g, b
    if t <= 66 then
        r = 255
        g = 99.4708025861 * math.log(t) - 161.1195681661
    else
        r = 329.698727446 * (t - 60) ^ -0.1332047592
        g = 288.1221695283 * (t - 60) ^ -0.0755148492
    end
    if t >= 66 then b = 255 elseif t <= 19 then b = 0 else b = 138.5177312231 * math.log(t - 10) - 305.0447927307 end
    return rgb(r / 255, g / 255, b / 255)
end
-- White balance as a tint multiplier. Higher temperatures look warmer, like a camera's temperature slider;
-- tint moves between green (negative) and magenta (positive). Returns the tint and a brightness compensation.
local function whiteBalance(temperature, tint)
    local light = kelvinColor(6500 * 6500 / clamp(temperature, 1500, 15000))
    local reference = kelvinColor(6500)
    local r, g, b = light.R / reference.R, light.G / reference.G, light.B / reference.B
    g = g * (1 - clamp(tint, -100, 100) / 100 * 0.22)
    local top = math.max(r, g, b, 1e-3)
    local color = rgb(r / top, g / top, b / top)
    return color, (1 - luminance(color)) * 0.35
end

local function safeSet(inst, property, value)
    return (pcall(function() inst[property] = value end))
end
local function safeGet(inst, property)
    local ok, value = pcall(function() return inst[property] end)
    if ok then return value end
    return nil
end
local function alive(inst) return typeof(inst) == "Instance" and inst.Parent ~= nil end
local function new(class, props, parent)
    local inst = Instance.new(class)
    for key, value in pairs(props or {}) do inst[key] = value end
    if parent then inst.Parent = parent end
    return inst
end
local function tryNew(class)
    local ok, inst = pcall(Instance.new, class)
    if ok then return inst end
    return nil
end
local function enumItem(enum, name)
    local ok, item = pcall(function() return Enum[enum][name] end)
    if ok then return item end
    return nil
end
local function formatNumber(value, digits)
    return string.format("%." .. (digits or 0) .. "f", value)
end

-- Executor file access. Every call is guarded: without these functions the script runs without saving.
local Files = {}
function Files.read(path)
    if type(readfile) ~= "function" then return nil end
    if type(isfile) == "function" then
        local ok, exists = pcall(isfile, path)
        if not ok or not exists then return nil end
    end
    local ok, data = pcall(readfile, path)
    if ok and type(data) == "string" then return data end
    return nil
end
function Files.folder(path)
    if type(makefolder) ~= "function" then return false end
    if type(isfolder) == "function" then
        local ok, exists = pcall(isfolder, path)
        if ok and exists then return true end
    end
    return (pcall(makefolder, path))
end
function Files.list(path)
    if type(listfiles) ~= "function" then return {} end
    local ok, items = pcall(listfiles, path)
    if ok and type(items) == "table" then return items end
    return {}
end
function Files.fetch(url)
    local ok, body = pcall(function() return game:HttpGet(url) end)
    if ok and type(body) == "string" then return body end
    local requester = (type(request) == "function" and request) or (type(http_request) == "function" and http_request) or nil
    if requester then
        local okRequest, response = pcall(requester, {Url = url, Method = "GET"})
        if okRequest and type(response) == "table" and response.Body then return response.Body end
    end
    return nil
end

-- Where screen overlays live: the executor's hidden container when there is one.
local function guiParent()
    if type(gethui) == "function" then
        local ok, hui = pcall(gethui)
        if ok and typeof(hui) == "Instance" then return hui end
    end
    local ok, core = pcall(function() return game:GetService("CoreGui") end)
    if ok and core then
        local okTest = pcall(function() local probe = Instance.new("Folder"); probe.Parent = core; probe:Destroy() end)
        if okTest then return core end
    end
    return LocalPlayer:FindFirstChildOfClass("PlayerGui") or LocalPlayer:WaitForChild("PlayerGui", 10)
end

-- =============================================================================
-- PROPERTY OVERRIDES
-- Effects never overwrite a game property for good. Each one registers a modifier (value -> value) on a
-- property; every frame the engine works out what the game set (its "base"), runs the modifiers on top
-- and writes the result. When the game changes the property itself (a day/night cycle, a cutscene), the
-- new value becomes the base. When the last modifier goes, the base is written back.
-- =============================================================================
local Props = {Records = {}, ByInst = setmetatable({}, {__mode = "k"})}

local function sameValue(a, b)
    local kind = typeof(a)
    if kind ~= typeof(b) then return false end
    if kind == "number" then return math.abs(a - b) <= 1e-3 * math.max(1, math.abs(a)) end
    if kind == "Color3" then return math.abs(a.R - b.R) < 2e-3 and math.abs(a.G - b.G) < 2e-3 and math.abs(a.B - b.B) < 2e-3 end
    return a == b
end

function Props.record(inst, property)
    local map = Props.ByInst[inst]
    if not map then
        map = {}
        Props.ByInst[inst] = map
    end
    local rec = map[property]
    if not rec then
        local ok, value = pcall(function() return inst[property] end)
        if not ok then return nil end
        rec = {Inst = inst, Prop = property, Base = value, Written = nil, Mods = {}, Count = 0}
        map[property] = rec
        table.insert(Props.Records, rec)
    end
    return rec
end
-- owner: any key (an effect id); order: lower runs first; fn(value) returns the new value.
function Props.set(inst, property, owner, order, fn)
    local rec = Props.record(inst, property)
    if not rec then return false end
    if not rec.Mods[owner] then rec.Count = rec.Count + 1 end
    rec.Mods[owner] = {Order = order or 0, Fn = fn}
    rec.Sorted = nil
    return true
end
function Props.clear(inst, property, owner)
    local map = Props.ByInst[inst]
    local rec = map and map[property]
    if rec and rec.Mods[owner] then
        rec.Mods[owner] = nil
        rec.Count = rec.Count - 1
        rec.Sorted = nil
    end
end
function Props.clearOwner(owner)
    for _, rec in ipairs(Props.Records) do
        if rec.Mods[owner] then
            rec.Mods[owner] = nil
            rec.Count = rec.Count - 1
            rec.Sorted = nil
        end
    end
end
function Props.base(inst, property)
    local map = Props.ByInst[inst]
    local rec = map and map[property]
    if rec then return rec.Base end
    return safeGet(inst, property)
end
local function sortedMods(rec)
    if rec.Sorted then return rec.Sorted end
    local list = {}
    for _, mod in pairs(rec.Mods) do table.insert(list, mod) end
    table.sort(list, function(a, b) return a.Order < b.Order end)
    rec.Sorted = list
    return list
end
local function dropRecord(index, rec)
    table.remove(Props.Records, index)
    local map = Props.ByInst[rec.Inst]
    if map then map[rec.Prop] = nil end
end
function Props.update()
    for index = #Props.Records, 1, -1 do
        local rec = Props.Records[index]
        local inst = rec.Inst
        if inst ~= Lighting and inst.Parent == nil then
            dropRecord(index, rec)
        else
            local ok, current = pcall(function() return inst[rec.Prop] end)
            if ok then
                if rec.Written == nil or not sameValue(current, rec.Written) then rec.Base = current end
                if rec.Count <= 0 then
                    if rec.Written ~= nil and sameValue(current, rec.Written) then safeSet(inst, rec.Prop, rec.Base) end
                    dropRecord(index, rec)
                else
                    local value = rec.Base
                    for _, mod in ipairs(sortedMods(rec)) do
                        local okMod, result = pcall(mod.Fn, value)
                        if okMod and result ~= nil then value = result end
                    end
                    if not sameValue(value, current) then safeSet(inst, rec.Prop, value) end
                    rec.Written = safeGet(inst, rec.Prop)
                end
            end
        end
    end
end
-- Puts every touched property back to the game's value.
function Props.restoreAll()
    for index = #Props.Records, 1, -1 do
        local rec = Props.Records[index]
        if rec.Written ~= nil and (rec.Inst == Lighting or rec.Inst.Parent ~= nil) then
            -- Only when the value is still ours: a value the game set since is left alone.
            if sameValue(safeGet(rec.Inst, rec.Prop), rec.Written) then safeSet(rec.Inst, rec.Prop, rec.Base) end
        end
        dropRecord(index, rec)
    end
end

-- =============================================================================
-- OWN INSTANCES
-- Post-processing effects live in Lighting under one name each; world helpers (reflection planes, shadow
-- cards, lights) live in one folder inside the camera, so they are never replicated or saved, and they
-- are invisible to raycasts and touches (CanQuery, CanTouch and CanCollide are off).
-- =============================================================================
local Slots = {}
local function slot(name, class)
    local inst = Slots[name]
    if inst and inst.Parent == Lighting then return inst end
    if inst then pcall(function() inst:Destroy() end) end
    local created = tryNew(class)
    if not created then
        Slots[name] = nil
        return nil
    end
    created.Name = TAG .. "_" .. name
    created.Parent = Lighting
    Slots[name] = created
    return created
end
local function slotAlive(name) local inst = Slots[name]; return inst ~= nil and inst.Parent == Lighting end
local function dropSlot(name)
    local inst = Slots[name]
    Slots[name] = nil
    if inst then pcall(function() inst:Destroy() end) end
end
local function isOwn(inst)
    if typeof(inst) ~= "Instance" then return false end
    for _, own in pairs(Slots) do if own == inst then return true end end
    return inst.Name:sub(1, #TAG) == TAG or inst.Name:sub(1, 7) == "LyraUI_"
end

local World = {}
function World.root()
    local camera = Workspace.CurrentCamera
    local folder = World.Folder
    -- A destroyed folder (the camera was replaced) cannot be parented again: start a new one.
    if folder and folder.Parent ~= camera and not pcall(function() folder.Parent = camera end) then folder = nil end
    if not folder then
        folder = new("Folder", {Name = TAG})
        folder.Parent = camera
        World.Folder = folder
        World.Anchor = nil
    end
    return folder
end
function World.child(name)
    local root = World.root()
    local folder = root:FindFirstChild(name)
    if not folder then folder = new("Folder", {Name = name}, root) end
    return folder
end
-- An invisible part that only exists to carry a SurfaceGui, lights or attachments.
function World.part(props, parent)
    local part = new("Part", {Anchored = true, CanCollide = false, CanTouch = false, CanQuery = false, CastShadow = false, Massless = true,
        Transparency = 1, Locked = true, Material = Enum.Material.SmoothPlastic})
    for key, value in pairs(props or {}) do part[key] = value end
    part.Parent = parent or World.root()
    return part
end
-- One anchor part at the origin holds every helper attachment (lights, flare sources).
function World.attachment(name)
    if not alive(World.Anchor) then
        World.Anchor = World.part({Name = "Anchor", Size = Vector3.new(0.05, 0.05, 0.05), CFrame = CFrame.new()})
    end
    return new("Attachment", {Name = name or "Point"}, World.Anchor)
end

local Overlay = {}
function Overlay.gui()
    if alive(Overlay.Gui) then return Overlay.Gui end
    Overlay.Gui = new("ScreenGui", {Name = TAG .. "_Overlay", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = -50,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling}, guiParent())
    return Overlay.Gui
end
function Overlay.layer(name, zindex)
    local gui = Overlay.gui()
    local layer = gui:FindFirstChild(name)
    if not layer then
        layer = new("Frame", {Name = name, Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = zindex or 1,
            ClipsDescendants = true}, gui)
    end
    return layer
end
function Overlay.drop(name)
    local gui = Overlay.Gui
    local layer = gui and gui:FindFirstChild(name)
    if layer then layer:Destroy() end
end

-- =============================================================================
-- SCENE
-- Shared per-frame facts: camera, sun, the player's character, every character nearby and the
-- raycast filters that skip them.
-- =============================================================================
local Scene = {Eye = Vector3.zero, Look = Vector3.new(0, 0, -1), Sun = UP, Day = 1, SunPower = 1, Focus = Vector3.zero,
    Characters = {}, CharacterSet = {}, NextCharacters = 0, Rays = 0, RayWindow = 0, RaysPerSecond = 0}

local function newRaycastParams(list)
    local params = RaycastParams.new()
    params.FilterType = enumItem("RaycastFilterType", "Exclude") or Enum.RaycastFilterType.Blacklist
    params.FilterDescendantsInstances = list or {}
    params.IgnoreWater = false
    return params
end
Scene.WorldParams = newRaycastParams()  -- skips our helpers and every character
Scene.SolidParams = newRaycastParams()  -- skips our helpers and the local character
Scene.WaterParams = newRaycastParams()

local function characterRoot(model)
    return model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart or model:FindFirstChild("Torso") or model:FindFirstChild("Head")
end

function Scene.refreshCharacters()
    local list, set = {}, {}
    for _, player in ipairs(Players:GetPlayers()) do
        local model = player.Character
        local root = model and characterRoot(model)
        if root then
            local humanoid = model:FindFirstChildOfClass("Humanoid")
            table.insert(list, {Model = model, Root = root, Humanoid = humanoid, Player = player, Local = player == LocalPlayer})
            set[model] = true
        end
    end
    Scene.Characters, Scene.CharacterSet = list, set
    local exclude = {World.root()}
    for model in pairs(set) do table.insert(exclude, model) end
    Scene.WorldParams.FilterDescendantsInstances = exclude
    local solid = {World.root()}
    if LocalPlayer.Character then table.insert(solid, LocalPlayer.Character) end
    Scene.SolidParams.FilterDescendantsInstances = solid
    Scene.WaterParams.FilterDescendantsInstances = exclude
end

-- Models with a Humanoid that no player owns, found around a point (used when NPCs are included).
function Scene.npcsNear(position, radius, limit)
    local found, seen = {}, {}
    local params = OverlapParams.new()
    params.FilterType = enumItem("RaycastFilterType", "Exclude") or Enum.RaycastFilterType.Blacklist
    params.FilterDescendantsInstances = {World.root()}
    pcall(function() params.MaxParts = 600 end)
    local ok, parts = pcall(function() return Workspace:GetPartBoundsInRadius(position, radius, params) end)
    if not ok then return found end
    for _, part in ipairs(parts) do
        local model = part.Parent
        if model and model:IsA("Model") and not seen[model] and not Scene.CharacterSet[model] then
            seen[model] = true
            local humanoid = model:FindFirstChildOfClass("Humanoid")
            local root = humanoid and characterRoot(model)
            if root and humanoid.Health > 0 then
                table.insert(found, {Model = model, Root = root, Humanoid = humanoid, Npc = true})
                if #found >= (limit or 12) then break end
            end
        end
    end
    return found
end

function Scene.update(now)
    local camera = Workspace.CurrentCamera
    Scene.Camera = camera
    if camera then
        local frame = camera.CFrame
        Scene.CFrame = frame
        Scene.Eye = frame.Position
        Scene.Look = frame.LookVector
        Scene.Viewport = camera.ViewportSize
        Scene.FieldOfView = camera.FieldOfView
    end
    local okSun, sun = pcall(function() return Lighting:GetSunDirection() end)
    Scene.Sun = okSun and sun or UP
    Scene.Day = clamp((Scene.Sun.Y + 0.06) * 5, 0, 1)
    Scene.SunPower = Scene.Day * clamp((tonumber(Lighting.Brightness) or 2) / 2, 0, 3)
    local warm = 1 - clamp(Scene.Sun.Y * 3.5, 0, 1)
    Scene.SunColor = Color3.new(1, 0.97, 0.92):Lerp(Color3.new(1, 0.62, 0.36), warm)
    local character = LocalPlayer.Character
    local root = character and characterRoot(character)
    Scene.Focus = root and root.Position or (Scene.Eye + Scene.Look * 12)
    if now >= Scene.NextCharacters then
        Scene.NextCharacters = now + 0.5
        Scene.refreshCharacters()
    end
    if now >= Scene.RayWindow then
        Scene.RaysPerSecond = Scene.Rays
        Scene.Rays = 0
        Scene.RayWindow = now + 1
    end
end

-- A raycast that looks through glass panes and invisible barriers (up to four of them).
function Scene.cast(origin, direction, params, keepTransparent)
    local length = direction.Magnitude
    if length < 1e-3 then return nil end
    local unit = direction / length
    for _ = 1, 4 do
        Scene.Rays = Scene.Rays + 1
        local result = Workspace:Raycast(origin, unit * length, params)
        if not result then return nil end
        local hit = result.Instance
        if keepTransparent or not hit:IsA("BasePart") or hit.Transparency < 0.9 then return result end
        local travelled = (result.Position - origin).Magnitude + 0.05
        length = length - travelled
        if length <= 0.1 then return nil end
        origin = result.Position + unit * 0.05
    end
    return nil
end

function Scene.skyColor()
    local sunY = Scene.Sun.Y
    local night = Color3.fromRGB(18, 24, 44)
    local dusk = Color3.fromRGB(235, 150, 96)
    local day = Color3.fromRGB(150, 192, 240)
    local color = night:Lerp(dusk, clamp((sunY + 0.12) * 6, 0, 1)):Lerp(day, clamp(sunY * 3, 0, 1))
    local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
    if atmosphere then color = color:Lerp(atmosphere.Color, 0.3 * clamp(atmosphere.Density * 2, 0, 1)) end
    return color
end

-- Colour of a surface a ray hit, and how much light reaches it (sun when unblocked, plus ambient).
function Scene.surfaceColor(hit)
    local part = hit.Instance
    if part:IsA("Terrain") then
        local ok, color = pcall(function() return part:GetMaterialColor(hit.Material) end)
        return ok and color or Color3.fromRGB(110, 120, 100), false
    end
    return part.Color, part.Material == Enum.Material.Neon
end
function Scene.radiance(hit, checkSun)
    local albedo, emissive = Scene.surfaceColor(hit)
    if emissive then return scaleColor(albedo, 1.6), 1.2 end
    local direct = 0
    local normal = hit.Normal
    local facing = normal:Dot(Scene.Sun)
    local outdoors = false
    if facing > 0 and Scene.SunPower > 0 and checkSun ~= false then
        local blocked = Scene.cast(hit.Position + normal * 0.15, Scene.Sun * 400, Scene.WorldParams)
        if not blocked then
            direct = facing * Scene.SunPower
            outdoors = true
        end
    end
    local ambient = outdoors and Props.base(Lighting, "OutdoorAmbient") or lerpColor(Props.base(Lighting, "Ambient"), Props.base(Lighting, "OutdoorAmbient"), 0.35)
    local light = addColor(scaleColor(ambient, 0.9), scaleColor(Scene.SunColor or WHITE, direct))
    local color = mulColor(albedo, light)
    return color, luminance(albedo) * (direct + luminance(ambient) * 0.9)
end

-- =============================================================================
-- PROBE
-- A light probe shared by Global Illumination, Ambient light and Exposure. A few rays per frame keep
-- two running averages: what the camera sees (for metering) and the light around the player (for bounce).
-- =============================================================================
local Probe = {Users = 0, ViewIndex = 0, EnvIndex = 0, ViewLum = 0.35, EnvColor = Color3.fromRGB(128, 128, 128), EnvLum = 0.3,
    Bright = {}, Grid = {}, Dirs = {}}
do
    -- Metering grid: 7 x 5 points, the centre ones weighted more.
    for row = 0, 4 do
        for col = 0, 6 do
            local x, y = (col + 0.5) / 7, (row + 0.5) / 5
            local weight = 1 + 2 * math.max(0, 1 - ((x - 0.5) ^ 2 + (y - 0.5) ^ 2) * 4)
            table.insert(Probe.Grid, {X = x, Y = y, W = weight, Centre = math.abs(x - 0.5) < 0.15 and math.abs(y - 0.5) < 0.2})
        end
    end
    -- Bounce directions: a Fibonacci sphere, biased to the horizon and the ground where bounce comes from.
    local count = 40
    for i = 0, count - 1 do
        local y = 1 - (i + 0.5) / count * 2
        local radius = math.sqrt(1 - y * y)
        local angle = i * 2.399963229728653
        table.insert(Probe.Dirs, Vector3.new(math.cos(angle) * radius, y * 0.8, math.sin(angle) * radius).Unit)
    end
end
Probe.ViewSamples, Probe.EnvSamples = {}, {}

function Probe.step(rays, metering, dt)
    if Probe.Users <= 0 or not Scene.Camera then return end
    local camera = Scene.Camera
    local viewport = Scene.Viewport or camera.ViewportSize
    local viewRays = math.max(1, math.floor(rays * 0.5))
    for _ = 1, viewRays do
        Probe.ViewIndex = Probe.ViewIndex % #Probe.Grid + 1
        local point = Probe.Grid[Probe.ViewIndex]
        local ray = camera:ViewportPointToRay(point.X * viewport.X, point.Y * viewport.Y)
        local hit = Scene.cast(ray.Origin, ray.Direction * 600, Scene.SolidParams)
        local lum
        if hit then
            local _, l = Scene.radiance(hit, true)
            lum = l
        else
            lum = luminance(Scene.skyColor()) * (0.35 + 0.9 * Scene.Day)
            local toSun = ray.Direction:Dot(Scene.Sun)
            if toSun > 0.995 then lum = lum + 2 * Scene.SunPower end
        end
        Probe.ViewSamples[Probe.ViewIndex] = {Lum = lum, W = point.W, Centre = point.Centre}
    end
    for _ = 1, math.max(1, rays - viewRays) do
        Probe.EnvIndex = Probe.EnvIndex % #Probe.Dirs + 1
        local direction = Probe.Dirs[Probe.EnvIndex]
        local origin = Scene.Focus + UP * 2.5
        local hit = Scene.cast(origin, direction * 70, Scene.WorldParams)
        local sample
        if hit then
            local color, lum = Scene.radiance(hit, true)
            local distance = (hit.Position - origin).Magnitude
            sample = {Color = color, Lum = lum, Hit = hit.Position, Normal = hit.Normal, Albedo = (Scene.surfaceColor(hit)), Distance = distance,
                Sunlit = lum > 0.25, Sky = false}
        else
            local sky = Scene.skyColor()
            sample = {Color = scaleColor(sky, 0.35 + 0.75 * Scene.Day), Lum = luminance(sky) * (0.3 + 0.7 * Scene.Day), Sky = true}
        end
        Probe.EnvSamples[Probe.EnvIndex] = sample
    end
    -- Averages.
    local logSum, weightSum, centreSum, centreCount = 0, 0, 0, 0
    for _, sample in pairs(Probe.ViewSamples) do
        local w = metering == "Average" and 1 or sample.W
        logSum = logSum + math.log(math.max(sample.Lum, 1e-3)) * w
        weightSum = weightSum + w
        if sample.Centre then centreSum = centreSum + sample.Lum; centreCount = centreCount + 1 end
    end
    if weightSum > 0 then
        local target = math.exp(logSum / weightSum)
        if metering == "Spot" and centreCount > 0 then target = centreSum / centreCount end
        Probe.ViewLum = approach(Probe.ViewLum, target, 4, dt)
    end
    local r, g, b, n, lumSum = 0, 0, 0, 0, 0
    for _, sample in pairs(Probe.EnvSamples) do
        r, g, b, n = r + sample.Color.R, g + sample.Color.G, b + sample.Color.B, n + 1
        lumSum = lumSum + sample.Lum
    end
    if n > 0 then
        local target = rgb(r / n, g / n, b / n)
        Probe.EnvColor = Probe.EnvColor:Lerp(target, clamp(dt * 2.5, 0, 1))
        Probe.EnvLum = approach(Probe.EnvLum, lumSum / n, 2.5, dt)
    end
end
-- The brightest sunlit spots around the player, at least `spacing` studs apart (bounce light sources).
function Probe.brightSpots(count, spacing)
    local list = {}
    for _, sample in pairs(Probe.EnvSamples) do
        if not sample.Sky and sample.Sunlit and sample.Distance and sample.Distance > 3 then table.insert(list, sample) end
    end
    table.sort(list, function(a, b) return a.Lum > b.Lum end)
    local picked = {}
    for _, sample in ipairs(list) do
        local far = true
        for _, other in ipairs(picked) do
            if (other.Hit - sample.Hit).Magnitude < spacing then far = false; break end
        end
        if far then
            table.insert(picked, sample)
            if #picked >= count then break end
        end
    end
    return picked
end

-- =============================================================================
-- EFFECTS
-- Each effect has an id, a list of parameters (they become the controls on its page and the saved
-- flags "fx.<id>.<key>"), and Start / Stop / Apply / Update functions. Apply runs when a parameter
-- changes; Update runs every frame while the effect is on.
-- =============================================================================
local FX, FXList = {}, {}
local Engine -- defined further down; effects read Engine.Quality and Engine.Load

local function defineEffect(def)
    def.Config = {}
    for _, param in ipairs(def.Params) do def.Config[param.Key] = param.Default end
    def.Enabled = def.Default == true
    def.Active = false
    def.Cost = 0
    def.Errors = 0
    def.Info = ""
    FX[def.Id] = def
    table.insert(FXList, def)
    return def
end

-- Quality caps: Engine.Quality picks a row, Engine.Load (0.35-1) shrinks it when auto quality kicks in.
local QUALITY = {
    Low = {Rays = 4, Surfaces = 1, Parts = 160, Pixels = 6, Canvas = 512, Rate = 20, Cards = 24, Lights = 2, Lamps = 2, Highlights = 6},
    Balanced = {Rays = 6, Surfaces = 2, Parts = 350, Pixels = 9, Canvas = 768, Rate = 30, Cards = 50, Lights = 4, Lamps = 4, Highlights = 10},
    High = {Rays = 10, Surfaces = 4, Parts = 700, Pixels = 13, Canvas = 1024, Rate = 60, Cards = 100, Lights = 6, Lamps = 6, Highlights = 16},
    Ultra = {Rays = 14, Surfaces = 6, Parts = 1200, Pixels = 18, Canvas = 1536, Rate = 60, Cards = 180, Lights = 8, Lamps = 8, Highlights = 24},
}
local function cap(key)
    local row = QUALITY[Engine and Engine.Quality or "Balanced"] or QUALITY.Balanced
    local value = row[key]
    if Engine and Engine.Load < 1 and key ~= "Pixels" then value = math.max(1, math.floor(value * Engine.Load + 0.5)) end
    return value
end

-- -----------------------------------------------------------------------------
-- Colour
-- -----------------------------------------------------------------------------
local TONES = {
    {Name = "Neutral"},
    {Name = "Filmic", Contrast = 0.12, Saturation = -0.06, Brightness = -0.01, Tint = Color3.new(1, 0.98, 0.95), Grade = "Default"},
    {Name = "Warm film", Contrast = 0.08, Saturation = 0.04, Brightness = 0.01, Tint = Color3.new(1, 0.93, 0.83)},
    {Name = "Cool", Contrast = 0.06, Saturation = -0.04, Tint = Color3.new(0.87, 0.94, 1)},
    {Name = "Teal & orange", Contrast = 0.16, Saturation = 0.12, Tint = Color3.new(1, 0.95, 0.9)},
    {Name = "Bleach bypass", Contrast = 0.32, Saturation = -0.45, Brightness = 0.02},
    {Name = "Vivid", Contrast = 0.14, Saturation = 0.35},
    {Name = "Noir", Contrast = 0.38, Saturation = -1, Brightness = -0.02},
    {Name = "Sepia", Contrast = 0.1, Saturation = -0.82, Tint = Color3.new(1, 0.88, 0.7)},
    {Name = "Retro", Contrast = 0.04, Saturation = -0.05, Grade = "Retro"},
}
local TONE_NAMES = {}
for _, tone in ipairs(TONES) do table.insert(TONE_NAMES, tone.Name) end
local function toneNamed(name)
    for _, tone in ipairs(TONES) do if tone.Name == name then return tone end end
    return TONES[1]
end

defineEffect({
    Id = "colour", Title = "Colour", Icon = "sliders-horizontal", Default = true,
    Description = "Grade, tone and white balance for the whole frame.",
    Notes = {"A colour correction layer sets brightness, contrast, saturation and a white-balance tint.",
        "Tones are ready-made grades; the strength slider blends them in. Retro and Filmic also use Roblox's tonemapper when the game supports it."},
    Params = {
        {Key = "Brightness", Title = "Brightness", Kind = "Slider", Min = -30, Max = 30, Default = 0, Suffix = "%"},
        {Key = "Contrast", Title = "Contrast", Kind = "Slider", Min = -50, Max = 100, Default = 10, Suffix = "%"},
        {Key = "Saturation", Title = "Saturation", Kind = "Slider", Min = -100, Max = 100, Default = 8, Suffix = "%"},
        {Key = "Temperature", Title = "Temperature", Description = "Higher is warmer. 6500 K is neutral.", Kind = "Slider", Min = 3000, Max = 11000, Step = 100, Default = 6600, Suffix = " K"},
        {Key = "Tint", Title = "Tint", Description = "Green to magenta.", Kind = "Slider", Min = -100, Max = 100, Default = 0},
        {Key = "Tone", Title = "Tone", Kind = "Dropdown", Options = TONE_NAMES, Default = "Filmic"},
        {Key = "ToneStrength", Title = "Tone strength", Kind = "Slider", Min = 0, Max = 100, Default = 70, Suffix = "%"},
    },
    Apply = function(self)
        local cfg = self.Config
        local tone = toneNamed(cfg.Tone)
        local s = cfg.ToneStrength / 100
        local balance, compensation = whiteBalance(cfg.Temperature, cfg.Tint)
        local cc = slot("Colour", "ColorCorrectionEffect")
        if cc then
            cc.Brightness = clamp(cfg.Brightness / 100 + (tone.Brightness or 0) * s + compensation, -1, 1)
            cc.Contrast = clamp(cfg.Contrast / 100 + (tone.Contrast or 0) * s, -1, 1)
            cc.Saturation = clamp(cfg.Saturation / 100 + (tone.Saturation or 0) * s, -1, 1)
            cc.TintColor = mulColor(balance, WHITE:Lerp(tone.Tint or WHITE, s))
            cc.Enabled = true
        end
        local preset = tone.Grade and s > 0.3 and enumItem("TonemapperPreset", tone.Grade)
        if preset then
            local grading = slot("Grading", "ColorGradingEffect")
            if grading then safeSet(grading, "TonemapperPreset", preset); safeSet(grading, "Enabled", true) end
        else
            dropSlot("Grading")
        end
        self.Info = tone.Name ~= "Neutral" and (tone.Name .. " tone") or "Neutral tone"
    end,
    Update = function(self) if not slotAlive("Colour") then self:Apply() end end,
    Stop = function() dropSlot("Colour"); dropSlot("Grading") end,
})

-- -----------------------------------------------------------------------------
-- LUT: .cube files (1D or 3D) and ReShade PNG strips, fitted to a colour correction layer.
-- -----------------------------------------------------------------------------
local Lut = {Cache = {}}

-- Inflate (RFC 1951), enough for PNG image data.
local band, bor, lshift, rshift = bit32.band, bit32.bor, bit32.lshift, bit32.rshift
local LEN_BASE = {3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258}
local LEN_EXTRA = {0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0}
local DIST_BASE = {1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145,
    8193, 12289, 16385, 24577}
local DIST_EXTRA = {0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13}
local CLEN_ORDER = {16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15}

local function huffman(lengths, count)
    local maxBits, counts = 0, {}
    for symbol = 0, count - 1 do
        local length = lengths[symbol] or 0
        if length > 0 then
            counts[length] = (counts[length] or 0) + 1
            if length > maxBits then maxBits = length end
        end
    end
    local code, nextCode = 0, {}
    for bits = 1, maxBits do
        code = (code + (counts[bits - 1] or 0)) * 2
        nextCode[bits] = code
    end
    local size, map = 2 ^ maxBits, {}
    for symbol = 0, count - 1 do
        local length = lengths[symbol] or 0
        if length > 0 then
            local c = nextCode[length]
            nextCode[length] = c + 1
            local reversed = 0
            for _ = 1, length do
                reversed = reversed * 2 + c % 2
                c = math.floor(c / 2)
            end
            for index = reversed, size - 1, 2 ^ length do map[index] = symbol * 16 + length end
        end
    end
    return {Map = map, Bits = maxBits, Mask = size - 1}
end

local function inflate(data, start)
    local pos, buffer, count = start, 0, 0
    local out, n = {}, 0
    local function need(bits)
        while count < bits do
            local byte = data:byte(pos) or 0
            pos = pos + 1
            buffer = bor(buffer, lshift(byte, count))
            count = count + 8
        end
    end
    local function read(bits)
        if bits == 0 then return 0 end
        need(bits)
        local value = band(buffer, lshift(1, bits) - 1)
        buffer = rshift(buffer, bits)
        count = count - bits
        return value
    end
    local function decode(tree)
        need(tree.Bits)
        local entry = tree.Map[band(buffer, tree.Mask)]
        if not entry then error("Bad compressed data") end
        local length = entry % 16
        buffer = rshift(buffer, length)
        count = count - length
        return (entry - length) / 16
    end
    local fixedLit, fixedDist
    repeat
        local final = read(1)
        local kind = read(2)
        if kind == 0 then
            -- Stored block: drop the partial byte and give back whole bytes read ahead.
            local whole = math.floor(count / 8)
            pos = pos - whole
            buffer, count = 0, 0
            local lo, hi = data:byte(pos, pos + 1)
            local length = lo + hi * 256
            pos = pos + 4
            for i = 0, length - 1 do
                n = n + 1
                out[n] = data:byte(pos + i)
            end
            pos = pos + length
        elseif kind == 1 or kind == 2 then
            local lit, dist
            if kind == 1 then
                if not fixedLit then
                    local lengths = {}
                    for s = 0, 143 do lengths[s] = 8 end
                    for s = 144, 255 do lengths[s] = 9 end
                    for s = 256, 279 do lengths[s] = 7 end
                    for s = 280, 287 do lengths[s] = 8 end
                    fixedLit = huffman(lengths, 288)
                    local distances = {}
                    for s = 0, 29 do distances[s] = 5 end
                    fixedDist = huffman(distances, 30)
                end
                lit, dist = fixedLit, fixedDist
            else
                local hlit, hdist, hclen = read(5) + 257, read(5) + 1, read(4) + 4
                local clens = {}
                for i = 1, hclen do clens[CLEN_ORDER[i]] = read(3) end
                local clenTree = huffman(clens, 19)
                local lengths, i = {}, 0
                while i < hlit + hdist do
                    local symbol = decode(clenTree)
                    if symbol < 16 then
                        lengths[i] = symbol
                        i = i + 1
                    else
                        local repeatValue, times = 0, 0
                        if symbol == 16 then repeatValue = lengths[i - 1] or 0; times = read(2) + 3
                        elseif symbol == 17 then times = read(3) + 3
                        else times = read(7) + 11 end
                        for _ = 1, times do lengths[i] = repeatValue; i = i + 1 end
                    end
                end
                local litLengths, distLengths = {}, {}
                for s = 0, hlit - 1 do litLengths[s] = lengths[s] end
                for s = 0, hdist - 1 do distLengths[s] = lengths[hlit + s] end
                lit, dist = huffman(litLengths, hlit), huffman(distLengths, hdist)
            end
            while true do
                local symbol = decode(lit)
                if symbol < 256 then
                    n = n + 1
                    out[n] = symbol
                elseif symbol == 256 then
                    break
                else
                    local index = symbol - 256
                    local length = LEN_BASE[index] + read(LEN_EXTRA[index])
                    local distanceSymbol = decode(dist) + 1
                    local distance = DIST_BASE[distanceSymbol] + read(DIST_EXTRA[distanceSymbol])
                    for _ = 1, length do
                        n = n + 1
                        out[n] = out[n - distance]
                    end
                end
            end
        else
            error("Bad compressed block")
        end
    until final == 1
    return out, n
end

local function u32(data, i)
    local a, b, c, d = data:byte(i, i + 3)
    return ((a * 256 + b) * 256 + c) * 256 + d
end
-- Decodes an 8 or 16-bit PNG (grey, RGB, palette, with or without alpha). Returns width, height, pixel(x, y).
function Lut.decodePng(data)
    assert(data:sub(1, 8) == "\137PNG\r\n\26\n", "Not a PNG file")
    local pos, idat, palette = 9, {}, nil
    local width, height, depth, colorType, interlace
    while pos <= #data do
        local length = u32(data, pos)
        local kind = data:sub(pos + 4, pos + 7)
        local body = data:sub(pos + 8, pos + 7 + length)
        if kind == "IHDR" then
            width, height = u32(body, 1), u32(body, 5)
            depth, colorType, interlace = body:byte(9), body:byte(10), body:byte(13)
        elseif kind == "PLTE" then
            palette = body
        elseif kind == "IDAT" then
            table.insert(idat, body)
        elseif kind == "IEND" then
            break
        end
        pos = pos + 12 + length
    end
    assert(width and height, "PNG has no header")
    assert(interlace == 0, "Interlaced PNGs are not supported")
    assert(depth == 8 or depth == 16, "Only 8 and 16-bit PNGs are supported")
    local channels = ({[0] = 1, [2] = 3, [3] = 1, [4] = 2, [6] = 4})[colorType]
    assert(channels, "Unsupported PNG colour type")
    assert(colorType ~= 3 or (palette and depth == 8), "Bad palette PNG")
    local compressed = table.concat(idat)
    assert(#compressed > 2 and band(compressed:byte(2), 0x20) == 0, "Unsupported PNG compression")
    local raw = inflate(compressed, 3)
    local bpp = channels * depth / 8
    local stride = width * bpp
    local pixels = {}
    local previous = {}
    for x = 1, stride do previous[x] = 0 end
    local index = 1
    for y = 0, height - 1 do
        local filter = raw[index]
        index = index + 1
        local line = {}
        for x = 1, stride do
            local value = raw[index + x - 1] or 0
            local left = x > bpp and line[x - bpp] or 0
            local up = previous[x]
            local upLeft = x > bpp and previous[x - bpp] or 0
            if filter == 1 then value = value + left
            elseif filter == 2 then value = value + up
            elseif filter == 3 then value = value + math.floor((left + up) / 2)
            elseif filter == 4 then
                local p = left + up - upLeft
                local pa, pb, pc = math.abs(p - left), math.abs(p - up), math.abs(p - upLeft)
                if pa <= pb and pa <= pc then value = value + left elseif pb <= pc then value = value + up else value = value + upLeft end
            end
            line[x] = value % 256
        end
        index = index + stride
        pixels[y] = line
        previous = line
    end
    local step = depth / 8
    local function pixel(x, y)
        local line = pixels[y]
        local base = x * bpp + 1
        if colorType == 3 then
            local entry = line[base] * 3 + 1
            local r, g, b = palette:byte(entry, entry + 2)
            return r / 255, g / 255, b / 255
        elseif channels <= 2 then
            local v = line[base] / 255
            return v, v, v
        end
        return line[base] / 255, line[base + step] / 255, line[base + 2 * step] / 255
    end
    return width, height, pixel
end

-- Smooth sampling between the grid points of an N x N x N table: fetch(ri, gi, bi) -> r, g, b.
function Lut.trilinear(size, fetch, normalize)
    return function(r, g, b)
        local x = (normalize and normalize(r, 1) or clamp(r, 0, 1)) * (size - 1)
        local y = (normalize and normalize(g, 2) or clamp(g, 0, 1)) * (size - 1)
        local z = (normalize and normalize(b, 3) or clamp(b, 0, 1)) * (size - 1)
        local x0, y0, z0 = math.min(math.floor(x), size - 2), math.min(math.floor(y), size - 2), math.min(math.floor(z), size - 2)
        local tx, ty, tz = x - x0, y - y0, z - z0
        local outR, outG, outB = 0, 0, 0
        for corner = 0, 7 do
            local dx, dy, dz = corner % 2, math.floor(corner / 2) % 2, math.floor(corner / 4)
            local w = (dx == 1 and tx or 1 - tx) * (dy == 1 and ty or 1 - ty) * (dz == 1 and tz or 1 - tz)
            if w > 0 then
                local cr, cg, cb = fetch(x0 + dx, y0 + dy, z0 + dz)
                outR, outG, outB = outR + cr * w, outG + cg * w, outB + cb * w
            end
        end
        return outR, outG, outB
    end
end
-- A sampler built from a .cube file: sample(r, g, b) -> r, g, b (all 0-1).
function Lut.parseCube(text)
    local size, size1d, values = nil, nil, {}
    local low, high = {0, 0, 0}, {1, 1, 1}
    for line in text:gmatch("[^\r\n]+") do
        line = line:gsub("#.*$", "")
        local key, rest = line:match("^%s*([%u_%d]+)%s+(.-)%s*$")
        if key == "LUT_3D_SIZE" then size = tonumber(rest)
        elseif key == "LUT_1D_SIZE" then size1d = tonumber(rest)
        elseif key == "DOMAIN_MIN" or key == "DOMAIN_MAX" then
            local a, b, c = rest:match("([%-%d%.eE+]+)%s+([%-%d%.eE+]+)%s+([%-%d%.eE+]+)")
            local target = key == "DOMAIN_MIN" and low or high
            target[1], target[2], target[3] = tonumber(a) or target[1], tonumber(b) or target[2], tonumber(c) or target[3]
        else
            local r, g, b = line:match("^%s*([%-%d%.eE+]+)%s+([%-%d%.eE+]+)%s+([%-%d%.eE+]+)%s*$")
            if r and tonumber(r) and tonumber(g) and tonumber(b) then
                local count = #values
                values[count + 1], values[count + 2], values[count + 3] = tonumber(r), tonumber(g), tonumber(b)
            end
        end
    end
    local function normalize(v, axis) return clamp((v - low[axis]) / math.max(high[axis] - low[axis], 1e-6), 0, 1) end
    if size and size >= 2 then
        assert(#values >= size * size * size * 3, "The .cube file is missing entries")
        return Lut.trilinear(size, function(ri, gi, bi)
            local index = (ri + gi * size + bi * size * size) * 3
            return values[index + 1], values[index + 2], values[index + 3]
        end, normalize), "3D " .. size .. "³"
    elseif size1d and size1d >= 2 then
        assert(#values >= size1d * 3, "The .cube file is missing entries")
        return function(r, g, b)
            local function at(v, axis)
                local x = normalize(v, axis) * (size1d - 1)
                local i = math.min(math.floor(x), size1d - 2)
                local t = x - i
                return values[i * 3 + axis] * (1 - t) + values[(i + 1) * 3 + axis] * t
            end
            return at(r, 1), at(g, 2), at(b, 3)
        end, "1D " .. size1d
    end
    error("No LUT_3D_SIZE or LUT_1D_SIZE in the file")
end
-- A sampler built from a ReShade strip: N tiles of N x N side by side (red across a tile, green down, blue by tile).
function Lut.parseStrip(data)
    local width, height, pixel = Lut.decodePng(data)
    local size = height
    assert(size >= 2 and width == size * size, "A LUT strip must be N² pixels wide and N tall (for example 1024 x 32)")
    return Lut.trilinear(size, function(ri, gi, bi) return pixel(bi * size + ri, gi) end), "strip " .. size .. "³"
end
-- Fits a colour correction layer (tint, brightness, contrast, saturation) to any sampler.
function Lut.fit(sample)
    local xs = {0.08, 0.2, 0.35, 0.5, 0.65, 0.8, 0.92}
    local slope, intercept = {}, {}
    for channel = 1, 3 do
        local sx, sy, sxx, sxy, n = 0, 0, 0, 0, 0
        for _, x in ipairs(xs) do
            local out = {sample(x, x, x)}
            local y = out[channel] or x
            sx, sy, sxx, sxy, n = sx + x, sy + y, sxx + x * x, sxy + x * y, n + 1
        end
        local denominator = n * sxx - sx * sx
        local m = denominator ~= 0 and (n * sxy - sx * sy) / denominator or 1
        slope[channel], intercept[channel] = m, (sy - m * sx) / n
    end
    local gain = math.max(slope[1], slope[2], slope[3], 0.05)
    local contrast = clamp(gain - 1, -0.6, 1)
    local tint = rgb(slope[1] / gain, slope[2] / gain, slope[3] / gain)
    local meanIntercept = (intercept[1] + intercept[2] + intercept[3]) / 3
    local brightness = clamp((meanIntercept - 0.5) / gain + 0.5, -0.5, 0.5)
    local function predict(r, g, b)
        local k = 1 + contrast
        return ((r * tint.R + brightness) - 0.5) * k + 0.5, ((g * tint.G + brightness) - 0.5) * k + 0.5, ((b * tint.B + brightness) - 0.5) * k + 0.5
    end
    local measured, predicted = 0, 0
    for hue = 0, 330, 30 do
        local c = Color3.fromHSV(hue / 360, 0.6, 0.65)
        local orr, og, ob = sample(c.R, c.G, c.B)
        local pr, pg, pb = predict(c.R, c.G, c.B)
        local lo = 0.2126 * orr + 0.7152 * og + 0.0722 * ob
        local lp = 0.2126 * pr + 0.7152 * pg + 0.0722 * pb
        measured = measured + math.abs(orr - lo) + math.abs(og - lo) + math.abs(ob - lo)
        predicted = predicted + math.abs(pr - lp) + math.abs(pg - lp) + math.abs(pb - lp)
    end
    local saturation = predicted > 1e-4 and clamp(measured / predicted - 1, -1, 1) or 0
    return {Tint = tint, Brightness = brightness, Contrast = contrast, Saturation = saturation}
end
function Lut.load(path)
    path = tostring(path or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if path == "" then return nil, "Type a file path or a URL." end
    if Lut.Cache[path] then return Lut.Cache[path] end
    local data
    if path:match("^https?://") then data = Files.fetch(path)
    else data = Files.read(path) or Files.read(TAG .. "/luts/" .. path) end
    if not data or data == "" then return nil, "Could not read " .. path end
    local ok, sampler, kind = pcall(function()
        if data:sub(1, 8) == "\137PNG\r\n\26\n" then return Lut.parseStrip(data) end
        return Lut.parseCube(data)
    end)
    if not ok then return nil, tostring(sampler):gsub("^.-:%d+: ", "") end
    local look = Lut.fit(sampler)
    look.Kind = kind
    Lut.Cache[path] = look
    return look
end
function Lut.files()
    local list = {}
    for _, file in ipairs(Files.list(TAG .. "/luts")) do
        local name = tostring(file):match("([^/\\]+)$")
        if name and (name:lower():match("%.cube$") or name:lower():match("%.png$")) then table.insert(list, name) end
    end
    table.sort(list)
    return list
end

local LOOKS = {
    {Name = "Teal & orange", Tint = Color3.new(1, 0.94, 0.86), Brightness = -0.01, Contrast = 0.18, Saturation = 0.2},
    {Name = "Print film", Tint = Color3.new(1, 0.95, 0.88), Brightness = -0.02, Contrast = 0.22, Saturation = 0.08},
    {Name = "Soft film", Tint = Color3.new(0.95, 1, 0.96), Brightness = 0.01, Contrast = -0.05, Saturation = -0.18},
    {Name = "Golden hour", Tint = Color3.new(1, 0.86, 0.66), Brightness = 0.02, Contrast = 0.1, Saturation = 0.15},
    {Name = "Arctic", Tint = Color3.new(0.84, 0.93, 1), Brightness = 0.03, Contrast = 0.06, Saturation = -0.2},
    {Name = "Neon night", Tint = Color3.new(0.95, 0.8, 1), Brightness = 0, Contrast = 0.25, Saturation = 0.4},
    {Name = "Green code", Tint = Color3.new(0.78, 1, 0.8), Brightness = -0.02, Contrast = 0.2, Saturation = -0.3},
    {Name = "Faded 70s", Tint = Color3.new(1, 0.93, 0.8), Brightness = 0.05, Contrast = -0.18, Saturation = -0.25},
    {Name = "Moonlight", Tint = Color3.new(0.75, 0.84, 1), Brightness = -0.04, Contrast = 0.12, Saturation = -0.35},
    {Name = "Silver", Tint = Color3.new(0.97, 0.98, 1), Brightness = 0, Contrast = 0.3, Saturation = -0.85},
}
local LOOK_NAMES = {}
for _, look in ipairs(LOOKS) do table.insert(LOOK_NAMES, look.Name) end
local CUSTOM_LUT = "File or URL below"

defineEffect({
    Id = "lut", Title = "LUT", Icon = "box", Default = false,
    Description = "Colour look-up tables, from .cube files or ReShade strips.",
    Notes = {"Pick a built-in look, or put .cube files and ReShade PNG strips in the workspace folder " .. TAG .. "/luts and pick them here.",
        "A link (https://…) to a .cube or .png file also works.",
        "Roblox cannot sample a LUT per pixel, so the table is measured and fitted to a colour correction layer: tint, brightness, contrast and saturation. Curves that bend a lot are approximated."},
    Params = {
        {Key = "Source", Title = "Look", Kind = "Dropdown", Options = LOOK_NAMES, Default = "Teal & orange", Dynamic = true},
        {Key = "Path", Title = "File or URL", Kind = "Input", Default = "", Placeholder = "my-look.cube or https://…"},
        {Key = "Strength", Title = "Strength", Kind = "Slider", Min = 0, Max = 100, Default = 80, Suffix = "%"},
    },
    Apply = function(self)
        local cfg = self.Config
        local look
        if cfg.Source == CUSTOM_LUT then
            local loaded, problem = Lut.load(cfg.Path)
            look = loaded
            self.Info = loaded and ("Fitted " .. (loaded.Kind or "LUT")) or (problem or "No file")
        elseif tostring(cfg.Source):lower():match("%.cube$") or tostring(cfg.Source):lower():match("%.png$") then
            local loaded, problem = Lut.load(TAG .. "/luts/" .. cfg.Source)
            look = loaded
            self.Info = loaded and ("Fitted " .. (loaded.Kind or "LUT")) or (problem or "No file")
        else
            for _, item in ipairs(LOOKS) do if item.Name == cfg.Source then look = item end end
            self.Info = look and look.Name or ""
        end
        if not look then dropSlot("LUT"); return end
        local s = cfg.Strength / 100
        local cc = slot("LUT", "ColorCorrectionEffect")
        if cc then
            cc.TintColor = WHITE:Lerp(look.Tint, s)
            cc.Brightness = clamp(look.Brightness * s, -1, 1)
            cc.Contrast = clamp(look.Contrast * s, -1, 1)
            cc.Saturation = clamp(look.Saturation * s, -1, 1)
            cc.Enabled = true
        end
    end,
    Update = function(self) if self.Info ~= "" and not slotAlive("LUT") and self.Config.Strength > 0 then self:Apply() end end,
    Stop = function() dropSlot("LUT") end,
})

-- -----------------------------------------------------------------------------
-- Sharpness: local contrast and clarity, and the option to remove the game's own blur.
-- -----------------------------------------------------------------------------
local function gameBlurs()
    local list = {}
    local function scan(parent)
        if not parent then return end
        for _, child in ipairs(parent:GetChildren()) do
            if (child:IsA("BlurEffect") or child:IsA("DepthOfFieldEffect")) and not isOwn(child) then table.insert(list, child) end
        end
    end
    scan(Lighting)
    scan(Workspace.CurrentCamera)
    return list
end
defineEffect({
    Id = "sharpness", Title = "Sharpness", Icon = "search", Default = true,
    Description = "Sharpening and clarity for fine detail and local contrast.",
    Notes = {"Raises contrast around the mid-tones so edges and textures read more clearly.",
        "Remove game blur turns off the game's own blur and depth-of-field layers while this effect is on."},
    Params = {
        {Key = "Strength", Title = "Strength", Kind = "Slider", Min = 0, Max = 100, Default = 35, Suffix = "%"},
        {Key = "Clarity", Title = "Clarity", Description = "Mid-tone contrast.", Kind = "Slider", Min = 0, Max = 100, Default = 25, Suffix = "%"},
        {Key = "RemoveBlur", Title = "Remove game blur", Kind = "Toggle", Default = false},
    },
    Apply = function(self)
        local cfg = self.Config
        local cc = slot("Sharpness", "ColorCorrectionEffect")
        if cc then
            cc.Contrast = clamp(cfg.Strength / 100 * 0.1 + cfg.Clarity / 100 * 0.12, -1, 1)
            cc.Saturation = clamp(cfg.Strength / 100 * 0.04, -1, 1)
            cc.Brightness = -cfg.Clarity / 100 * 0.015
            cc.TintColor = WHITE
            cc.Enabled = true
        end
        Props.clearOwner("sharpness")
        if cfg.RemoveBlur then
            for _, blur in ipairs(gameBlurs()) do Props.set(blur, "Enabled", "sharpness", 0, function() return false end) end
        end
        self.Info = cfg.RemoveBlur and "Game blur removed" or ""
    end,
    Update = function(self, _, now)
        if not slotAlive("Sharpness") then self:Apply() end
        if self.Config.RemoveBlur and now >= (self.NextScan or 0) then
            self.NextScan = now + 2
            for _, blur in ipairs(gameBlurs()) do Props.set(blur, "Enabled", "sharpness", 0, function() return false end) end
        end
    end,
    Stop = function() dropSlot("Sharpness"); Props.clearOwner("sharpness") end,
})

-- -----------------------------------------------------------------------------
-- Bloom and sun rays: Roblox's own post effects, layered on top of the game's.
-- -----------------------------------------------------------------------------
defineEffect({
    Id = "bloom", Title = "Bloom", Icon = "star", Default = true,
    Description = "Glow that spills from bright lights and highlights.",
    Notes = {"A bloom layer on top of the game's. Lower the threshold to let more of the frame glow.",
        "Replace game bloom turns the game's own bloom off while this one is on."},
    Params = {
        {Key = "Intensity", Title = "Intensity", Kind = "Slider", Min = 0, Max = 100, Default = 30, Suffix = "%"},
        {Key = "Size", Title = "Size", Kind = "Slider", Min = 0, Max = 56, Default = 26},
        {Key = "Threshold", Title = "Threshold", Description = "Only pixels brighter than this glow.", Kind = "Slider", Min = 0.5, Max = 4, Step = 0.05, Default = 1.6},
        {Key = "Replace", Title = "Replace game bloom", Kind = "Toggle", Default = false},
    },
    Apply = function(self)
        local cfg = self.Config
        local bloom = slot("Bloom", "BloomEffect")
        if bloom then
            bloom.Intensity = cfg.Intensity / 100 * 1.5
            bloom.Size = cfg.Size
            bloom.Threshold = cfg.Threshold
            bloom.Enabled = true
        end
        Props.clearOwner("bloom")
        if cfg.Replace then
            for _, child in ipairs(Lighting:GetChildren()) do
                if child:IsA("BloomEffect") and not isOwn(child) then Props.set(child, "Enabled", "bloom", 0, function() return false end) end
            end
        end
    end,
    Update = function(self) if not slotAlive("Bloom") then self:Apply() end end,
    Stop = function() dropSlot("Bloom"); Props.clearOwner("bloom") end,
})

defineEffect({
    Id = "sunrays", Title = "Sun rays", Icon = "star", Default = false,
    Description = "Light shafts that fan out from the sun.",
    Notes = {"Roblox's sun rays, drawn when the sun is on screen and not hidden."},
    Params = {
        {Key = "Intensity", Title = "Intensity", Kind = "Slider", Min = 0, Max = 100, Default = 25, Suffix = "%"},
        {Key = "Spread", Title = "Spread", Kind = "Slider", Min = 0, Max = 100, Default = 60, Suffix = "%"},
    },
    Apply = function(self)
        local rays = slot("SunRays", "SunRaysEffect")
        if rays then
            rays.Intensity = self.Config.Intensity / 100 * 0.5
            rays.Spread = self.Config.Spread / 100
            rays.Enabled = true
        end
    end,
    Update = function(self) if not slotAlive("SunRays") then self:Apply() end end,
    Stop = function() dropSlot("SunRays") end,
})

-- -----------------------------------------------------------------------------
-- Atmosphere: tunes the game's Atmosphere, or adds one when there is none.
-- -----------------------------------------------------------------------------
local AIR = {
    Natural = {Color = nil, Decay = nil},
    Warm = {Color = Color3.fromRGB(255, 214, 170), Decay = Color3.fromRGB(150, 96, 70)},
    Cool = {Color = Color3.fromRGB(200, 222, 255), Decay = Color3.fromRGB(92, 110, 150)},
    Misty = {Color = Color3.fromRGB(222, 228, 232), Decay = Color3.fromRGB(170, 176, 184)},
    Dusk = {Color = Color3.fromRGB(255, 176, 160), Decay = Color3.fromRGB(110, 70, 110)},
}
defineEffect({
    Id = "atmosphere", Title = "Atmosphere", Icon = "refresh-cw", Default = false,
    Description = "Fog, haze and glare that give the air depth.",
    Notes = {"Adjusts the game's Atmosphere, or adds one when the game has none. Natural keeps the game's colours."},
    Params = {
        {Key = "Density", Title = "Density", Kind = "Slider", Min = 0, Max = 100, Default = 30, Suffix = "%"},
        {Key = "Offset", Title = "Horizon", Description = "How much the fog hugs the horizon.", Kind = "Slider", Min = 0, Max = 100, Default = 25, Suffix = "%"},
        {Key = "Haze", Title = "Haze", Kind = "Slider", Min = 0, Max = 10, Step = 0.1, Default = 1.5},
        {Key = "Glare", Title = "Glare", Kind = "Slider", Min = 0, Max = 10, Step = 0.1, Default = 0.6},
        {Key = "Tone", Title = "Colour", Kind = "Dropdown", Options = {"Natural", "Warm", "Cool", "Misty", "Dusk"}, Default = "Natural"},
    },
    Apply = function(self)
        local cfg = self.Config
        local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
        if atmosphere and isOwn(atmosphere) and atmosphere ~= Slots.Atmosphere then atmosphere = nil end
        if not atmosphere or atmosphere == Slots.Atmosphere then
            atmosphere = slot("Atmosphere", "Atmosphere")
            if not atmosphere then return end
            atmosphere.Color = Color3.fromRGB(199, 199, 199)
            atmosphere.Decay = Color3.fromRGB(106, 112, 125)
        end
        self.Target = atmosphere
        Props.clearOwner("atmosphere")
        local air = AIR[cfg.Tone] or AIR.Natural
        Props.set(atmosphere, "Density", "atmosphere", 0, function() return cfg.Density / 100 * 0.6 end)
        Props.set(atmosphere, "Offset", "atmosphere", 0, function() return cfg.Offset / 100 end)
        Props.set(atmosphere, "Haze", "atmosphere", 0, function() return cfg.Haze end)
        Props.set(atmosphere, "Glare", "atmosphere", 0, function() return cfg.Glare end)
        if air.Color then
            Props.set(atmosphere, "Color", "atmosphere", 0, function() return air.Color end)
            Props.set(atmosphere, "Decay", "atmosphere", 0, function() return air.Decay end)
        end
        self.Info = atmosphere == Slots.Atmosphere and "Added an atmosphere" or "Tuning the game's atmosphere"
    end,
    Update = function(self) if not alive(self.Target) then self:Apply() end end,
    Stop = function(self) Props.clearOwner("atmosphere"); dropSlot("Atmosphere"); self.Target = nil end,
})

-- -----------------------------------------------------------------------------
-- Lighting: time of day, sun strength, shadows and the lighting technology.
-- -----------------------------------------------------------------------------
local Technology = {Original = nil, Applied = nil}
function Technology.set(name)
    if type(sethiddenproperty) ~= "function" then return false, "This executor cannot change the lighting technology." end
    if Technology.Original == nil then
        local ok, value = pcall(function() return Lighting.Technology end)
        if not ok and type(gethiddenproperty) == "function" then ok, value = pcall(gethiddenproperty, Lighting, "Technology") end
        Technology.Original = ok and value or false
    end
    local item = enumItem("Technology", name)
    if not item then return false, "Unknown technology." end
    if not pcall(sethiddenproperty, Lighting, "Technology", item) then return false, "The game refused the change." end
    Technology.Applied = item
    return true
end
function Technology.restore()
    if Technology.Applied and Technology.Original and type(sethiddenproperty) == "function" then
        pcall(sethiddenproperty, Lighting, "Technology", Technology.Original)
    end
    Technology.Applied = nil
end
defineEffect({
    Id = "lighting", Title = "Lighting & shadows", Icon = "repeat", Default = false,
    Description = "Time of day, sun strength, shadow softness and lighting technology.",
    Notes = {"Lock time keeps the sun where you put it, even if the game has a day cycle.",
        "Technology needs an executor with sethiddenproperty. Future lights every lamp with shadows; it is the heaviest."},
    Params = {
        {Key = "LockTime", Title = "Lock time of day", Kind = "Toggle", Default = false},
        {Key = "Time", Title = "Time of day", Kind = "Slider", Min = 0, Max = 24, Step = 0.25, Default = 14,
            Format = function(v) local h = math.floor(v); return string.format("%02d:%02d", h, math.floor((v - h) * 60 + 0.5)) end},
        {Key = "Sun", Title = "Sun strength", Kind = "Slider", Min = 0, Max = 200, Default = 100, Suffix = "%"},
        {Key = "Softness", Title = "Shadow softness", Kind = "Slider", Min = 0, Max = 100, Default = 20, Suffix = "%"},
        {Key = "Shadows", Title = "Shadows", Kind = "Toggle", Default = true},
        {Key = "Technology", Title = "Technology", Kind = "Dropdown", Options = {"Game default", "Future", "ShadowMap", "Voxel", "Compatibility"}, Default = "Game default"},
    },
    Apply = function(self)
        local cfg = self.Config
        Props.clearOwner("lighting")
        if cfg.LockTime then Props.set(Lighting, "ClockTime", "lighting", 0, function() return cfg.Time end) end
        if cfg.Sun ~= 100 then Props.set(Lighting, "Brightness", "lighting", 0, function(v) return v * cfg.Sun / 100 end) end
        Props.set(Lighting, "ShadowSoftness", "lighting", 0, function() return cfg.Softness / 100 end)
        Props.set(Lighting, "GlobalShadows", "lighting", 0, function() return cfg.Shadows end)
        self.Info = ""
        if cfg.Technology == "Game default" then
            Technology.restore()
        else
            local ok, problem = Technology.set(cfg.Technology)
            self.Info = ok and (cfg.Technology .. " lighting") or problem
        end
    end,
    Stop = function() Props.clearOwner("lighting"); Technology.restore() end,
})

-- -----------------------------------------------------------------------------
-- Ambient light: lifts shadows with the light already in the frame.
-- -----------------------------------------------------------------------------
defineEffect({
    Id = "ambient", Title = "Ambient light", Icon = "star", Default = true, UsesProbe = true,
    Description = "Shadow lifted by the light that is already in the frame.",
    Notes = {"A light probe around you measures the colour of the light bouncing nearby; shadows are lifted with that colour.",
        "Environment light controls how much the sky lights and reflects off surfaces (visible with Future and ShadowMap lighting)."},
    Params = {
        {Key = "Strength", Title = "Shadow lift", Kind = "Slider", Min = 0, Max = 100, Default = 30, Suffix = "%"},
        {Key = "SceneColour", Title = "Use scene colour", Kind = "Slider", Min = 0, Max = 100, Default = 60, Suffix = "%"},
        {Key = "Indoor", Title = "Indoor lift", Kind = "Slider", Min = 0, Max = 100, Default = 35, Suffix = "%"},
        {Key = "Diffuse", Title = "Environment light", Kind = "Slider", Min = 0, Max = 100, Default = 100, Suffix = "%"},
        {Key = "Specular", Title = "Environment reflections", Kind = "Slider", Min = 0, Max = 100, Default = 100, Suffix = "%"},
    },
    Start = function(self)
        Probe.Users = Probe.Users + 1
        local cfg = self.Config
        local function lift(scale)
            return function(value)
                local tint = lerpColor(Color3.fromRGB(150, 150, 160), saturateColor(Probe.EnvColor, 1.3), cfg.SceneColour / 100)
                local amount = cfg.Strength / 100 * 0.42 * scale
                return addColor(value, tint, amount)
            end
        end
        Props.set(Lighting, "OutdoorAmbient", "ambient", 10, lift(1))
        Props.set(Lighting, "Ambient", "ambient", 10, function(value)
            return lift(1)(value):Lerp(addColor(value, WHITE, cfg.Indoor / 100 * 0.25), 0.5)
        end)
        Props.set(Lighting, "EnvironmentDiffuseScale", "ambient", 0, function() return cfg.Diffuse / 100 end)
        Props.set(Lighting, "EnvironmentSpecularScale", "ambient", 0, function() return cfg.Specular / 100 end)
    end,
    Update = function(self) self.Info = "Scene light " .. formatNumber(Probe.EnvLum * 100) .. "%" end,
    Stop = function() Probe.Users = Probe.Users - 1; Props.clearOwner("ambient") end,
})

-- -----------------------------------------------------------------------------
-- Global illumination: bounce light from sunlit surfaces near the player, plus a colour-bleeding ambient.
-- -----------------------------------------------------------------------------
defineEffect({
    Id = "gi", Title = "Global Illumination", Icon = "refresh-cw", Default = false, UsesProbe = true,
    Description = "Light that bounces off surfaces onto the ones beside them.",
    Notes = {"The probe finds the brightest sunlit surfaces around you. Each one gets a soft light of its own colour, placed just off the surface, so it tints whatever is next to it.",
        "Colour bleeding also shifts the ambient light toward the colours around you. Bounce lights show best with Future or ShadowMap lighting."},
    Params = {
        {Key = "Intensity", Title = "Intensity", Kind = "Slider", Min = 0, Max = 100, Default = 50, Suffix = "%"},
        {Key = "Bleeding", Title = "Colour bleeding", Kind = "Slider", Min = 0, Max = 100, Default = 50, Suffix = "%"},
        {Key = "Lights", Title = "Bounce lights", Kind = "Stepper", Min = 0, Max = 8, Default = 4},
        {Key = "Range", Title = "Light range", Kind = "Slider", Min = 6, Max = 40, Default = 16, Suffix = " studs"},
        {Key = "Sky", Title = "Sky light", Kind = "Slider", Min = 0, Max = 100, Default = 40, Suffix = "%"},
    },
    Start = function(self)
        Probe.Users = Probe.Users + 1
        self.Lights = {}
        local cfg = self.Config
        Props.set(Lighting, "OutdoorAmbient", "gi", 20, function(value)
            local bleed = saturateColor(Probe.EnvColor, 1 + cfg.Bleeding / 100)
            local sky = Scene.skyColor()
            local amount = cfg.Intensity / 100
            local mixed = lerpColor(value, addColor(scaleColor(value, 0.75), bleed, 0.35), amount * cfg.Bleeding / 100)
            return addColor(mixed, sky, amount * cfg.Sky / 100 * 0.12 * Scene.Day)
        end)
    end,
    Update = function(self, dt)
        local cfg = self.Config
        local wanted = math.min(cfg.Lights, cap("Lights"))
        local spots = wanted > 0 and Probe.brightSpots(wanted, 7) or {}
        for index = 1, math.max(#self.Lights, wanted) do
            local light = self.Lights[index]
            local spot = spots[index]
            if index <= wanted and not (light and alive(light.Point)) then
                local attachment = World.attachment("Bounce")
                light = {Point = attachment, Light = new("PointLight", {Shadows = false, Brightness = 0, Range = cfg.Range}, attachment), Level = 0}
                self.Lights[index] = light
            end
            if light and alive(light.Point) then
                local target = 0
                if spot and index <= wanted then
                    local goal = spot.Hit + spot.Normal * 2.5
                    local current = light.Point.WorldPosition
                    light.Point.WorldPosition = (current - goal).Magnitude > 20 and goal or current:Lerp(goal, clamp(dt * 3, 0, 1))
                    light.Light.Color = saturateColor(spot.Albedo, 1 + cfg.Bleeding / 100)
                    target = cfg.Intensity / 100 * 1.4 * clamp(spot.Lum * 1.5, 0.2, 1.2)
                end
                light.Level = approach(light.Level, target, 3, dt)
                light.Light.Brightness = light.Level
                light.Light.Range = cfg.Range
                light.Light.Enabled = light.Level > 0.01
            end
        end
        for index = #self.Lights, wanted + 1, -1 do
            local light = self.Lights[index]
            if light and light.Level < 0.02 then
                pcall(function() light.Point:Destroy() end)
                table.remove(self.Lights, index)
            end
        end
        self.Info = #spots .. " bounce light" .. (#spots == 1 and "" or "s")
    end,
    Stop = function(self)
        Probe.Users = Probe.Users - 1
        Props.clearOwner("gi")
        for _, light in ipairs(self.Lights or {}) do pcall(function() light.Point:Destroy() end) end
        self.Lights = {}
    end,
})

-- -----------------------------------------------------------------------------
-- Exposure: eye adaptation from the light the camera sees.
-- -----------------------------------------------------------------------------
defineEffect({
    Id = "exposure", Title = "Exposure", Icon = "eye-off", Default = false, UsesProbe = true,
    Description = "Adapts brightness to the scene the way an eye or a camera does.",
    Notes = {"Rays across the screen measure how bright the view is (sunlit, shaded, sky). Exposure then drifts toward a balanced level: step indoors and the view slowly opens up; look at the sky and it closes down.",
        "Manual mode just adds the compensation."},
    Params = {
        {Key = "Mode", Title = "Mode", Kind = "Segmented", Options = {"Auto", "Manual"}, Default = "Auto"},
        {Key = "Compensation", Title = "Compensation", Kind = "Slider", Min = -3, Max = 3, Step = 0.1, Default = 0, Suffix = " EV"},
        {Key = "Min", Title = "Darkest adaptation", Kind = "Slider", Min = -3, Max = 0, Step = 0.1, Default = -1.2, Suffix = " EV"},
        {Key = "Max", Title = "Brightest adaptation", Kind = "Slider", Min = 0, Max = 3, Step = 0.1, Default = 1.4, Suffix = " EV"},
        {Key = "SpeedUp", Title = "Brightening speed", Kind = "Slider", Min = 0.2, Max = 5, Step = 0.1, Default = 1.1},
        {Key = "SpeedDown", Title = "Darkening speed", Kind = "Slider", Min = 0.2, Max = 5, Step = 0.1, Default = 2.4},
        {Key = "Metering", Title = "Metering", Kind = "Dropdown", Options = {"Centre", "Average", "Spot"}, Default = "Centre"},
    },
    Start = function(self)
        Probe.Users = Probe.Users + 1
        self.EV = 0
        Props.set(Lighting, "ExposureCompensation", "exposure", 50, function(value) return clamp(value + self.EV, -3, 3) end)
    end,
    Update = function(self, dt)
        local cfg = self.Config
        local target = cfg.Compensation
        if cfg.Mode == "Auto" then
            local measured = math.max(Probe.ViewLum, 1e-3)
            target = clamp(math.log(0.32 / measured, 2) * 0.65, cfg.Min, cfg.Max) + cfg.Compensation
        end
        local speed = target > self.EV and cfg.SpeedUp or cfg.SpeedDown
        self.EV = approach(self.EV, target, speed, dt)
        self.Info = string.format("%+.1f EV", self.EV)
    end,
    Stop = function() Probe.Users = Probe.Users - 1; Props.clearOwner("exposure") end,
})

-- -----------------------------------------------------------------------------
-- Depth of field with a thin-lens model: focal length from the field of view, an f-stop and a focus distance.
-- -----------------------------------------------------------------------------
local STUD_MM = 280 -- 1 stud = 0.28 m
defineEffect({
    Id = "dof", Title = "Depth of field", Icon = "search", Default = false,
    Description = "Focus and blur by distance, with a physical lens model.",
    Notes = {"A thin-lens model: with the focal length (50 mm by default; 0 follows your field of view on a full-frame sensor), the f-stop and the focus distance, the lens formulas give the sharp zone and how blurry the background gets.",
        "Auto focuses on whatever is in the middle of the screen; Character keeps you sharp."},
    Params = {
        {Key = "Focus", Title = "Focus", Kind = "Segmented", Options = {"Auto", "Character", "Manual"}, Default = "Auto"},
        {Key = "Distance", Title = "Manual distance", Kind = "Slider", Min = 2, Max = 200, Default = 30, Suffix = " studs"},
        {Key = "Aperture", Title = "Aperture", Kind = "Stepper", Values = {1.4, 2, 2.8, 4, 5.6, 8, 11, 16, 22}, Default = 2.8, Format = function(v) return "f/" .. v end},
        {Key = "Focal", Title = "Focal length", Description = "Longer lenses blur more. 0 follows your field of view.", Kind = "Slider", Min = 0, Max = 200, Default = 50, Suffix = " mm"},
        {Key = "Speed", Title = "Focus speed", Kind = "Slider", Min = 1, Max = 20, Default = 7},
        {Key = "MaxBlur", Title = "Maximum blur", Kind = "Slider", Min = 0, Max = 100, Default = 70, Suffix = "%"},
        {Key = "Near", Title = "Blur close objects", Kind = "Toggle", Default = true},
    },
    Start = function(self) self.FocusDistance = 30 end,
    Update = function(self, dt)
        local cfg = self.Config
        local target = cfg.Distance
        if cfg.Focus == "Auto" and Scene.Camera then
            local viewport = Scene.Viewport
            local ray = Scene.Camera:ViewportPointToRay(viewport.X / 2, viewport.Y / 2)
            local hit = Scene.cast(ray.Origin, ray.Direction * 600, Scene.SolidParams)
            target = hit and (hit.Position - ray.Origin).Magnitude or 600
        elseif cfg.Focus == "Character" then
            local character = LocalPlayer.Character
            local head = character and (character:FindFirstChild("Head") or characterRoot(character))
            target = head and (head.Position - Scene.Eye).Magnitude or cfg.Distance
        end
        self.FocusDistance = approach(self.FocusDistance, clamp(target, 0.5, 600), cfg.Speed, dt)
        local f = cfg.Focal > 0 and cfg.Focal or 12 / math.tan(math.rad(Scene.FieldOfView or 70) / 2)
        local N, c = cfg.Aperture, 0.03
        local S = math.max(self.FocusDistance * STUD_MM, f * 1.5)
        local H = f * f / (N * c) + f
        local near = S * (H - f) / (H + S - 2 * f)
        local far = S < H and S * (H - f) / (H - S) or math.huge
        local blur = f * f / (N * math.max(S - f, 1)) -- blur disc at infinity, mm on the sensor
        local strength = clamp(blur / 24 * 60, 0, 1) * cfg.MaxBlur / 100
        local dof = slot("DepthOfField", "DepthOfFieldEffect")
        if not dof then return end
        local nearStuds, farStuds = near / STUD_MM, far / STUD_MM
        if farStuds == math.huge then
            dof.FocusDistance = clamp(nearStuds + 50, 0, 200)
            dof.InFocusRadius = 50
            dof.FarIntensity = 0
        else
            dof.FocusDistance = clamp((nearStuds + farStuds) / 2, 0, 200)
            dof.InFocusRadius = clamp((farStuds - nearStuds) / 2, 0, 50)
            dof.FarIntensity = strength
        end
        dof.NearIntensity = cfg.Near and clamp(strength * 0.8, 0, 1) or 0
        dof.Enabled = true
        self.Info = string.format("Focus %.0f studs · %.0f mm f/%s", self.FocusDistance, f, tostring(N))
    end,
    Stop = function() dropSlot("DepthOfField") end,
})

-- -----------------------------------------------------------------------------
-- Motion blur: a blur layer that follows how fast the camera turns and moves.
-- -----------------------------------------------------------------------------
defineEffect({
    Id = "motionblur", Title = "Motion blur", Icon = "repeat", Default = false,
    Description = "Smears the frame when the camera turns fast.",
    Notes = {"Measures the camera's turn and move speed every frame and blurs the frame in proportion. Roblox's blur is not directional, so it is kept short."},
    Params = {
        {Key = "Intensity", Title = "Intensity", Kind = "Slider", Min = 0, Max = 100, Default = 50, Suffix = "%"},
        {Key = "Threshold", Title = "Threshold", Description = "Turn speed before blur starts.", Kind = "Slider", Min = 0, Max = 200, Default = 60, Suffix = "°/s"},
        {Key = "Movement", Title = "Blur when moving", Kind = "Toggle", Default = false},
    },
    Start = function(self) self.Level = 0; self.LastLook = nil; self.LastEye = nil end,
    Update = function(self, dt)
        local cfg = self.Config
        local speed = 0
        if self.LastLook and dt > 0 then
            local turn = math.deg(math.acos(clamp(self.LastLook:Dot(Scene.Look), -1, 1))) / dt
            speed = math.max(0, turn - cfg.Threshold) / 400
            if cfg.Movement and self.LastEye then speed = speed + math.max(0, (Scene.Eye - self.LastEye).Magnitude / dt - 40) / 300 end
        end
        self.LastLook, self.LastEye = Scene.Look, Scene.Eye
        self.Level = approach(self.Level, clamp(speed, 0, 1), 14, dt)
        local blur = slot("MotionBlur", "BlurEffect")
        if blur then
            blur.Size = self.Level * cfg.Intensity / 100 * 14
            blur.Enabled = blur.Size > 0.2
        end
    end,
    Stop = function() dropSlot("MotionBlur") end,
})

-- -----------------------------------------------------------------------------
-- Noise texture for grain and dithering. An EditableImage of soft random noise when the game allows it;
-- otherwise a layer of tiny glyphs, which needs no image at all.
-- -----------------------------------------------------------------------------
local Noise = {Size = 128}
function Noise.content()
    if Noise.Tried then return Noise.Content end
    Noise.Tried = true
    pcall(function()
        local assets = game:GetService("AssetService")
        local size = Noise.Size
        local image = assets:CreateEditableImage({Size = Vector2.new(size, size)})
        local data = buffer.create(size * size * 4)
        local rng = Random.new(20240611)
        for i = 0, size * size - 1 do
            -- Triangular noise around mid-grey reads as grain instead of speckles.
            local v = math.floor((rng:NextNumber() + rng:NextNumber()) * 127.5)
            buffer.writeu8(data, i * 4, v)
            buffer.writeu8(data, i * 4 + 1, v)
            buffer.writeu8(data, i * 4 + 2, v)
            buffer.writeu8(data, i * 4 + 3, 255)
        end
        image:WritePixelsBuffer(Vector2.zero, Vector2.new(size, size), data)
        Noise.Image = image
        Noise.Content = Content.fromObject(image)
    end)
    return Noise.Content
end
local GLYPHS = {".", "·", ",", "'", ":", "`", " ", " ", " ", " "}
local function glyphText(columns, rows, seed)
    local rng = Random.new(seed)
    local lines = {}
    for row = 1, rows do
        local chars = table.create(columns)
        for col = 1, columns do chars[col] = GLYPHS[rng:NextInteger(1, #GLYPHS)] end
        lines[row] = table.concat(chars)
    end
    return table.concat(lines, "\n")
end
-- A full-screen noise layer. Returns {Root, Set(transparency), Jitter()}.
function Noise.layer(name, scale, zindex)
    local layer = Overlay.layer(name, zindex)
    layer:ClearAllChildren()
    local object = {Root = layer}
    local content = Noise.content()
    local tile = math.floor(Noise.Size * scale)
    if content then
        local image = new("ImageLabel", {BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.new(1, tile * 2, 1, tile * 2),
            ScaleType = Enum.ScaleType.Tile, TileSize = UDim2.fromOffset(tile, tile), ImageTransparency = 1}, layer)
        if not safeSet(image, "ImageContent", content) then image:Destroy(); content = nil else object.Image = image end
    end
    if not content then
        local size = math.max(8, math.floor(10 * scale))
        local light = new("TextLabel", {BackgroundTransparency = 1, Size = UDim2.new(1, 40, 1, 40), Font = Enum.Font.Code, TextSize = size,
            TextColor3 = WHITE, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, TextWrapped = false,
            Text = glyphText(220, 120, 7), TextTransparency = 1}, layer)
        local dark = light:Clone()
        dark.TextColor3 = BLACK
        dark.Text = glyphText(220, 120, 11)
        dark.Parent = layer
        object.Glyphs = {light, dark}
        object.Tile = size * 6
    end
    object.TileSize = tile
    function object.Set(transparency)
        if object.Image then object.Image.ImageTransparency = transparency end
        if object.Glyphs then
            for _, label in ipairs(object.Glyphs) do label.TextTransparency = clamp(1 - (1 - transparency) * 3.5, 0, 1) end
        end
    end
    local rng = Random.new()
    function object.Jitter()
        if object.Image then
            object.Image.Position = UDim2.fromOffset(-rng:NextInteger(0, tile), -rng:NextInteger(0, tile))
        elseif object.Glyphs then
            for _, label in ipairs(object.Glyphs) do label.Position = UDim2.fromOffset(-rng:NextInteger(0, 20), -rng:NextInteger(0, 20)) end
        end
    end
    return object
end

defineEffect({
    Id = "deband", Title = "Deband", Icon = "sliders-horizontal", Default = false,
    Description = "Breaks up colour banding in smooth gradients.",
    Notes = {"Adds a very fine, moving dither over the frame, the same trick debanding shaders use: smooth skies and fog stop showing steps.",
        "The noise is generated on your device (EditableImage). Where the game does not allow that, a light glyph pattern is used instead."},
    Params = {
        {Key = "Strength", Title = "Strength", Kind = "Slider", Min = 0, Max = 100, Default = 45, Suffix = "%"},
        {Key = "Animated", Title = "Animated dither", Description = "Moves the pattern every frame so it never shows as texture.", Kind = "Toggle", Default = true},
    },
    Start = function(self) self.Layer = Noise.layer("Deband", 1, 2) end,
    Apply = function(self) if self.Layer then self.Layer.Set(1 - self.Config.Strength / 100 * 0.07) end end,
    Update = function(self)
        if not alive(self.Layer and self.Layer.Root) then self.Layer = Noise.layer("Deband", 1, 2); self:Apply() end
        if self.Config.Animated then self.Layer.Jitter() end
    end,
    Stop = function(self) Overlay.drop("Deband"); self.Layer = nil end,
})

defineEffect({
    Id = "grain", Title = "Film grain", Icon = "box", Default = false,
    Description = "Fine moving noise like film or a camera sensor.",
    Notes = {"A noise layer that changes every frame. Size scales the grain; Shadows only makes it lighter in bright scenes."},
    Params = {
        {Key = "Intensity", Title = "Intensity", Kind = "Slider", Min = 0, Max = 100, Default = 30, Suffix = "%"},
        {Key = "Size", Title = "Grain size", Kind = "Segmented", Options = {"Fine", "Medium", "Coarse"}, Default = "Fine"},
        {Key = "Rate", Title = "Speed", Kind = "Slider", Min = 6, Max = 60, Default = 24, Suffix = " fps"},
    },
    Start = function(self) self.Built = nil; self.Next = 0 end,
    Apply = function(self)
        local scale = ({Fine = 1, Medium = 1.6, Coarse = 2.4})[self.Config.Size] or 1
        if self.Built ~= scale or not alive(self.Layer and self.Layer.Root) then
            self.Layer = Noise.layer("Grain", scale, 3)
            self.Built = scale
        end
        self.Layer.Set(1 - self.Config.Intensity / 100 * 0.2)
    end,
    Update = function(self, _, now)
        if not alive(self.Layer and self.Layer.Root) then self.Built = nil; self:Apply() end
        if now >= self.Next then
            self.Next = now + 1 / self.Config.Rate
            self.Layer.Jitter()
        end
    end,
    Stop = function(self) Overlay.drop("Grain"); self.Layer = nil; self.Built = nil end,
})

-- -----------------------------------------------------------------------------
-- Vignette: four soft gradients from the screen edges; where two meet, the corners get darker.
-- -----------------------------------------------------------------------------
defineEffect({
    Id = "vignette", Title = "Vignette", Icon = "maximize-2", Default = false,
    Description = "Darkens the corners to draw the eye to the centre.",
    Params = {
        {Key = "Intensity", Title = "Intensity", Kind = "Slider", Min = 0, Max = 100, Default = 40, Suffix = "%"},
        {Key = "Size", Title = "Size", Description = "How far it reaches into the screen.", Kind = "Slider", Min = 10, Max = 60, Default = 32, Suffix = "%"},
        {Key = "Tint", Title = "Colour", Kind = "Dropdown", Options = {"Black", "Warm", "Cool"}, Default = "Black"},
    },
    Notes = {"Drawn as an overlay under the game's own interface."},
    Apply = function(self)
        local cfg = self.Config
        local layer = Overlay.layer("Vignette", 4)
        layer:ClearAllChildren()
        local color = ({Black = BLACK, Warm = Color3.fromRGB(40, 18, 6), Cool = Color3.fromRGB(4, 14, 34)})[cfg.Tint] or BLACK
        local size, strength = cfg.Size / 100, cfg.Intensity / 100
        local fade = NumberSequence.new({NumberSequenceKeypoint.new(0, 1 - strength * 0.85), NumberSequenceKeypoint.new(0.35, 1 - strength * 0.4),
            NumberSequenceKeypoint.new(0.7, 1 - strength * 0.1), NumberSequenceKeypoint.new(1, 1)})
        local sides = {
            {UDim2.new(1, 0, size, 0), UDim2.fromScale(0, 0), 90},
            {UDim2.new(1, 0, size, 0), UDim2.fromScale(0, 1 - size), -90},
            {UDim2.new(size, 0, 1, 0), UDim2.fromScale(0, 0), 0},
            {UDim2.new(size, 0, 1, 0), UDim2.fromScale(1 - size, 0), 180},
        }
        for _, side in ipairs(sides) do
            local frame = new("Frame", {Size = side[1], Position = side[2], BackgroundColor3 = color, BorderSizePixel = 0}, layer)
            new("UIGradient", {Rotation = side[3], Transparency = fade}, frame)
        end
    end,
    Update = function(self) if not (Overlay.Gui and Overlay.Gui:FindFirstChild("Vignette")) then self:Apply() end end,
    Stop = function() Overlay.drop("Vignette") end,
})

-- -----------------------------------------------------------------------------
-- Lens flare: ghosts, halo, anamorphic streaks and lens dirt from the sun and nearby lamps.
-- -----------------------------------------------------------------------------
local Lamps = {Set = {}, List = {}, Scanning = false}
local function isLamp(inst) return inst:IsA("PointLight") or inst:IsA("SpotLight") or inst:IsA("SurfaceLight") end
function Lamps.add(inst)
    if Lamps.Set[inst] or not isLamp(inst) then return end
    Lamps.Set[inst] = true
    table.insert(Lamps.List, inst)
end
function Lamps.start()
    if Lamps.Connection then return end
    Lamps.Connection = Workspace.DescendantAdded:Connect(function(inst) if isLamp(inst) then Lamps.add(inst) end end)
    Lamps.Scanning = true
    task.spawn(function()
        local all = Workspace:GetDescendants()
        for index, inst in ipairs(all) do
            if not Lamps.Connection then return end
            if isLamp(inst) then Lamps.add(inst) end
            if index % 4000 == 0 then task.wait() end
        end
        Lamps.Scanning = false
    end)
end
function Lamps.stop()
    if Lamps.Connection then Lamps.Connection:Disconnect() end
    Lamps.Connection = nil
    Lamps.Set, Lamps.List = {}, {}
end
function Lamps.position(light)
    local parent = light.Parent
    if not parent then return nil end
    if parent:IsA("Attachment") then return parent.WorldPosition end
    if parent:IsA("BasePart") then return parent.Position end
    return nil
end
-- The brightest lamps near the camera, closest first.
function Lamps.near(limit, range)
    local found = {}
    for index = #Lamps.List, 1, -1 do
        local light = Lamps.List[index]
        if light.Parent == nil then
            Lamps.Set[light] = nil
            table.remove(Lamps.List, index)
        elseif light.Enabled and light.Brightness >= 0.4 and light.Range >= 4 then
            local position = Lamps.position(light)
            if position then
                local distance = (position - Scene.Eye).Magnitude
                if distance < range then table.insert(found, {Light = light, Position = position, Distance = distance}) end
            end
        end
    end
    table.sort(found, function(a, b) return a.Distance < b.Distance end)
    while #found > limit do table.remove(found) end
    return found
end

local GHOSTS = {
    {-0.35, 0.09, Color3.fromRGB(255, 170, 90)}, {-0.62, 0.05, Color3.fromRGB(120, 255, 170)}, {0.42, 0.04, Color3.fromRGB(110, 170, 255)},
    {-1.05, 0.14, Color3.fromRGB(190, 120, 255)}, {-1.4, 0.07, Color3.fromRGB(120, 230, 255)}, {0.75, 0.11, Color3.fromRGB(255, 220, 120)},
    {-0.18, 0.03, Color3.fromRGB(255, 120, 120)}, {-1.8, 0.2, Color3.fromRGB(150, 180, 255)},
}
local function circle(parent, color, zindex)
    local frame = new("Frame", {AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = color, BorderSizePixel = 0, BackgroundTransparency = 1, ZIndex = zindex or 1}, parent)
    new("UICorner", {CornerRadius = UDim.new(0.5, 0)}, frame)
    return frame
end
local function streak(parent, color)
    local frame = new("Frame", {AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = color, BorderSizePixel = 0, BackgroundTransparency = 1}, parent)
    new("UIGradient", {Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0),
        NumberSequenceKeypoint.new(1, 1)})}, frame)
    return frame
end

defineEffect({
    Id = "flare", Title = "Lens flare", Icon = "circle-check", Default = false,
    Description = "Ghosts, halo, streaks and dirt from bright lights.",
    Notes = {"The sun's position is projected onto the screen and a few rays check how much of it is hidden, so the flare fades behind trees and walls.",
        "Ghosts are reflections inside the lens: they sit on the line from the light through the centre of the screen. Lens dirt lights up when a bright light is near it.",
        "Lamps adds small flares to the nearest bright lights in the game."},
    Params = {
        {Key = "Intensity", Title = "Intensity", Kind = "Slider", Min = 0, Max = 100, Default = 60, Suffix = "%"},
        {Key = "Ghosts", Title = "Ghosts", Kind = "Stepper", Min = 0, Max = 8, Default = 6},
        {Key = "Halo", Title = "Halo", Kind = "Toggle", Default = true},
        {Key = "Streaks", Title = "Streaks", Kind = "Toggle", Default = true},
        {Key = "Length", Title = "Streak length", Kind = "Slider", Min = 10, Max = 100, Default = 55, Suffix = "%"},
        {Key = "Dirt", Title = "Lens dirt", Kind = "Slider", Min = 0, Max = 100, Default = 35, Suffix = "%"},
        {Key = "Lamps", Title = "Flares from lamps", Kind = "Toggle", Default = true},
    },
    Start = function(self)
        self.Visible = 0
        self.LampFlares = {}
        Lamps.start()
    end,
    Apply = function(self)
        local layer = Overlay.layer("Flare", 5)
        layer:ClearAllChildren()
        local cfg = self.Config
        local parts = {Glow = {}, Ghosts = {}, Dirt = {}}
        parts.Glow[1] = circle(layer, Color3.fromRGB(255, 244, 220), 3)
        parts.Glow[2] = circle(layer, Color3.fromRGB(255, 220, 170), 2)
        parts.Glow[3] = circle(layer, Color3.fromRGB(255, 200, 150), 1)
        if cfg.Halo then
            parts.Halo = circle(layer, WHITE, 1)
            parts.HaloStroke = new("UIStroke", {Thickness = 4, Color = Color3.fromRGB(255, 210, 170), Transparency = 1}, parts.Halo)
        end
        for index = 1, cfg.Ghosts do
            local spec = GHOSTS[index]
            parts.Ghosts[index] = {Frame = circle(layer, spec[3], 1), Offset = spec[1], Size = spec[2]}
        end
        if cfg.Streaks then
            parts.Streak = streak(layer, Color3.fromRGB(170, 205, 255))
            parts.Streak2 = streak(layer, Color3.fromRGB(120, 160, 255))
        end
        local rng = Random.new(42)
        for index = 1, 14 do
            parts.Dirt[index] = {Frame = circle(layer, Color3.fromRGB(255, 236, 210), 0), X = rng:NextNumber(0.05, 0.95), Y = rng:NextNumber(0.05, 0.95),
                Size = rng:NextNumber(0.05, 0.16), Weight = rng:NextNumber(0.5, 1)}
        end
        self.Parts = parts
        self.Layer = layer
        for _, flare in pairs(self.LampFlares) do pcall(function() flare.Root:Destroy() end) end
        self.LampFlares = {}
    end,
    Update = function(self, dt, now)
        if not alive(self.Layer) then self:Apply() end
        local cfg, parts, camera = self.Config, self.Parts, Scene.Camera
        if not camera or not parts then return end
        local viewport = Scene.Viewport
        local center = viewport / 2
        local strength = cfg.Intensity / 100
        -- Sun visibility from five rays in a small cone around the sun direction.
        local target = 0
        local sunPoint, onScreen = camera:WorldToViewportPoint(Scene.Eye + Scene.Sun * 4000)
        if onScreen and Scene.Day > 0.05 and Scene.Sun.Y > -0.05 then
            if now >= (self.NextRays or 0) then
                self.NextRays = now + 0.05
                local right = Scene.Sun:Cross(UP)
                if right.Magnitude < 1e-3 then right = Vector3.new(1, 0, 0) end
                right = right.Unit
                local up = right:Cross(Scene.Sun).Unit
                local clear = 0
                for _, offset in ipairs({Vector3.zero, right * 0.012, -right * 0.012, up * 0.012, -up * 0.012}) do
                    if not Scene.cast(Scene.Eye, (Scene.Sun + offset).Unit * 2000, Scene.SolidParams) then clear = clear + 1 end
                end
                self.Clear = clear / 5
            end
            local edge = math.max(math.abs(sunPoint.X - center.X) / center.X, math.abs(sunPoint.Y - center.Y) / center.Y)
            target = (self.Clear or 0) * clamp((1.15 - edge) * 3, 0, 1) * Scene.Day
        end
        self.Visible = approach(self.Visible, target, 10, dt)
        local v = self.Visible * strength
        local sun = Vector2.new(sunPoint.X, sunPoint.Y)
        local axis = sun - center
        local unit = math.min(viewport.X, viewport.Y)
        local show = v > 0.01
        for index, glow in ipairs(parts.Glow) do
            local size = unit * ({0.06, 0.16, 0.34})[index]
            glow.Position = UDim2.fromOffset(sun.X, sun.Y)
            glow.Size = UDim2.fromOffset(size, size)
            glow.BackgroundTransparency = show and (1 - v * ({0.55, 0.25, 0.1})[index]) or 1
        end
        if parts.Halo then
            local size = unit * 0.62
            parts.Halo.Position = UDim2.fromOffset(sun.X, sun.Y)
            parts.Halo.Size = UDim2.fromOffset(size, size)
            parts.HaloStroke.Transparency = show and (1 - v * 0.18) or 1
            parts.HaloStroke.Thickness = math.max(2, unit * 0.006)
        end
        for _, ghost in ipairs(parts.Ghosts) do
            local position = center + axis * ghost.Offset
            local size = unit * ghost.Size
            ghost.Frame.Position = UDim2.fromOffset(position.X, position.Y)
            ghost.Frame.Size = UDim2.fromOffset(size, size)
            ghost.Frame.BackgroundTransparency = show and (1 - v * 0.16) or 1
        end
        if parts.Streak then
            local length = viewport.X * (0.4 + cfg.Length / 100 * 1.4)
            parts.Streak.Position = UDim2.fromOffset(sun.X, sun.Y)
            parts.Streak.Size = UDim2.fromOffset(length, math.max(2, unit * 0.005))
            parts.Streak.BackgroundTransparency = show and (1 - v * 0.7) or 1
            parts.Streak2.Position = UDim2.fromOffset(sun.X, sun.Y)
            parts.Streak2.Size = UDim2.fromOffset(length * 0.6, math.max(6, unit * 0.022))
            parts.Streak2.BackgroundTransparency = show and (1 - v * 0.18) or 1
        end
        local dirt = cfg.Dirt / 100
        for _, spot in ipairs(parts.Dirt) do
            local position = Vector2.new(spot.X * viewport.X, spot.Y * viewport.Y)
            local near = clamp(1 - (position - sun).Magnitude / (unit * 0.9), 0, 1)
            local size = unit * spot.Size
            spot.Frame.Position = UDim2.fromOffset(position.X, position.Y)
            spot.Frame.Size = UDim2.fromOffset(size, size)
            spot.Frame.BackgroundTransparency = 1 - v * dirt * near * spot.Weight * 0.22
        end
        -- Lamps.
        local wanted = cfg.Lamps and cap("Lamps") or 0
        local lamps = wanted > 0 and Lamps.near(wanted, 110) or {}
        local seen = {}
        for _, lamp in ipairs(lamps) do
            local point, visible = camera:WorldToViewportPoint(lamp.Position)
            local flare = self.LampFlares[lamp.Light]
            if not flare then
                local root = new("Frame", {Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1}, self.Layer)
                flare = {Root = root, Glow = circle(root, WHITE, 2), Streak = streak(root, WHITE), Level = 0, Clear = 0}
                self.LampFlares[lamp.Light] = flare
            end
            seen[lamp.Light] = true
            if visible and now >= (flare.NextRay or 0) then
                flare.NextRay = now + 0.12
                local hit = Scene.cast(Scene.Eye, lamp.Position - Scene.Eye, Scene.SolidParams)
                local holder = lamp.Light.Parent
                flare.Clear = (not hit or hit.Instance == holder or (hit.Position - lamp.Position).Magnitude < 1.5) and 1 or 0
            end
            local power = clamp(lamp.Light.Brightness / 3, 0, 1.5) * clamp(1 - lamp.Distance / 110, 0, 1)
            flare.Level = approach(flare.Level, visible and flare.Clear * power or 0, 10, dt)
            local level = flare.Level * strength
            local size = unit * (0.05 + 0.12 * power) * clamp(30 / math.max(lamp.Distance, 6), 0.4, 2)
            flare.Glow.BackgroundColor3 = lamp.Light.Color
            flare.Glow.Position = UDim2.fromOffset(point.X, point.Y)
            flare.Glow.Size = UDim2.fromOffset(size, size)
            flare.Glow.BackgroundTransparency = 1 - level * 0.45
            flare.Streak.BackgroundColor3 = lamp.Light.Color
            flare.Streak.Position = UDim2.fromOffset(point.X, point.Y)
            flare.Streak.Size = UDim2.fromOffset(size * 5 * (0.4 + cfg.Length / 100), math.max(2, size * 0.05))
            flare.Streak.BackgroundTransparency = cfg.Streaks and (1 - level * 0.6) or 1
        end
        for light, flare in pairs(self.LampFlares) do
            if not seen[light] then
                pcall(function() flare.Root:Destroy() end)
                self.LampFlares[light] = nil
            end
        end
        self.Info = self.Visible > 0.05 and ("Sun " .. formatNumber(self.Visible * 100) .. "% visible") or (#lamps > 0 and (#lamps .. " lamps nearby") or "Sun not in view")
    end,
    Stop = function(self)
        Overlay.drop("Flare")
        Lamps.stop()
        self.LampFlares = {}
        self.Parts = nil
    end,
})

-- -----------------------------------------------------------------------------
-- Zeal Rim Light: an outline glow plus a light behind each character, opposite the camera.
-- -----------------------------------------------------------------------------
defineEffect({
    Id = "rim", Title = "Zeal Rim Light", Icon = "user", Default = false,
    Description = "A bright edge that lifts subjects off their background.",
    Notes = {"Each character near you gets a soft outline in the rim colour and, optionally, a small light placed behind it (on the far side from the camera) so its edges catch light.",
        "Roblox draws at most 31 outlines at once; the nearest characters get them first."},
    Params = {
        {Key = "Intensity", Title = "Intensity", Kind = "Slider", Min = 0, Max = 100, Default = 60, Suffix = "%"},
        {Key = "Hue", Title = "Colour", Kind = "Slider", Min = 0, Max = 360, Default = 205, Suffix = "°"},
        {Key = "Saturation", Title = "Colour strength", Kind = "Slider", Min = 0, Max = 100, Default = 35, Suffix = "%"},
        {Key = "Outline", Title = "Edge outline", Kind = "Toggle", Default = true},
        {Key = "Backlight", Title = "Back light", Kind = "Toggle", Default = true},
        {Key = "Targets", Title = "Who", Kind = "Dropdown", Options = {"Everyone", "Players", "Only me"}, Default = "Players"},
        {Key = "Range", Title = "Range", Kind = "Slider", Min = 20, Max = 300, Default = 120, Suffix = " studs"},
    },
    Start = function(self) self.Items = {} end,
    Update = function(self, dt, now)
        local cfg = self.Config
        local color = hueColor(cfg.Hue, cfg.Saturation / 100, 1)
        local strength = cfg.Intensity / 100
        if now >= (self.NextList or 0) then
            self.NextList = now + 0.4
            local list = {}
            for _, character in ipairs(Scene.Characters) do
                if cfg.Targets ~= "Only me" or character.Local then table.insert(list, character) end
            end
            if cfg.Targets == "Everyone" then
                for _, npc in ipairs(Scene.npcsNear(Scene.Eye, cfg.Range, 12)) do table.insert(list, npc) end
            end
            for _, item in ipairs(list) do item.Distance = (item.Root.Position - Scene.Eye).Magnitude end
            table.sort(list, function(a, b) return a.Distance < b.Distance end)
            self.Targets = list
        end
        local outlines, lights, seen = cap("Highlights"), math.max(2, cap("Lights")), {}
        for index, target in ipairs(self.Targets or {}) do
            if target.Distance <= cfg.Range and alive(target.Root) then
                local item = self.Items[target.Model]
                if not item then
                    item = {}
                    self.Items[target.Model] = item
                end
                seen[target.Model] = true
                if cfg.Outline and index <= outlines then
                    if not alive(item.Highlight) then
                        item.Highlight = new("Highlight", {Adornee = target.Model, FillTransparency = 1, DepthMode = Enum.HighlightDepthMode.Occluded}, World.child("Rim"))
                    end
                    item.Highlight.OutlineColor = color
                    item.Highlight.OutlineTransparency = 1 - strength * 0.75
                    item.Highlight.Enabled = true
                elseif item.Highlight then
                    item.Highlight:Destroy()
                    item.Highlight = nil
                end
                if cfg.Backlight and index <= lights then
                    if not alive(item.Point) then
                        item.Point = World.attachment("Rim")
                        item.Light = new("PointLight", {Shadows = false}, item.Point)
                    end
                    local root = target.Root.Position
                    local away = root - Scene.Eye
                    away = Vector3.new(away.X, 0, away.Z)
                    away = away.Magnitude > 0.1 and away.Unit or Vector3.new(0, 0, 1)
                    item.Point.WorldPosition = root + away * 3 + UP * 1.6
                    item.Light.Color = color
                    item.Light.Brightness = 1 + strength * 4
                    item.Light.Range = 6 + strength * 5
                    item.Light.Enabled = true
                elseif item.Point then
                    item.Point:Destroy()
                    item.Point = nil
                end
            end
        end
        local count = 0
        for model, item in pairs(self.Items) do
            if not seen[model] then
                if item.Highlight then item.Highlight:Destroy() end
                if item.Point then item.Point:Destroy() end
                self.Items[model] = nil
            else
                count = count + 1
            end
        end
        self.Info = count .. " lit"
    end,
    Stop = function(self)
        for _, item in pairs(self.Items or {}) do
            if item.Highlight then pcall(function() item.Highlight:Destroy() end) end
            if item.Point then pcall(function() item.Point:Destroy() end) end
        end
        self.Items = {}
        local folder = World.Folder and World.Folder:FindFirstChild("Rim")
        if folder then folder:Destroy() end
    end,
})

-- -----------------------------------------------------------------------------
-- MXAO: soft shading where objects meet the floor and the ceiling, contact shadows under characters,
-- and an optional tint of bounce light from the object's colour.
-- -----------------------------------------------------------------------------
local AO = {}
local function shadeSequence(peak)
    return NumberSequence.new({NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.28, 1 - peak * 0.12),
        NumberSequenceKeypoint.new(0.42, 1 - peak * 0.55), NumberSequenceKeypoint.new(0.5, 1 - peak),
        NumberSequenceKeypoint.new(0.58, 1 - peak * 0.55), NumberSequenceKeypoint.new(0.72, 1 - peak * 0.12), NumberSequenceKeypoint.new(1, 1)})
end
local function bounceSequence(peak)
    return NumberSequence.new({NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.15, 1 - peak * 0.35),
        NumberSequenceKeypoint.new(0.5, 1 - peak), NumberSequenceKeypoint.new(0.85, 1 - peak * 0.35), NumberSequenceKeypoint.new(1, 1)})
end
-- A card lying on a surface, centred on a crease line. Half of it sits under the object and is hidden,
-- so a symmetric gradient reads as shading that fades away from the object.
function AO.card(center, normal, along, length, width, color)
    local cf = CFrame.fromMatrix(center + normal * 0.02, along, (-normal):Cross(along))
    local part = World.part({Name = "Crease", Size = Vector3.new(math.max(length, 0.2), width, 0.02), CFrame = cf}, World.child("AO"))
    local gui = new("SurfaceGui", {Face = Enum.NormalId.Front, SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud, PixelsPerStud = 6,
        LightInfluence = 1, AlwaysOnTop = false, ClipsDescendants = true, Adornee = part}, part)
    local bounce = new("Frame", {Size = UDim2.fromScale(1, 1), BackgroundColor3 = color or WHITE, BorderSizePixel = 0, ZIndex = 1}, gui)
    local bounceGradient = new("UIGradient", {Rotation = 90}, bounce)
    local shade = new("Frame", {Size = UDim2.fromScale(1, 1), BackgroundColor3 = BLACK, BorderSizePixel = 0, ZIndex = 2}, gui)
    local shadeGradient = new("UIGradient", {Rotation = 90}, shade)
    return {Part = part, Shade = shadeGradient, Bounce = bounceGradient, BounceFrame = bounce}
end
function AO.style(card, cfg)
    local peak = cfg.Intensity / 100 * 0.62
    card.Shade.Transparency = shadeSequence(peak)
    local bounce = cfg.Bounce and cfg.BounceStrength / 100 * 0.3 or 0
    card.BounceFrame.Visible = bounce > 0
    if bounce > 0 then card.Bounce.Transparency = bounceSequence(bounce) end
end
local EDGE_SKIP = {WedgePart = true, CornerWedgePart = true, TrussPart = true, Seat = true, VehicleSeat = true, SpawnLocation = false}
function AO.creases(part, cfg, params)
    local cards = {}
    if part.Transparency > 0.25 or not part.Anchored or EDGE_SKIP[part.ClassName] then return cards end
    if part:IsA("Part") and part.Shape ~= Enum.PartType.Block then return cards end
    local cf, size = part.CFrame, part.Size
    if cf.UpVector.Y < 0.985 or size.Y < 0.8 or math.min(size.X, size.Z) < 0.3 then return cards end
    local half = size / 2
    local width = cfg.Radius * 2
    local sides = {
        {Out = cf.RightVector, Extent = half.X, Along = cf.LookVector, Length = size.Z},
        {Out = -cf.RightVector, Extent = half.X, Along = cf.LookVector, Length = size.Z},
        {Out = cf.LookVector, Extent = half.Z, Along = cf.RightVector, Length = size.X},
        {Out = -cf.LookVector, Extent = half.Z, Along = cf.RightVector, Length = size.X},
    }
    local bottom = cf.Position - cf.UpVector * half.Y
    local top = cf.Position + cf.UpVector * half.Y
    for _, side in ipairs(sides) do
        local out = Vector3.new(side.Out.X, 0, side.Out.Z).Unit
        local along = Vector3.new(side.Along.X, 0, side.Along.Z).Unit
        local edge = bottom + side.Out * side.Extent
        local hit = Scene.cast(edge + out * 0.35 + UP * 1.2, Vector3.new(0, -3, 0), params)
        if hit and hit.Instance ~= part and hit.Normal.Y > 0.9 and hit.Position.Y >= edge.Y - 0.6 and hit.Position.Y <= edge.Y + 0.25 then
            table.insert(cards, AO.card(Vector3.new(edge.X, hit.Position.Y, edge.Z), hit.Normal, along, side.Length, width, part.Color))
        end
        if cfg.Ceilings and size.Y < 60 then
            local edgeTop = top + side.Out * side.Extent
            local up = Scene.cast(edgeTop + out * 0.35 - UP * 1.2, Vector3.new(0, 3, 0), params)
            if up and up.Instance ~= part and up.Normal.Y < -0.9 and up.Position.Y <= edgeTop.Y + 0.6 and up.Position.Y >= edgeTop.Y - 0.25 then
                table.insert(cards, AO.card(Vector3.new(edgeTop.X, up.Position.Y, edgeTop.Z), up.Normal, along, side.Length, width, part.Color))
            end
        end
    end
    for _, card in ipairs(cards) do AO.style(card, cfg) end
    return cards
end
-- A soft round shadow under a character: stacked circles, darkest in the middle.
function AO.blob()
    local part = World.part({Name = "Contact", Size = Vector3.new(5, 5, 0.02)}, World.child("AO"))
    local gui = new("SurfaceGui", {Face = Enum.NormalId.Front, SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud, PixelsPerStud = 16,
        LightInfluence = 1, AlwaysOnTop = false, Adornee = part}, part)
    local rings = {}
    for index, scale in ipairs({1, 0.8, 0.62, 0.46, 0.3}) do
        local ring = new("Frame", {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(scale, scale),
            BackgroundColor3 = BLACK, BorderSizePixel = 0, BackgroundTransparency = 1, ZIndex = index}, gui)
        new("UICorner", {CornerRadius = UDim.new(0.5, 0)}, ring)
        rings[index] = ring
    end
    return {Part = part, Rings = rings}
end

defineEffect({
    Id = "mxao", Title = "MXAO", Icon = "box", Default = false,
    Description = "Soft shadowing in corners and creases, with optional bounce light.",
    Notes = {"Roblox has no screen-space ambient occlusion, so it is built in the world: objects near you are checked for where they meet the floor or the ceiling, and a soft shading card is laid along each crease.",
        "Characters get a contact shadow that softens as they jump. Bounce light tints the shading with the object's own colour, like light reflected off it.",
        "Cards are only built around you and are recycled as you move."},
    Params = {
        {Key = "Intensity", Title = "Intensity", Kind = "Slider", Min = 0, Max = 100, Default = 60, Suffix = "%"},
        {Key = "Radius", Title = "Radius", Kind = "Slider", Min = 0.5, Max = 6, Step = 0.1, Default = 2.2, Suffix = " studs"},
        {Key = "Contact", Title = "Contact shadows", Description = "Under characters.", Kind = "Toggle", Default = true},
        {Key = "Creases", Title = "Floor creases", Kind = "Toggle", Default = true},
        {Key = "Ceilings", Title = "Ceiling creases", Kind = "Toggle", Default = true},
        {Key = "Bounce", Title = "Bounce light", Kind = "Toggle", Default = true},
        {Key = "BounceStrength", Title = "Bounce strength", Kind = "Slider", Min = 0, Max = 100, Default = 40, Suffix = "%"},
        {Key = "Range", Title = "Range", Kind = "Slider", Min = 30, Max = 250, Default = 90, Suffix = " studs"},
        {Key = "Objects", Title = "Objects", Description = "Most objects shaded at once.", Kind = "Slider", Min = 10, Max = 300, Default = 60},
    },
    Start = function(self)
        self.Parts, self.Blobs, self.Queue, self.CardCount = {}, {}, {}, 0
        self.Params = newRaycastParams()
        self.Overlap = OverlapParams.new()
        self.Overlap.FilterType = enumItem("RaycastFilterType", "Exclude") or Enum.RaycastFilterType.Blacklist
        pcall(function() self.Overlap.MaxParts = 2500 end)
    end,
    Apply = function(self)
        -- Restyle what exists; geometry changes (radius, ceilings) rebuild on the next scan.
        for part, entry in pairs(self.Parts or {}) do
            if entry.Radius ~= self.Config.Radius or entry.Ceilings ~= self.Config.Ceilings then
                for _, card in ipairs(entry.Cards) do pcall(function() card.Part:Destroy() end) end
                self.Parts[part] = nil
            else
                for _, card in ipairs(entry.Cards) do AO.style(card, self.Config) end
            end
        end
    end,
    Update = function(self, dt, now)
        local cfg = self.Config
        local exclude = table.clone(Scene.WorldParams.FilterDescendantsInstances)
        self.Params.FilterDescendantsInstances = exclude
        -- Creases: rescan the area twice a second, then build cards a few objects per frame.
        if cfg.Creases and now >= (self.NextScan or 0) then
            self.NextScan = now + 0.5
            self.Overlap.FilterDescendantsInstances = exclude
            local ok, found = pcall(function() return Workspace:GetPartBoundsInRadius(Scene.Focus, cfg.Range, self.Overlap) end)
            local list = {}
            if ok then
                for _, part in ipairs(found) do
                    if part.Anchored and part.Transparency < 0.25 and part.Size.Y >= 0.8 and not part:IsA("Terrain") then
                        table.insert(list, {Part = part, Distance = (part.Position - Scene.Focus).Magnitude})
                    end
                end
            end
            table.sort(list, function(a, b) return a.Distance < b.Distance end)
            local limit = math.min(cfg.Objects, cap("Cards"))
            local keep = {}
            for index = 1, math.min(#list, limit) do keep[list[index].Part] = true end
            for part, entry in pairs(self.Parts) do
                if not keep[part] or part.Parent == nil or entry.CFrame ~= part.CFrame then
                    for _, card in ipairs(entry.Cards) do pcall(function() card.Part:Destroy() end) end
                    self.CardCount = self.CardCount - #entry.Cards
                    self.Parts[part] = nil
                end
            end
            self.Queue = {}
            for index = 1, math.min(#list, limit) do
                local part = list[index].Part
                if not self.Parts[part] then table.insert(self.Queue, part) end
            end
        end
        local started = os.clock()
        while #self.Queue > 0 and os.clock() - started < 0.0015 do
            local part = table.remove(self.Queue, 1)
            if part.Parent then
                local cards = AO.creases(part, cfg, self.Params)
                self.Parts[part] = {Cards = cards, CFrame = part.CFrame, Radius = cfg.Radius, Ceilings = cfg.Ceilings}
                self.CardCount = self.CardCount + #cards
            end
        end
        if not cfg.Creases and next(self.Parts) then
            for _, entry in pairs(self.Parts) do for _, card in ipairs(entry.Cards) do pcall(function() card.Part:Destroy() end) end end
            self.Parts, self.CardCount = {}, 0
        end
        -- Contact shadows under characters.
        local seen = {}
        if cfg.Contact then
            for _, character in ipairs(Scene.Characters) do
                local root = character.Root
                if alive(root) and (root.Position - Scene.Eye).Magnitude < cfg.Range then
                    seen[character.Model] = true
                    local blob = self.Blobs[character.Model]
                    if not blob or not alive(blob.Part) then
                        blob = AO.blob()
                        self.Blobs[character.Model] = blob
                    end
                    local hit = Scene.cast(root.Position, Vector3.new(0, -14, 0), self.Params)
                    if hit then
                        local hip = character.Humanoid and character.Humanoid.HipHeight or 2
                        local height = math.max(0, (root.Position.Y - hit.Position.Y) - hip - root.Size.Y / 2)
                        local fade = clamp(1 - height / 9, 0, 1)
                        local width = 4.2 + height * 0.25
                        local normal = hit.Normal
                        local along = normal:Cross(Vector3.new(0, 0, 1))
                        if along.Magnitude < 0.1 then along = normal:Cross(Vector3.new(1, 0, 0)) end
                        along = along.Unit
                        blob.Part.Size = Vector3.new(width, width, 0.02)
                        blob.Part.CFrame = CFrame.fromMatrix(hit.Position + normal * 0.025, along, (-normal):Cross(along))
                        for _, ring in ipairs(blob.Rings) do ring.BackgroundTransparency = 1 - cfg.Intensity / 100 * 0.16 * fade end
                    else
                        for _, ring in ipairs(blob.Rings) do ring.BackgroundTransparency = 1 end
                    end
                end
            end
        end
        for model, blob in pairs(self.Blobs) do
            if not seen[model] then
                pcall(function() blob.Part:Destroy() end)
                self.Blobs[model] = nil
            end
        end
        self.Info = self.CardCount .. " shading cards"
    end,
    Stop = function(self)
        local folder = World.Folder and World.Folder:FindFirstChild("AO")
        if folder then folder:Destroy() end
        self.Parts, self.Blobs, self.Queue, self.CardCount = {}, {}, {}, 0
    end,
})

-- -----------------------------------------------------------------------------
-- SSR: real-time planar reflections.
--
-- For each reflective surface near the camera (a floor, a wall, a ceiling, a water plane) a thin invisible
-- part lies on it carrying a SurfaceGui with a ViewportFrame. The ViewportFrame holds copies of the
-- characters and objects nearby, mirrored across the surface, and its camera sits exactly at the real
-- camera, looking straight into the surface. With the camera perpendicular to the surface the mapping
-- from the image to the surface is a plain scale and offset, so the ViewportFrame is sized and placed
-- inside the SurfaceGui (an off-axis projection) and the mirrored world lines up with the real one at any
-- angle. The surface itself hides everything in front of it, so reflections are occluded correctly.
-- -----------------------------------------------------------------------------
local MATERIAL_LOOK = {
    Glass = {0.85, 0}, Ice = {0.6, 0.1}, Glacier = {0.4, 0.3}, Marble = {0.55, 0.1}, Granite = {0.35, 0.3}, SmoothPlastic = {0.42, 0.15},
    Plastic = {0.3, 0.35}, Metal = {0.6, 0.25, true}, DiamondPlate = {0.45, 0.35, true}, Foil = {0.65, 0.2, true}, CorrodedMetal = {0.15, 0.6, true},
    Neon = {0.2, 0.3}, ForceField = {0, 1}, Wood = {0.18, 0.55}, WoodPlanks = {0.2, 0.5}, Slate = {0.18, 0.55}, Concrete = {0.1, 0.75},
    Brick = {0.06, 0.85}, Cobblestone = {0.08, 0.8}, Pebble = {0.1, 0.7}, Fabric = {0.02, 1}, Sand = {0.03, 1}, Grass = {0.02, 1},
    LeafyGrass = {0.02, 1}, Ground = {0.03, 1}, Mud = {0.12, 0.6}, Asphalt = {0.12, 0.7}, Basalt = {0.15, 0.6}, Rock = {0.08, 0.8},
    Sandstone = {0.08, 0.8}, Limestone = {0.12, 0.7}, Pavement = {0.15, 0.6}, CrackedLava = {0.1, 0.7}, Salt = {0.1, 0.7}, Snow = {0.08, 0.8},
    Cardboard = {0.03, 1}, Carpet = {0.01, 1}, CeramicTiles = {0.5, 0.15}, ClayRoofTiles = {0.2, 0.5}, RoofShingles = {0.06, 0.8},
    Leather = {0.15, 0.6}, Plaster = {0.1, 0.7}, Rubber = {0.12, 0.6}, Water = {0.7, 0.05},
}
local function materialLook(material)
    local look = MATERIAL_LOOK[material and material.Name or ""] or {0.2, 0.5}
    return look[1], look[2], look[3] == true
end

local MIRROR_LIFT, MIRROR_THICK = 0.05, 0.02
local TAN_LIMIT = math.tan(math.rad(118) / 2)
local KEEP_IN_CLONE = {SpecialMesh = true, BlockMesh = true, CylinderMesh = true, FileMesh = true, Decal = true, Texture = true, SurfaceAppearance = true}

-- Mirrors a CFrame across a plane and negates its X axis, so it stays a proper rotation; boxes, wedges and
-- most character meshes are symmetric along X, so the copy has the mirrored shape.
local function mirrorer(point, normal)
    local nx, ny, nz = normal.X, normal.Y, normal.Z
    local offset = point.X * nx + point.Y * ny + point.Z * nz
    return function(cf)
        local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = cf:GetComponents()
        local distance = x * nx + y * ny + z * nz - offset
        local dx = r00 * nx + r10 * ny + r20 * nz
        local dy = r01 * nx + r11 * ny + r21 * nz
        local dz = r02 * nx + r12 * ny + r22 * nz
        return CFrame.new(x - 2 * distance * nx, y - 2 * distance * ny, z - 2 * distance * nz,
            -(r00 - 2 * dx * nx), r01 - 2 * dy * nx, r02 - 2 * dz * nx,
            -(r10 - 2 * dx * ny), r11 - 2 * dy * ny, r12 - 2 * dz * ny,
            -(r20 - 2 * dx * nz), r21 - 2 * dy * nz, r22 - 2 * dz * nz)
    end
end

-- Where the viewport goes inside a mirror's SurfaceGui and which camera renders it. U and V are the
-- canvas X and Y directions, W x H the canvas in studs, face its centre, eye the real camera.
local function mirrorProjection(eye, face, normal, U, V, W, H, maxTan)
    local rel = eye - face
    local d = rel:Dot(normal)
    if d < 0.15 then return nil end
    local eu, ev = rel:Dot(U), rel:Dot(V)
    local hu = math.max(math.abs(eu + W / 2), math.abs(eu - W / 2))
    local hv = math.max(math.abs(ev + H / 2), math.abs(ev - H / 2))
    local tx = clamp(hu / d, 0.02, maxTan or 1e6)
    local ty = clamp(hv / d, 0.02, math.min(TAN_LIMIT, maxTan or 1e6))
    return {
        FieldOfView = math.deg(2 * math.atan(ty)),
        CFrame = CFrame.fromMatrix(eye, U, -V),
        Position = UDim2.fromScale((eu - d * tx + W / 2) / W, (ev - d * ty + H / 2) / H),
        Size = UDim2.fromScale(2 * d * tx / W, 2 * d * ty / H),
        Distance = d,
    }
end

-- The rectangular face of a part that a ray hit, or nil for round, sloped or irregular surfaces.
local function faceOf(part, result)
    local cf, size = part.CFrame, part.Size
    local normal = cf:VectorToObjectSpace(result.Normal)
    local axis, sign
    if math.abs(normal.X) > 0.995 then axis, sign = 1, normal.X > 0 and 1 or -1
    elseif math.abs(normal.Y) > 0.995 then axis, sign = 2, normal.Y > 0 and 1 or -1
    elseif math.abs(normal.Z) > 0.995 then axis, sign = 3, normal.Z > 0 and 1 or -1
    else return nil end
    local localPoint = cf:PointToObjectSpace(result.Position)
    local coords, half = {localPoint.X, localPoint.Y, localPoint.Z}, {size.X / 2, size.Y / 2, size.Z / 2}
    if math.abs(math.abs(coords[axis]) - half[axis]) > 0.15 then return nil end
    if part:IsA("Part") then
        if part.Shape ~= Enum.PartType.Block then return nil end
    elseif part:IsA("MeshPart") or part:IsA("PartOperation") then
        -- Meshes only when they are flat slabs (floor tiles, rugs, platforms).
        local others = {}
        for i = 1, 3 do if i ~= axis then table.insert(others, half[i]) end end
        if size[({"X", "Y", "Z"})[axis]] > 2 or others[1] < 2 or others[2] < 2 then return nil end
    else
        return nil
    end
    local vectors = {cf.RightVector, cf.UpVector, -cf.LookVector}
    local worldNormal = vectors[axis] * sign
    local a, b
    for i = 1, 3 do
        if i ~= axis then
            if not a then a = i else b = i end
        end
    end
    return {Part = part, Normal = worldNormal, Center = cf.Position + worldNormal * half[axis], A = vectors[a], B = vectors[b],
        HalfA = half[a], HalfB = half[b]}
end
local function planeKey(normal, point)
    local function q(v) return math.floor(v * 100 + 0.5) end
    return q(normal.X) .. "," .. q(normal.Y) .. "," .. q(normal.Z) .. "@" .. math.floor(normal:Dot(point) * 20 + 0.5)
end
local function surfaceKind(normal)
    if normal.Y > 0.8 then return "Floors" elseif normal.Y < -0.8 then return "Ceilings" elseif math.abs(normal.Y) < 0.25 then return "Walls" end
    return nil
end

-- A plain copy of a part for a viewport: just the look, never scripts, sounds, lights or joints.
local function visualCopy(source)
    local copy
    if source:IsA("Part") and not source:FindFirstChildWhichIsA("DataModelMesh") then
        copy = Instance.new("Part")
        copy.Shape = source.Shape
        copy.Size = source.Size
        for _, child in ipairs(source:GetChildren()) do
            if child:IsA("Decal") then
                local ok, decal = pcall(function() return child:Clone() end)
                if ok and decal then decal.Parent = copy end
            end
        end
    else
        local archivable = source.Archivable
        if not archivable then pcall(function() source.Archivable = true end) end
        local ok, result = pcall(function() return source:Clone() end)
        if not archivable then pcall(function() source.Archivable = false end) end
        if not ok or not result then return nil end
        copy = result
        for _, item in ipairs(copy:GetDescendants()) do
            if not KEEP_IN_CLONE[item.ClassName] then pcall(function() item:Destroy() end) end
        end
    end
    copy.Name = source.Name
    copy.Anchored = true
    copy.CanCollide = false
    copy.CanQuery = false
    copy.CanTouch = false
    copy.CastShadow = false
    copy.Massless = true
    copy.Color = source.Color
    copy.Material = source.Material
    copy.Transparency = source.Transparency
    copy.Reflectance = source.Reflectance
    return copy
end
local function characterParts(model)
    local list = {}
    for _, item in ipairs(model:GetDescendants()) do
        if item:IsA("BasePart") and item.Name ~= "HumanoidRootPart" and item.Transparency < 0.98 and not item:FindFirstChildOfClass("WrapLayer") then
            table.insert(list, item)
        end
    end
    return list
end
-- An empty character for a viewport: a Humanoid (so clothing shows) and the clothing itself.
local function characterShell(model)
    local shell = Instance.new("Model")
    shell.Name = model.Name
    local source = model:FindFirstChildOfClass("Humanoid")
    local humanoid = Instance.new("Humanoid")
    pcall(function()
        humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
        humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
        if source then humanoid.RigType = source.RigType end
    end)
    humanoid.Parent = shell
    for _, child in ipairs(model:GetChildren()) do
        if child:IsA("Clothing") or child:IsA("ShirtGraphic") or child:IsA("BodyColors") then
            local ok, copy = pcall(function() return child:Clone() end)
            if ok and copy then copy.Parent = shell end
        end
    end
    return shell
end

local SSR = defineEffect({
    Id = "ssr", Title = "SSR", Icon = "refresh-cw", Default = true,
    Description = "Real-time reflections on floors, walls and glossy surfaces.",
    Notes = {"Reflections of players, your own character and the world around you, updated every frame.",
        "Rays across the screen find the biggest reflective surfaces in view (floor tiles on the same level are joined into one). Each gets a mirror: a copy of the nearby scene, flipped across the surface, seen from your camera.",
        "How strong a reflection is depends on the material (glass, marble, metal and polished plastic reflect most), the viewing angle (Fresnel) and how bright the surface is.",
        "Copies use simple lighting, and meshes keep their own handedness, so text and asymmetric meshes are not flipped. Looking very low along a long floor, the far part may not reflect: Roblox cameras stop at 120° of view."},
    Params = {
        {Key = "Strength", Title = "Strength", Kind = "Slider", Min = 0, Max = 100, Default = 55, Suffix = "%"},
        {Key = "Fresnel", Title = "Fresnel", Description = "Stronger reflections at grazing angles.", Kind = "Slider", Min = 0, Max = 100, Default = 60, Suffix = "%"},
        {Key = "Blur", Title = "Roughness", Description = "Softer, lower-resolution reflections.", Kind = "Slider", Min = 0, Max = 100, Default = 15, Suffix = "%"},
        {Key = "Tint", Title = "Surface tint", Description = "How much the surface colour tints its reflection.", Kind = "Slider", Min = 0, Max = 100, Default = 35, Suffix = "%"},
        {Key = "Floors", Title = "Floors", Kind = "Toggle", Default = true},
        {Key = "Walls", Title = "Walls", Kind = "Toggle", Default = true},
        {Key = "Ceilings", Title = "Ceilings", Kind = "Toggle", Default = false},
        {Key = "Water", Title = "Water", Kind = "Toggle", Default = true},
        {Key = "GlossyOnly", Title = "Glossy materials only", Description = "Skip rough materials like grass, fabric and brick.", Kind = "Toggle", Default = false},
        {Key = "Players", Title = "Characters", Description = "Players, you and nearby NPCs.", Kind = "Toggle", Default = true},
        {Key = "World", Title = "World objects", Kind = "Toggle", Default = true},
        {Key = "Surfaces", Title = "Surfaces", Description = "Most mirrors at once.", Kind = "Stepper", Min = 1, Max = 6, Default = 3},
        {Key = "Detail", Title = "Objects per mirror", Kind = "Slider", Min = 50, Max = 1500, Step = 25, Default = 400},
        {Key = "Range", Title = "Range", Kind = "Slider", Min = 40, Max = 400, Step = 10, Default = 160, Suffix = " studs"},
    },
})

function SSR:Start()
    self.Mirrors, self.Order, self.Hits, self.Queue, self.Nearby = {}, {}, {}, {}, {}
    self.ScanIndex, self.Columns, self.Rows = 0, 9, 7
    self.NextNearby, self.GatherTurn, self.Clones = 0, 0, 0
    self.Overlap = OverlapParams.new()
    self.Overlap.FilterType = enumItem("RaycastFilterType", "Exclude") or Enum.RaycastFilterType.Blacklist
    pcall(function() self.Overlap.MaxParts = 4000 end)
    self.Box = OverlapParams.new()
    self.Box.FilterType = self.Overlap.FilterType
    pcall(function() self.Box.MaxParts = 400 end)
end
function SSR:Apply()
    -- Surfaces that a new setting rules out go away on the next selection; resolution follows at once.
    for _, mirror in pairs(self.Mirrors or {}) do mirror.Signature = nil end
end

-- One step of the surface scan: rays through a 9 x 7 grid on the screen plus one straight down from you.
function SSR:scan(count)
    local camera = Scene.Camera
    if not camera then return end
    local total = self.Columns * self.Rows + 1
    for _ = 1, count do
        self.ScanIndex = self.ScanIndex + 1
        if self.ScanIndex > total then
            self:select()
            self.Hits = {}
            self.ScanIndex = 1
        end
        local origin, direction, weight, centre
        if self.ScanIndex == total then
            origin, direction, weight, centre = Scene.Focus + UP, Vector3.new(0, -25, 0), 4, 0
        else
            local index = self.ScanIndex - 1
            local x = (index % self.Columns + 0.5) / self.Columns
            local y = (math.floor(index / self.Columns) + 0.5) / self.Rows
            local ray = camera:ViewportPointToRay(x * Scene.Viewport.X, y * Scene.Viewport.Y)
            origin, direction = ray.Origin, ray.Direction * self.Config.Range
            weight, centre = 1, math.sqrt((x - 0.5) ^ 2 + (y - 0.5) ^ 2)
        end
        local hit = Scene.cast(origin, direction, Scene.WaterParams)
        if hit then self:collect(hit, weight, centre) end
    end
end
function SSR:collect(hit, weight, centre)
    local cfg = self.Config
    local part = hit.Instance
    local group
    if part:IsA("Terrain") then
        if not (cfg.Water and hit.Material == Enum.Material.Water and hit.Normal.Y > 0.7) then return end
        local level = math.floor(hit.Position.Y * 4 + 0.5) / 4
        local key = "water@" .. level
        group = self.Hits[key]
        if not group then
            local reflectivity, roughness = materialLook(Enum.Material.Water)
            group = {Key = key, Water = true, Normal = UP, Point = Vector3.new(0, level, 0), A = Vector3.new(1, 0, 0), B = Vector3.new(0, 0, 1),
                Weight = 0, Reflectivity = reflectivity, Roughness = roughness, Metal = false, Color = Workspace.Terrain.WaterColor, Faces = {}}
            self.Hits[key] = group
        end
    else
        if part.Transparency > 0.6 then return end
        local face = faceOf(part, hit)
        if not face then return end
        local kind = surfaceKind(face.Normal)
        if not kind or not cfg[kind] then return end
        local reflectivity, roughness, metal = materialLook(part.Material)
        if cfg.GlossyOnly and reflectivity < 0.3 then return end
        if reflectivity <= 0.01 then return end
        local key = planeKey(face.Normal, face.Center)
        group = self.Hits[key]
        if not group then
            group = {Key = key, Normal = face.Normal, Point = face.Center, A = face.A, B = face.B, Weight = 0, Faces = {}, Kind = kind}
            self.Hits[key] = group
        end
        local known = group.Faces[part]
        if not known then
            face.Weight = 0
            face.Reflectivity, face.Roughness, face.Metal = reflectivity, roughness, metal
            group.Faces[part] = face
            known = face
        end
        known.Weight = known.Weight + weight
    end
    group.Weight = group.Weight + weight
    if not group.Sample or centre < group.SampleCentre then
        group.Sample, group.SampleCentre = hit.Position, centre
    end
end

-- Coplanar faces around the eye, so a floor made of tiles becomes one mirror.
function SSR:region(group, half)
    if group.Water then return nil end
    local best, bestWeight = nil, -1
    for _, face in pairs(group.Faces) do
        if face.Weight > bestWeight then best, bestWeight = face, face.Weight end
    end
    if not best then return nil end
    group.A, group.B, group.Point = best.A, best.B, best.Center
    group.Reflectivity, group.Roughness, group.Metal, group.Color = best.Reflectivity, best.Roughness, best.Metal, best.Part.Color
    local n = group.Normal
    local eye = Scene.Eye
    local foot = eye - n * (eye - group.Point):Dot(n)
    local faces = {}
    for part, face in pairs(group.Faces) do faces[part] = face end
    local box = CFrame.fromMatrix(foot, group.A, n)
    self.Box.FilterDescendantsInstances = Scene.WorldParams.FilterDescendantsInstances
    local ok, parts = pcall(function() return Workspace:GetPartBoundsInBox(box, Vector3.new(half * 2, 0.6, half * 2), self.Box) end)
    if ok then
        for _, part in ipairs(parts) do
            if not faces[part] and part.Transparency <= 0.6 then
                local probe = {Normal = n, Position = part.CFrame.Position}
                -- Find the face of this part that lies on the plane.
                local localNormal = part.CFrame:VectorToObjectSpace(n)
                local size = part.Size
                local extent = math.abs(localNormal.X) * size.X / 2 + math.abs(localNormal.Y) * size.Y / 2 + math.abs(localNormal.Z) * size.Z / 2
                probe.Position = part.Position + n * extent
                if math.abs((probe.Position - group.Point):Dot(n)) < 0.06 then
                    local face = faceOf(part, probe)
                    if face and face.Normal:Dot(n) > 0.999 then
                        local reflectivity = materialLook(part.Material)
                        if math.abs(reflectivity - group.Reflectivity) < 0.2 then faces[part] = face end
                    end
                end
            end
        end
    end
    -- Rectangles in plane coordinates; join them when they tile their bounding box.
    local a0, a1, b0, b1 = math.huge, -math.huge, math.huge, -math.huge
    local area = 0
    local ea, eb = (foot - group.Point):Dot(group.A), (foot - group.Point):Dot(group.B)
    local function clipArea(lo, hi, low, high, centerA, centerB)
        local wa = math.max(0, math.min(hi, centerA + half) - math.max(lo, centerA - half))
        local wb = math.max(0, math.min(high, centerB + half) - math.max(low, centerB - half))
        return wa * wb
    end
    local aligned = {}
    for part, face in pairs(faces) do
        local alignA = math.abs(face.A:Dot(group.A))
        local alignB = math.abs(face.A:Dot(group.B))
        if alignA > 0.999 or alignB > 0.999 then
            local rel = face.Center - group.Point
            local ca, cb = rel:Dot(group.A), rel:Dot(group.B)
            local ha = alignA > 0.999 and face.HalfA or face.HalfB
            local hb = alignA > 0.999 and face.HalfB or face.HalfA
            local rect = {ca - ha, ca + ha, cb - hb, cb + hb}
            aligned[part] = rect
            a0, a1, b0, b1 = math.min(a0, rect[1]), math.max(a1, rect[2]), math.min(b0, rect[3]), math.max(b1, rect[4])
            area = area + clipArea(rect[1], rect[2], rect[3], rect[4], ea, eb)
        end
    end
    local bestRect = aligned[best.Part]
    if not bestRect then return nil end
    local unionArea = clipArea(a0, a1, b0, b1, ea, eb)
    if unionArea > 0 and area / unionArea >= 0.9 then return {a0, a1, b0, b1} end
    return bestRect
end

function SSR:select()
    local cfg = self.Config
    local wanted = math.min(cfg.Surfaces, cap("Surfaces"))
    local list = {}
    for key, group in pairs(self.Hits) do
        local current = self.Mirrors[key]
        if not group.Water then
            local best
            for _, face in pairs(group.Faces) do if not best or face.Weight > best.Weight then best = face end end
            group.Reflectivity = best and best.Reflectivity or 0.2
        end
        group.Score = group.Weight * (0.25 + group.Reflectivity) * (current and 1.6 or 1)
        table.insert(list, group)
    end
    table.sort(list, function(a, b) return a.Score > b.Score end)
    local keep = {}
    for index = 1, math.min(wanted, #list) do
        local group = list[index]
        local half = clamp(math.abs((Scene.Eye - group.Point):Dot(group.Normal)) * 3 + 30, 30, cfg.Range)
        local rect = self:region(group, half)
        if rect or group.Water then
            group.Rect = rect
            keep[group.Key] = true
            local mirror = self.Mirrors[group.Key]
            if mirror and not mirror.Dying then
                mirror.Group = group
                mirror.Signature = nil
            else
                if mirror then self:destroy(mirror) end
                self.Mirrors[group.Key] = self:create(group)
            end
        end
    end
    for key, mirror in pairs(self.Mirrors) do
        if not keep[key] then mirror.Dying = true end
    end
end

function SSR:create(group)
    local mirror = {Key = group.Key, Group = group, Entries = {}, Dynamic = {}, Static = {}, Shells = {}, Fade = 0, StaticIndex = 0,
        Mirror = mirrorer(group.Point, group.Normal), MirrorPoint = group.Point, NextGather = 0, NextLight = 0}
    mirror.Part = World.part({Name = "Mirror", Size = Vector3.new(4, 4, MIRROR_THICK)}, World.child("Reflections"))
    mirror.Gui = new("SurfaceGui", {Face = Enum.NormalId.Front, SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud, PixelsPerStud = 8,
        LightInfluence = 0.4, Brightness = 1.15, AlwaysOnTop = false, ClipsDescendants = true, ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
        Adornee = mirror.Part}, mirror.Part)
    mirror.View = new("ViewportFrame", {BackgroundTransparency = 1, BorderSizePixel = 0, ImageTransparency = 1, Size = UDim2.fromScale(1, 1)}, mirror.Gui)
    mirror.World = new("WorldModel", {}, mirror.View)
    mirror.Camera = new("Camera", {FieldOfView = 70}, mirror.View)
    mirror.View.CurrentCamera = mirror.Camera
    table.insert(self.Order, mirror)
    return mirror
end
function SSR:destroy(mirror)
    pcall(function() mirror.Part:Destroy() end)
    for index, item in ipairs(self.Order) do
        if item == mirror then table.remove(self.Order, index); break end
    end
    if self.Mirrors[mirror.Key] == mirror then self.Mirrors[mirror.Key] = nil end
end

-- Lays the mirror part on the surface around the eye and aims the viewport. Returns false when hidden.
function SSR:place(mirror)
    local cfg, group = self.Config, mirror.Group
    local n = group.Normal
    local eye = Scene.Eye
    local height = (eye - mirror.MirrorPoint):Dot(n)
    if height < 0.25 then return false end
    -- The plane changed (the floor moved): rebuild the mirrored copies.
    if (group.Point - mirror.MirrorPoint):Dot(n) > 0.02 or (group.Point - mirror.MirrorPoint):Dot(n) < -0.02 then
        mirror.Mirror = mirrorer(group.Point, n)
        mirror.MirrorPoint = group.Point
        for _, entry in pairs(mirror.Entries) do entry.Last = nil end
    end
    local rel = eye - group.Point
    local ea, eb = rel:Dot(group.A), rel:Dot(group.B)
    local half = math.ceil(clamp(height * 3 + 24, 24, cfg.Range) / 8) * 8
    local snap = math.max(4, half / 4)
    local ca, cb = math.floor(ea / snap + 0.5) * snap, math.floor(eb / snap + 0.5) * snap
    local a0, a1, b0, b1 = ca - half, ca + half, cb - half, cb + half
    local rect = group.Rect
    if rect then a0, a1, b0, b1 = math.max(a0, rect[1]), math.min(a1, rect[2]), math.max(b0, rect[3]), math.min(b1, rect[4]) end
    if a1 - a0 < 0.5 or b1 - b0 < 0.5 then return false end
    -- Canvas X follows whichever surface axis lines up best with the view: the wide axis of the viewport.
    local flat = Scene.Look - n * Scene.Look:Dot(n)
    if flat.Magnitude > 0.2 then
        local unit = flat.Unit
        local alongA = math.abs(unit:Dot(group.A)) >= math.abs(unit:Dot(group.B))
        if mirror.AlongA == nil or (alongA ~= mirror.AlongA and math.abs(math.abs(unit:Dot(group.A)) - 0.7071) > 0.08) then mirror.AlongA = alongA end
    elseif mirror.AlongA == nil then
        mirror.AlongA = true
    end
    local U, V, W, H
    if mirror.AlongA then U, V, W, H = group.A, group.B, a1 - a0, b1 - b0 else U, V, W, H = group.B, group.A, b1 - b0, a1 - a0 end
    if U:Cross(V):Dot(n) > 0 then V = -V end
    local signature = string.format("%.2f|%.2f|%.2f|%.2f|%s|%d|%d", a0, a1, b0, b1, tostring(mirror.AlongA), cfg.Blur, cap("Pixels"))
    if signature ~= mirror.Signature then
        mirror.Signature = signature
        local center = group.Point + group.A * ((a0 + a1) / 2) + group.B * ((b0 + b1) / 2) + n * (MIRROR_LIFT - MIRROR_THICK / 2)
        mirror.Part.Size = Vector3.new(W, H, MIRROR_THICK)
        mirror.Part.CFrame = CFrame.fromMatrix(center, -U, -V)
        local pixels = cap("Pixels") * (1 - cfg.Blur / 100 * 0.75) * (1 - (group.Roughness or 0.3) * 0.45)
        mirror.PPM = clamp(math.min(pixels, cap("Canvas") / math.max(W, H)), 1, 60)
        mirror.Gui.PixelsPerStud = mirror.PPM
        mirror.MaxPixels = cap("Canvas") * 1.5
        mirror.U, mirror.V, mirror.W, mirror.H = U, V, W, H
        mirror.Face = center + n * (MIRROR_THICK / 2)
    end
    local projection = mirrorProjection(eye, mirror.Face, n, mirror.U, mirror.V, mirror.W, mirror.H,
        mirror.MaxPixels / (2 * math.max((eye - mirror.Face):Dot(n), 0.15) * mirror.PPM))
    if not projection then return false end
    mirror.Camera.FieldOfView = projection.FieldOfView
    mirror.Camera.CFrame = projection.CFrame
    mirror.View.Position = projection.Position
    mirror.View.Size = projection.Size
    return true
end

-- What each mirror should hold: characters in range and the biggest, closest objects in front of it.
function SSR:gather(mirror)
    local cfg, group = self.Config, mirror.Group
    local n = group.Normal
    local plane = n:Dot(group.Point)
    local wanted = {}
    if cfg.Players then
        local characters = table.clone(Scene.Characters)
        for _, npc in ipairs(Scene.npcsNear(Scene.Eye, math.min(cfg.Range, 120), 8)) do table.insert(characters, npc) end
        for _, character in ipairs(characters) do
            local root = character.Root
            if alive(root) and (root.Position - Scene.Eye).Magnitude < cfg.Range and root.Position:Dot(n) - plane > -3 then
                for _, part in ipairs(characterParts(character.Model)) do wanted[part] = character.Model end
            end
        end
    end
    if cfg.World then
        local scored = {}
        for _, part in ipairs(self.Nearby) do
            if not wanted[part] and part.Parent and part.Transparency < 0.98 and not group.Faces[part] then
                local position = part.Position
                if position:Dot(n) - plane > 0.05 then
                    local size = part.Size
                    local big = math.max(size.X, size.Y, size.Z)
                    if big > 0.3 then
                        table.insert(scored, {Part = part, Score = big * big / ((position - Scene.Eye).Magnitude + 12)})
                    end
                end
            end
        end
        table.sort(scored, function(a, b) return a.Score > b.Score end)
        for index = 1, math.min(#scored, math.min(cfg.Detail, cap("Parts"))) do wanted[scored[index].Part] = true end
    end
    return wanted
end
function SSR:refresh(mirror, wanted)
    for source, entry in pairs(mirror.Entries) do
        if not wanted[source] or source.Parent == nil then
            pcall(function() entry.Clone:Destroy() end)
            mirror.Entries[source] = nil
        end
    end
    local models = {}
    for _, owner in pairs(wanted) do if owner ~= true then models[owner] = true end end
    for model, shell in pairs(mirror.Shells) do
        if model.Parent == nil or not shell.Parent or not models[model] then
            pcall(function() shell:Destroy() end)
            mirror.Shells[model] = nil
        end
    end
    local dynamic, static = {}, {}
    for source, entry in pairs(mirror.Entries) do
        if entry.Dynamic then table.insert(dynamic, entry) else table.insert(static, entry) end
    end
    mirror.Dynamic, mirror.Static = dynamic, static
    for source, owner in pairs(wanted) do
        if not mirror.Entries[source] then table.insert(self.Queue, {Mirror = mirror, Source = source, Owner = owner}) end
    end
end
function SSR:build(job)
    local mirror, source = job.Mirror, job.Source
    if mirror.Dying or not mirror.Part.Parent or mirror.Entries[source] or source.Parent == nil then return end
    local copy = visualCopy(source)
    if not copy then return end
    local parent = mirror.World
    if job.Owner ~= true then
        local shell = mirror.Shells[job.Owner]
        if not shell or not shell.Parent then
            shell = characterShell(job.Owner)
            shell.Parent = mirror.World
            mirror.Shells[job.Owner] = shell
        end
        parent = shell
    end
    local cf = source.CFrame
    copy.CFrame = mirror.Mirror(cf)
    copy.Parent = parent
    local entry = {Source = source, Clone = copy, Last = cf, Dynamic = job.Owner ~= true or not source.Anchored}
    mirror.Entries[source] = entry
    table.insert(entry.Dynamic and mirror.Dynamic or mirror.Static, entry)
end
-- Moves the copies that moved, all in one bulk call; static copies are checked a few at a time.
function SSR:sync(mirror)
    local parts, frames = {}, {}
    local function check(entry)
        local source = entry.Source
        if source.Parent == nil then return end
        local cf = source.CFrame
        if cf ~= entry.Last then
            entry.Last = cf
            parts[#parts + 1] = entry.Clone
            frames[#frames + 1] = mirror.Mirror(cf)
        end
    end
    for _, entry in ipairs(mirror.Dynamic) do check(entry) end
    local static = mirror.Static
    local count = #static
    if count > 0 then
        for _ = 1, math.min(count, 40) do
            mirror.StaticIndex = mirror.StaticIndex % count + 1
            local entry = static[mirror.StaticIndex]
            check(entry)
            -- Looks change too (doors fading, colour changes, a player turning invisible).
            local source, copy = entry.Source, entry.Clone
            if source.Parent and copy.Parent then
                if copy.Transparency ~= source.Transparency then copy.Transparency = source.Transparency end
                if copy.Color ~= source.Color then copy.Color = source.Color end
                if copy.Size ~= source.Size then copy.Size = source.Size end
            end
        end
    end
    local dynamic = mirror.Dynamic
    for _ = 1, math.min(#dynamic, 12) do
        mirror.DynamicLook = (mirror.DynamicLook or 0) % #dynamic + 1
        local entry = dynamic[mirror.DynamicLook]
        if entry.Source.Parent and entry.Clone.Parent and entry.Clone.Transparency ~= entry.Source.Transparency then
            entry.Clone.Transparency = entry.Source.Transparency
        end
    end
    if #parts > 0 then
        local ok = pcall(function() mirror.World:BulkMoveTo(parts, frames, Enum.BulkMoveMode.FireCFrameChanged) end)
        if not ok then for index, part in ipairs(parts) do part.CFrame = frames[index] end end
    end
end
-- How strong the reflection is: material, Fresnel at the viewing angle, and surface brightness.
function SSR:shade(mirror, now, dt)
    local cfg, group = self.Config, mirror.Group
    local n = group.Normal
    local sample = group.Sample or mirror.Face
    local toEye = Scene.Eye - sample
    local cosine = toEye.Magnitude > 0 and math.abs(toEye.Unit:Dot(n)) or 1
    local grazing = (1 - cosine) ^ 2.5
    local fresnel = cfg.Fresnel / 100
    local reflectivity = group.Reflectivity or 0.3
    local base = reflectivity * (1 - 0.5 * fresnel)
    local edge = math.min(1, reflectivity * (1 + 1.4 * fresnel) + 0.25 * fresnel)
    local color = group.Color or WHITE
    local opacity = cfg.Strength / 100 * 1.5 * lerp(base, edge, grazing) * (1 - 0.45 * luminance(color))
    local target = mirror.Dying and 0 or 1
    mirror.Fade = approach(mirror.Fade, target, 6, dt)
    mirror.View.ImageTransparency = 1 - clamp(opacity, 0, 0.92) * mirror.Fade
    local tint = cfg.Tint / 100 * (group.Metal and 1 or 0.4)
    mirror.View.ImageColor3 = lerpColor(WHITE, color, tint)
    if now >= mirror.NextLight then
        mirror.NextLight = now + 0.25
        local travel = -Scene.Sun
        mirror.View.LightDirection = travel - n * (2 * travel:Dot(n))
        mirror.View.LightColor = scaleColor(Scene.SunColor or WHITE, 0.15 + 0.55 * Scene.SunPower)
        mirror.View.Ambient = addColor(scaleColor(Props.base(Lighting, "OutdoorAmbient"), 0.7), Scene.skyColor(), 0.22 * (0.3 + 0.7 * Scene.Day))
    end
end

function SSR:Update(dt, now)
    local cfg = self.Config
    self:scan(cap("Rays"))
    -- One shared spatial query a second feeds every mirror.
    if now >= self.NextNearby then
        self.NextNearby = now + 1
        self.Overlap.FilterDescendantsInstances = Scene.WorldParams.FilterDescendantsInstances
        local ok, parts = pcall(function() return Workspace:GetPartBoundsInRadius(Scene.Eye, cfg.Range, self.Overlap) end)
        self.Nearby = ok and parts or {}
    end
    -- Gather for one mirror per frame, each about once a second.
    local order = self.Order
    if #order > 0 then
        self.GatherTurn = self.GatherTurn % #order + 1
        local mirror = order[self.GatherTurn]
        if mirror and not mirror.Dying and now >= mirror.NextGather then
            mirror.NextGather = now + 1
            self:refresh(mirror, self:gather(mirror))
        end
    end
    -- Build queued copies with a small time budget.
    local started = os.clock()
    while #self.Queue > 0 and os.clock() - started < 0.002 do
        self:build(table.remove(self.Queue, 1))
    end
    local surfaces, copies = 0, 0
    for index = #order, 1, -1 do
        local mirror = order[index]
        if not alive(mirror.Part) then
            self:destroy(mirror)
        else
            local visible = self:place(mirror)
            self:shade(mirror, now, dt)
            if not visible then mirror.View.ImageTransparency = 1 end
            if mirror.Dying and mirror.Fade < 0.02 then
                self:destroy(mirror)
            else
                if visible then self:sync(mirror) end
                surfaces = surfaces + 1
                for _ in pairs(mirror.Entries) do copies = copies + 1 end
            end
        end
    end
    self.Surfaces, self.Copies = surfaces, copies
    self.Info = surfaces .. " surface" .. (surfaces == 1 and "" or "s") .. " · " .. copies .. " objects"
end
function SSR:Stop()
    for _, mirror in ipairs(self.Order or {}) do pcall(function() mirror.Part:Destroy() end) end
    local folder = World.Folder and World.Folder:FindFirstChild("Reflections")
    if folder then folder:Destroy() end
    self.Mirrors, self.Order, self.Queue, self.Hits, self.Nearby = {}, {}, {}, {}, {}
    self.Surfaces, self.Copies = 0, 0
end

-- =============================================================================
-- ENGINE
-- One render-step function runs every active effect, then writes the property overrides. An effect that
-- errors three times is switched off on its own, so one problem never stops the rest.
-- =============================================================================
local isPhone = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
Engine = {Alive = true, On = true, Started = false, Quality = isPhone and "Low" or "Balanced", Load = 1, Auto = true,
    TargetFps = isPhone and 30 or 50, Now = 0, Connections = {}, Listeners = {},
    Stats = {Fps = 60, Ms = 16.7, Cost = 0, History = {}, NextSample = 0, Low = 0, High = 0}}

function Engine.emit(name, ...)
    local listener = Engine.Listeners[name]
    if listener then task.spawn(listener, ...) end
end
function Engine.fail(def, problem)
    def.Errors = def.Errors + 1
    warn("[Lyra Shaders] " .. def.Title .. ": " .. tostring(problem))
    if def.Errors >= 3 then
        def.Enabled = false
        Engine.activate(def)
        Engine.emit("Failed", def, tostring(problem))
    end
end
-- Starts or stops an effect so it matches the engine switch and its own switch.
function Engine.activate(def)
    local should = Engine.Alive and Engine.Started and Engine.On and def.Enabled
    if should and not def.Active then
        def.Active = true
        local ok, problem = pcall(function()
            if def.Start then def:Start() end
            if def.Apply then def:Apply() end
        end)
        if not ok then
            def.Active = false
            pcall(function() if def.Stop then def:Stop() end end)
            Engine.fail(def, problem)
        end
    elseif not should and def.Active then
        def.Active = false
        local ok, problem = pcall(function() if def.Stop then def:Stop() end end)
        if not ok then warn("[Lyra Shaders] " .. def.Title .. ": " .. tostring(problem)) end
        Props.clearOwner(def.Id)
        def.Info = ""
    end
end
function Engine.setEnabled(def, on)
    def.Enabled = on == true
    if on then def.Errors = 0 end
    Engine.activate(def)
end
function Engine.setParam(def, key, value)
    if def.Config[key] == value then return end
    def.Config[key] = value
    if def.Active and def.Apply then
        local ok, problem = pcall(def.Apply, def)
        if not ok then Engine.fail(def, problem) end
    end
end
function Engine.setOn(on)
    Engine.On = on ~= false
    for _, def in ipairs(FXList) do Engine.activate(def) end
end
function Engine.setQuality(name)
    if not QUALITY[name] then return end
    Engine.Quality = name
    for _, def in ipairs(FXList) do
        if def.Active and def.Apply then pcall(def.Apply, def) end
    end
end
function Engine.activeCount()
    local count = 0
    for _, def in ipairs(FXList) do if def.Active then count = count + 1 end end
    return count
end

-- Auto quality: below the target for a while sheds work; well above it for longer adds it back.
function Engine.autoQuality(dt)
    local stats = Engine.Stats
    if not Engine.Auto or not Engine.On then
        stats.Low, stats.High = 0, 0
        return
    end
    if stats.Fps < Engine.TargetFps - 4 then
        stats.Low, stats.High = stats.Low + dt, 0
        if stats.Low > 2.5 and Engine.Load > 0.35 then
            Engine.Load = math.max(0.35, Engine.Load - 0.15)
            stats.Low = 0
        end
    elseif stats.Fps > Engine.TargetFps + 8 then
        stats.High, stats.Low = stats.High + dt, 0
        if stats.High > 6 and Engine.Load < 1 then
            Engine.Load = math.min(1, Engine.Load + 0.1)
            stats.High = 0
        end
    else
        stats.Low, stats.High = 0, 0
    end
end

function Engine.step(dt)
    if not Engine.Alive then return end
    dt = clamp(tonumber(dt) or 1 / 60, 1 / 240, 0.25)
    local started = os.clock()
    Engine.Now = Engine.Now + dt
    local now = Engine.Now
    if Engine.On then
        World.root()
        Scene.update(now)
        -- An effect that failed to start (fewer than three times) gets another try every second.
        if now >= (Engine.NextRetry or 0) then
            Engine.NextRetry = now + 1
            for _, def in ipairs(FXList) do
                if def.Enabled and not def.Active then Engine.activate(def) end
            end
        end
        if Probe.Users > 0 then
            local ok, problem = pcall(Probe.step, cap("Rays"), FX.exposure.Config.Metering, dt)
            if not ok then warn("[Lyra Shaders] probe: " .. tostring(problem)) end
        end
        for _, def in ipairs(FXList) do
            if def.Active and def.Update then
                local t0 = os.clock()
                local ok, problem = pcall(def.Update, def, dt, now)
                def.Cost = def.Cost * 0.92 + (os.clock() - t0) * 1000 * 0.08
                if not ok then Engine.fail(def, problem) end
            end
        end
    end
    Props.update()
    local stats = Engine.Stats
    stats.Fps = approach(stats.Fps, 1 / dt, 4, dt)
    stats.Ms = approach(stats.Ms, dt * 1000, 4, dt)
    stats.Cost = approach(stats.Cost, (os.clock() - started) * 1000, 4, dt)
    if now >= stats.NextSample then
        stats.NextSample = now + 0.25
        table.insert(stats.History, stats.Fps)
        if #stats.History > 60 then table.remove(stats.History, 1) end
    end
    Engine.autoQuality(dt)
end

function Engine.start()
    if Engine.Started then return end
    Engine.Started = true
    local okBind = pcall(function()
        RunService:BindToRenderStep(TAG, Enum.RenderPriority.Last.Value, Engine.step)
    end)
    if okBind then
        Engine.Bound = true
    else
        table.insert(Engine.Connections, RunService.RenderStepped:Connect(Engine.step))
    end
    table.insert(Engine.Connections, Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function() World.root() end))
    Scene.update(0)
    Scene.refreshCharacters()
    for _, def in ipairs(FXList) do Engine.activate(def) end
end

function Engine.unload()
    if not Engine.Alive then return end
    Engine.Alive = false
    if Engine.Bound then pcall(function() RunService:UnbindFromRenderStep(TAG) end) end
    for _, connection in ipairs(Engine.Connections) do pcall(function() connection:Disconnect() end) end
    Engine.Connections = {}
    for _, def in ipairs(FXList) do
        if def.Active then
            def.Active = false
            pcall(function() if def.Stop then def:Stop() end end)
        end
    end
    for _, def in ipairs(FXList) do Props.clearOwner(def.Id) end
    Props.update()
    Props.restoreAll()
    Technology.restore()
    for name in pairs(Slots) do dropSlot(name) end
    Lamps.stop()
    pcall(function() if World.Folder then World.Folder:Destroy() end end)
    pcall(function() if Overlay.Gui then Overlay.Gui:Destroy() end end)
    pcall(function() if Noise.Image then Noise.Image:Destroy() end end)
    Engine.emit("Unloaded")
    if Genv.LyraShaders == Engine.Api then Genv.LyraShaders = nil end
end

-- =============================================================================
-- LOOKS
-- A look sets a whole family of effects at once. Keys are "<effect>.<parameter>"; "<effect>" alone is the
-- effect's switch. Effects a look does not name keep their current settings.
-- =============================================================================
local LOOK_ORDER = {"Natural", "Cinematic", "Vivid", "Noir", "Dreamy", "Golden hour"}
local LOOK_PRESETS = {
    Natural = {colour = true, ["colour.Tone"] = "Filmic", ["colour.ToneStrength"] = 60, ["colour.Contrast"] = 8, ["colour.Saturation"] = 6,
        ["colour.Temperature"] = 6600, ["colour.Brightness"] = 0, ambient = true, ["ambient.Strength"] = 30, ssr = true, sharpness = true,
        ["sharpness.Strength"] = 35, bloom = true, ["bloom.Intensity"] = 30, ["bloom.Threshold"] = 1.6, lut = false, vignette = false,
        grain = false, dof = false, flare = false, sunrays = false, exposure = false, atmosphere = false, motionblur = false, lighting = false},
    Cinematic = {colour = true, ["colour.Tone"] = "Teal & orange", ["colour.ToneStrength"] = 80, ["colour.Contrast"] = 16, ["colour.Saturation"] = 2,
        ["colour.Temperature"] = 6800, lut = true, ["lut.Source"] = "Print film", ["lut.Strength"] = 55, vignette = true, ["vignette.Intensity"] = 38,
        bloom = true, ["bloom.Intensity"] = 40, sunrays = true, ["sunrays.Intensity"] = 25, flare = true, ["flare.Intensity"] = 50,
        dof = true, ["dof.Focus"] = "Auto", ["dof.Aperture"] = 2.8, exposure = true, grain = true, ["grain.Intensity"] = 15,
        atmosphere = true, ["atmosphere.Density"] = 30, mxao = true, ambient = true, ssr = true},
    Vivid = {colour = true, ["colour.Tone"] = "Vivid", ["colour.ToneStrength"] = 80, ["colour.Saturation"] = 22, ["colour.Contrast"] = 14,
        ["colour.Temperature"] = 6500, bloom = true, ["bloom.Intensity"] = 35, sharpness = true, ["sharpness.Strength"] = 50, ambient = true,
        ["ambient.Strength"] = 40, ssr = true, ["ssr.Strength"] = 65, sunrays = true, ["sunrays.Intensity"] = 30, lut = false, grain = false,
        vignette = false, dof = false},
    Noir = {colour = true, ["colour.Tone"] = "Noir", ["colour.ToneStrength"] = 100, ["colour.Contrast"] = 25, ["colour.Saturation"] = 0,
        vignette = true, ["vignette.Intensity"] = 55, ["vignette.Tint"] = "Black", grain = true, ["grain.Intensity"] = 35, ["grain.Size"] = "Medium",
        bloom = true, ["bloom.Intensity"] = 20, lut = false, flare = false, sunrays = false, dof = false},
    Dreamy = {colour = true, ["colour.Tone"] = "Warm film", ["colour.ToneStrength"] = 70, ["colour.Contrast"] = -5, ["colour.Saturation"] = 10,
        ["colour.Temperature"] = 7200, ["colour.Brightness"] = 4, bloom = true, ["bloom.Intensity"] = 70, ["bloom.Threshold"] = 1.1, ["bloom.Size"] = 40,
        sunrays = true, ["sunrays.Intensity"] = 40, atmosphere = true, ["atmosphere.Haze"] = 3, ["atmosphere.Glare"] = 2, ["atmosphere.Tone"] = "Warm",
        dof = true, ["dof.Focus"] = "Character", ["dof.Aperture"] = 1.4, vignette = true, ["vignette.Intensity"] = 25, grain = false},
    ["Golden hour"] = {lighting = true, ["lighting.LockTime"] = true, ["lighting.Time"] = 17.5, colour = true, ["colour.Tone"] = "Warm film",
        ["colour.ToneStrength"] = 80, ["colour.Temperature"] = 7800, lut = true, ["lut.Source"] = "Golden hour", ["lut.Strength"] = 60,
        sunrays = true, ["sunrays.Intensity"] = 45, flare = true, ["flare.Intensity"] = 70, atmosphere = true, ["atmosphere.Tone"] = "Warm",
        ["atmosphere.Density"] = 35, bloom = true, ["bloom.Intensity"] = 45},
}

-- =============================================================================
-- INTERFACE (Lyra UI)
-- =============================================================================
local function loadLyra()
    -- A copy already loaded by the caller (offline use, tests) wins over the download.
    if type(Genv.LyraUI_Library) == "table" then return Genv.LyraUI_Library end
    local source = Files.fetch(LYRA_URL)
    assert(type(source) == "string" and source ~= "", "Lyra Shaders: could not download Lyra UI. Check your connection and run the script again.")
    local chunk, problem = loadstring(source)
    assert(chunk, "Lyra Shaders: Lyra UI did not compile: " .. tostring(problem))
    return chunk()
end
local Lyra = loadLyra()
Files.folder(TAG)
Files.folder(TAG .. "/luts")

local UI = {Rows = {}, Toggles = {}, Pages = {}, Infos = {}, Quick = {}, StatusHold = 0}
local Window = Lyra:CreateWindow({
    Name = "LyraShaders",
    Title = "Lyra Shaders",
    Subtitle = "In-game overlay  ·  v" .. VERSION,
    Theme = "Midnight",
    Keybind = Enum.KeyCode.RightControl,
    ChatCommand = "shaders",
    ConfigFile = TAG .. "/settings",
    Blur = false,
    NavCaption = "SHADERS",
    Footer = "ENGINE ON",
    LogoText = "LS",
    Status = "Changes save by themselves.",
    Size = {860, 600},
    OnDestroy = function() Engine.unload() end,
})
UI.Window = Window
local saved = Window.Saved or {}

local function flagOf(def, key) return "fx." .. def.Id .. "." .. key end
local function enabledFlag(def) return "fx." .. def.Id .. ".enabled" end
local function plural(count, word) return count .. " " .. word .. (count == 1 and "" or "s") end

function UI.hold(text, kind, seconds)
    if not Window.Alive then return end
    Window:Status(text, kind)
    UI.StatusHold = os.clock() + (seconds or 4)
end
function UI.enabledCount()
    local count = 0
    for _, def in ipairs(FXList) do if def.Enabled then count = count + 1 end end
    return count
end
function UI.refreshRow(def)
    local row = UI.Rows[def.Id]
    if row then
        local button = row.Buttons[1]
        button.Spec.Title = def.Enabled and "On" or "Off"
        button:SetText(button.Spec.Title)
        button:SetPrimary(def.Enabled)
        row:SetCurrent(def.Enabled)
    end
    local quick = UI.Quick[def.Id]
    if quick and quick:Get() ~= def.Enabled then quick:Set(def.Enabled, true) end
end
function UI.refreshFooter()
    if not Window.Alive then return end
    local count = UI.enabledCount()
    Window.NavFooter.Text = Engine.On and ("ENGINE ON  ·  " .. plural(count, "EFFECT") .. " ON") or "ENGINE OFF"
    if UI.PillLabel then
        UI.PillLabel.Text = Engine.On and "Shaders: On" or "Shaders: Off"
        Window:_paint(UI.PillDot, {BackgroundColor3 = Engine.On and "Green" or "Muted"})
    end
end
function UI.setEnabled(def, on)
    Engine.setEnabled(def, on)
    local toggle = UI.Toggles[def.Id]
    if toggle and toggle:Get() ~= def.Enabled then toggle:Set(def.Enabled, true) end
    UI.refreshRow(def)
    UI.refreshFooter()
end
function UI.open(def)
    local page = UI.Pages[def.Id]
    if page then Window:SelectTab(page) end
end
-- Detail pages are hidden tabs; while one is open, keep "Effects" lit on the rail.
function UI.markEffects()
    local rail = UI.EffectsTab and UI.EffectsTab.RailButton
    if not rail then return end
    rail.Marker.Visible = true
    Window:_tween(rail.Root, {BackgroundTransparency = 0})
    Window:_paint(rail.Label, {TextColor3 = "Text"})
end
function UI.resetEffect(def)
    for _, param in ipairs(def.Params) do Window:SetFlag(flagOf(def, param.Key), param.Default) end
    UI.hold(def.Title .. " is back to its defaults.", "info")
end
function UI.resetAll()
    for _, def in ipairs(FXList) do
        for _, param in ipairs(def.Params) do Window:SetFlag(flagOf(def, param.Key), param.Default) end
        Window:SetFlag(enabledFlag(def), def.Default == true)
    end
    UI.hold("Every effect is back to its defaults.", "success")
end
function UI.applyLook(name)
    local preset = LOOK_PRESETS[name]
    if not preset then return end
    for key, value in pairs(preset) do
        local id, param = key:match("^(%w+)%.?(.*)$")
        local def = id and FX[id]
        if def then Window:SetFlag(param == "" and enabledFlag(def) or flagOf(def, param), value) end
    end
    Window:SetFlag("engine.look", name)
    UI.hold(name .. " look applied. Every effect stays adjustable.", "success")
end
function UI.export()
    local data = {}
    for key, value in pairs(Window.Flags) do
        if type(key) == "string" and (key:sub(1, 3) == "fx." or key:sub(1, 7) == "engine.") then data[key] = value end
    end
    local ok, json = pcall(function() return HttpService:JSONEncode(data) end)
    if not ok then UI.hold("Could not export the settings.", "error"); return end
    local clipboard = (type(setclipboard) == "function" and setclipboard) or (type(toclipboard) == "function" and toclipboard) or nil
    local copied = clipboard ~= nil and (pcall(clipboard, json))
    if UI.ExportBox then UI.ExportBox:Set(json) end
    UI.hold(copied and "Settings copied to the clipboard." or "No clipboard here: the settings text is in the box below.", copied and "success" or "warning")
    return json
end
function UI.import(text)
    local ok, data = pcall(function() return HttpService:JSONDecode(text) end)
    if not ok or type(data) ~= "table" then UI.hold("That is not a Lyra Shaders settings text.", "error"); return end
    local count = 0
    for key, value in pairs(data) do
        if Window.FlagObjects[key] then
            Window:SetFlag(key, value)
            count = count + 1
        end
    end
    UI.hold("Imported " .. plural(count, "setting") .. ".", count > 0 and "success" or "warning")
end

-- One control for one effect parameter.
function UI.control(tab, def, param)
    local flag = flagOf(def, param.Key)
    local function changed(value) Engine.setParam(def, param.Key, value) end
    local kind = param.Kind
    if kind == "Slider" then
        return tab:Slider({Title = param.Title, Description = param.Description, Min = param.Min, Max = param.Max, Step = param.Step or 1,
            Default = param.Default, Suffix = param.Suffix, Format = param.Format, Flag = flag, Callback = changed})
    elseif kind == "Toggle" then
        return tab:Toggle({Title = param.Title, Description = param.Description, Default = param.Default, Flag = flag, Callback = changed})
    elseif kind == "Dropdown" then
        return tab:Dropdown({Title = param.Title, Description = param.Description, Options = param.Options, Default = param.Default, Width = 170,
            Flag = flag, Callback = changed})
    elseif kind == "Stepper" then
        return tab:Stepper({Title = param.Title, Description = param.Description, Values = param.Values, Min = param.Min, Max = param.Max,
            Step = param.Step, Default = param.Default, Format = param.Format, Suffix = param.Suffix, Flag = flag, Callback = changed})
    elseif kind == "Segmented" then
        tab:Label(param.Title)
        return tab:Segmented({Options = param.Options, Default = param.Default, Height = 40, Flag = flag, Callback = changed})
    elseif kind == "Input" then
        return tab:Input({Title = param.Title, Placeholder = param.Placeholder, Default = param.Default, Icon = "download", Button = true, Flag = flag,
            Callback = function(text, entered)
                changed(text)
                if entered and def.Id == "lut" and text ~= "" then
                    if def.Config.Source ~= CUSTOM_LUT then Window:SetFlag(flagOf(def, "Source"), CUSTOM_LUT) end
                    if def.Active then UI.hold("LUT: " .. (def.Info ~= "" and def.Info or "loading…"), def.Info:find("Fitted") and "success" or "warning") end
                end
            end})
    end
    return nil
end

function UI.lutOptions()
    local options = table.clone(LOOK_NAMES)
    for _, file in ipairs(Lut.files()) do table.insert(options, file) end
    table.insert(options, CUSTOM_LUT)
    return options
end

function UI.page(def)
    local tab = Window:Tab({Title = def.Title, Icon = def.Icon, OnSelect = function() UI.markEffects(); UI.refreshInfo(def) end})
    tab:SetVisible(false)
    UI.Pages[def.Id] = tab
    tab:ButtonRow({
        {Title = "All effects", Icon = "undo", Callback = function() Window:SelectTab(UI.EffectsTab) end},
        {Title = "Reset", Icon = "reset", Callback = function() UI.resetEffect(def) end},
    })
    tab:Section(def.Title, def.Description)
    UI.Toggles[def.Id] = tab:Toggle({Title = "Enabled", Description = "Turn " .. def.Title .. " on or off.", Default = def.Default == true,
        Flag = enabledFlag(def), Callback = function(on) UI.setEnabled(def, on) end})
    UI.Infos[def.Id] = tab:Label("", "Accent")
    if def.Id == "lut" then
        for _, param in ipairs(def.Params) do if param.Key == "Source" then param.Options = UI.lutOptions() end end
    end
    for _, param in ipairs(def.Params) do
        local control = UI.control(tab, def, param)
        if def.Id == "lut" and param.Key == "Source" then UI.LutSource = control end
    end
    if def.Id == "lut" then
        tab:Action({Title = "LUT folder", Description = "Put .cube files or PNG strips in workspace/" .. TAG .. "/luts, then reload the list.",
            Button = "Reload", Icon = "refresh", Callback = function()
                Files.folder(TAG .. "/luts")
                UI.LutSource:SetOptions(UI.lutOptions(), true)
                UI.hold("Found " .. plural(#Lut.files(), "LUT file") .. ".", "info")
            end})
    end
    if def.Notes then tab:Guide({Title = "How it works", Lines = def.Notes}) end
    return tab
end
function UI.refreshInfo(def)
    local label = UI.Infos[def.Id]
    if not label then return end
    local state
    if not Engine.On then state = "Engine off"
    elseif not def.Enabled then state = "Off"
    else state = "On" .. (def.Info ~= "" and ("  ·  " .. def.Info) or "") end
    label:Set(state, def.Enabled and Engine.On and "Accent" or "Muted")
end

-- HOME -----------------------------------------------------------------------
local Home = Window:Tab({Title = "Home", Icon = "star", OnSelect = function() if UI.refreshHome then UI.refreshHome() end end})
Home:Section("Lyra Shaders", "Lighting, colour and real-time reflections for any game. Everything runs on your device only, and turning it off puts the game's own look back.")
UI.Master = Home:Toggle({Title = "Shaders", Description = "Turns the whole engine on or off.", Default = true, Flag = "engine.on",
    Callback = function(on)
        Engine.setOn(on)
        UI.refreshFooter()
        for _, def in ipairs(FXList) do UI.refreshInfo(def) end
    end})
local nowGroup = Home:Group({Title = "RIGHT NOW"})
UI.HomeStatus = nowGroup:Paragraph("", {RichText = true})
Home:Section("Look", "One tap sets a whole look. Every effect stays adjustable afterwards.")
Home:Chips({Options = LOOK_ORDER, Default = saved["engine.look"] or "Natural", Callback = function(name) UI.applyLook(name) end})
Home:Section("Quality", "How much of your device the engine may use. Auto quality (in Settings) lowers it further when the frame rate drops.")
Home:Segmented({Options = {"Low", "Balanced", "High", "Ultra"}, Default = Engine.Quality, Flag = "engine.quality",
    Callback = function(name) Engine.setQuality(name) end})
local quick = Home:Group({Title = "FAVOURITES"})
for _, id in ipairs({"ssr", "colour", "mxao", "gi", "bloom", "flare"}) do
    local def = FX[id]
    UI.Quick[id] = quick:Toggle({Title = def.Title, Description = def.Description, Default = def.Default == true, Callback = function(on) UI.setEnabled(def, on) end})
end
Home:ButtonRow({
    {Title = "All effects", Icon = "sliders", Primary = true, Callback = function() Window:SelectTab(UI.EffectsTab) end},
    {Title = "All off", Icon = "eye-off", Callback = function()
        for _, def in ipairs(FXList) do if def.Enabled then UI.setEnabled(def, false) end end
        UI.hold("Every effect is off. The engine stays ready.", "info")
    end},
    {Title = "Defaults", Icon = "reset", Callback = function()
        Window:Confirm({Title = "Restore every default?", Text = "All effects and their settings go back to how they started.", Confirm = "Restore", Seconds = 10,
            Callback = UI.resetAll})
    end},
})
Home:Guide({Title = "How it works", Lines = {
    "1. Effects lists every shader. Tap one to tune it; On / Off switches it from the list.",
    "2. Looks set a whole family of effects at once.",
    "3. Quality decides how much work each effect may do; Statistics shows what it costs.",
}, Note = "Close the window with the X: the floating button, RightControl or /shaders in chat bring it back. /fx on and /fx off switch the engine."})

-- EFFECTS --------------------------------------------------------------------
local EffectsTab = Window:Tab({Title = "Effects", Icon = "sliders-horizontal"})
UI.EffectsTab = EffectsTab
EffectsTab:Section("Effects", "Tap the arrow to tune an effect. Highlighted rows are on.")
for _, def in ipairs(FXList) do
    UI.Rows[def.Id] = EffectsTab:Row({Title = def.Title, Subtitle = def.Description, Icon = def.Icon, Current = def.Default == true, Buttons = {
        {Title = def.Default and "On" or "Off", Primary = def.Default == true, Width = 60, Callback = function() UI.setEnabled(def, not def.Enabled) end},
        {Icon = "arrow-right", Callback = function() UI.open(def) end},
    }})
end

-- SETTINGS -------------------------------------------------------------------
local SettingsTab = Window:SettingsTab({Description = "The window's own settings, then the engine's."})
SettingsTab:Section("Engine", "How the shaders run on this device.")
SettingsTab:Toggle({Title = "Auto quality", Description = "Does less work per frame when the frame rate drops below the target, and more again when there is room.",
    Default = true, Flag = "engine.auto", Callback = function(on) Engine.Auto = on; if not on then Engine.Load = 1 end end})
SettingsTab:Slider({Title = "Target frame rate", Min = 20, Max = 120, Step = 5, Default = Engine.TargetFps, Suffix = " fps", Flag = "engine.target",
    Callback = function(value) Engine.TargetFps = value end})
SettingsTab:Keybind({Title = "Shaders on/off key", Description = "Press it anywhere to switch the engine. Tap, then press a key to set it.", Default = "None",
    Flag = "engine.key", Blocked = {"W", "A", "S", "D", "Space", "Return", "Tab", "Backspace", "Slash"}, Callback = function() UI.Master:Toggle() end})
UI.PillToggle = SettingsTab:Toggle({Title = "Shaders button", Description = "The small Shaders: On button on the side of the screen.", Default = true,
    Flag = "ui.pill", Callback = function(on) if UI.Pill then UI.Pill.Visible = on end end})
SettingsTab:Section("Share settings")
SettingsTab:Action({Title = "Copy settings", Description = "Every effect setting as text, to back up or share.", Button = "Copy", Icon = "copy", Callback = UI.export})
UI.ExportBox = SettingsTab:TextArea({Placeholder = "Paste a settings text here, then tap Import.", Height = 64})
SettingsTab:Button({Title = "Import", Icon = "download", Callback = function() UI.import(UI.ExportBox:Get()) end})
SettingsTab:Section("Reset")
SettingsTab:Action({Title = "Restore defaults", Description = "Every effect and setting back to how it started.", Button = "Restore", Icon = "reset",
    Callback = function()
        Window:Confirm({Title = "Restore every default?", Text = "All effects and their settings go back to how they started.", Confirm = "Restore", Seconds = 10,
            Callback = UI.resetAll})
    end})
SettingsTab:Action({Title = "Unload", Description = "Removes the shaders and this window. The game's look comes back.", Button = "Unload", Icon = "x",
    Callback = function()
        Window:Confirm({Title = "Unload Lyra Shaders?", Text = "Run the script again to bring it back.", Confirm = "Unload", Seconds = 10,
            Callback = function() Engine.unload() end})
    end})

-- STATISTICS -----------------------------------------------------------------
local StatsTab = Window:Tab({Title = "Statistics", Icon = "history", OnSelect = function() if UI.refreshStats then UI.refreshStats() end end})
StatsTab:Section("Statistics", "Live numbers from the engine, refreshed twice a second while this page is open.")
local graphGroup = StatsTab:Group({Title = "FRAME RATE  ·  LAST 15 SECONDS"})
local graph = new("Frame", {Size = UDim2.new(1, 0, 0, 74), BackgroundTransparency = 1, ClipsDescendants = true})
graphGroup:_add(graph)
graph.Parent = graphGroup.Frame
UI.Bars = {}
for index = 1, 60 do
    local bar = new("Frame", {AnchorPoint = Vector2.new(0, 1), Position = UDim2.new((index - 1) / 60, 1, 1, 0), Size = UDim2.new(1 / 60, -2, 0, 2),
        BorderSizePixel = 0}, graph)
    new("UICorner", {CornerRadius = UDim.new(0, 2)}, bar)
    Window:_paint(bar, {BackgroundColor3 = "Accent"})
    UI.Bars[index] = bar
end
UI.TargetLine = new("Frame", {Size = UDim2.new(1, 0, 0, 1), BackgroundTransparency = 0.35, BorderSizePixel = 0}, graph)
Window:_paint(UI.TargetLine, {BackgroundColor3 = "Gold"})
UI.GraphCaption = graphGroup:Label("")
local leftStats, rightStats = StatsTab:Columns()
local frameGroup = leftStats:Group({Title = "FRAME"})
UI.StatFrame = frameGroup:Paragraph("", {RichText = true})
local engineGroup = rightStats:Group({Title = "ENGINE"})
UI.StatEngine = engineGroup:Paragraph("", {RichText = true})
local worldGroup = leftStats:Group({Title = "WORLD"})
UI.StatWorld = worldGroup:Paragraph("", {RichText = true})
local deviceGroup = rightStats:Group({Title = "DEVICE"})
UI.StatDevice = deviceGroup:Paragraph("", {RichText = true})
local costGroup = StatsTab:Group({Title = "COST PER EFFECT"})
UI.StatCost = costGroup:Paragraph("", {RichText = true})

-- ABOUT ----------------------------------------------------------------------
local AboutTab = Window:Tab({Title = "About", Icon = "info"})
AboutTab:Section("Lyra Shaders", "Version " .. VERSION .. "  ·  shaders, lighting and reflections for Roblox, built on Lyra UI.")
AboutTab:Paragraph("Roblox does not let scripts run pixel shaders, so every effect here is rebuilt from what the engine does offer: post-processing layers, lighting properties, ViewportFrames, surface overlays, highlights and lights. Everything is created on your device only: other players see nothing, and turning the engine off puts the game's own look back.", {Muted = true})
local recipe = {}
for _, def in ipairs(FXList) do
    if def.Notes and def.Notes[1] then table.insert(recipe, def.Title .. ": " .. def.Notes[1]) end
end
AboutTab:Guide({Title = "How each effect is made", Lines = recipe})
AboutTab:Profile({Caption = "MADE BY", Title = "lyraEz", Handle = "@lyraEz", Initial = "L", ImageUrl = "https://github.com/lyraEz.png?size=256",
    Bio = "The moon reminds me that even in darkness, there's always a <b>beautiful light</b>", Url = "https://github.com/lyraEz", Label = "GitHub"})
AboutTab:Link({Title = "Lyra UI", Subtitle = "The interface library", Icon = "github", Url = "https://github.com/lyraEz/Library-UI"})
AboutTab:Link({Title = "Discord", Subtitle = "Join the community", Icon = "discord", Url = "https://discord.gg/8bxXcn2Vfb"})

-- EFFECT PAGES -----------------------------------------------------------------
for _, def in ipairs(FXList) do UI.page(def) end

-- LIVE TEXT ------------------------------------------------------------------
function UI.refreshHome()
    if not UI.HomeStatus then return end
    local stats = Engine.Stats
    local names = {}
    for _, def in ipairs(FXList) do if def.Active then table.insert(names, def.Title) end end
    local load = Engine.Load < 1 and (" · auto " .. formatNumber(Engine.Load * 100) .. "%") or ""
    UI.HomeStatus:Set(string.format("<b>%s</b>  ·  quality <b>%s</b>%s\n<b>%d</b> fps  ·  <b>%.1f</b> ms per frame  ·  engine <b>%.2f</b> ms\n%s",
        Engine.On and "Engine on" or "Engine off", Engine.Quality, load, math.floor(stats.Fps + 0.5), stats.Ms, stats.Cost,
        #names > 0 and table.concat(names, ", ") or "No effect is running."))
end
local function line(label, value) return "<b>" .. label .. "</b>   " .. value end
function UI.refreshStats()
    local stats = Engine.Stats
    local top = math.max(Engine.TargetFps * 1.5, 30)
    for _, value in ipairs(stats.History) do top = math.max(top, value) end
    local history = stats.History
    for index, bar in ipairs(UI.Bars) do
        local value = history[#history - 60 + index]
        if value then
            bar.Visible = true
            bar.Size = UDim2.new(1 / 60, -2, value / top, 0)
            Window:_paint(bar, {BackgroundColor3 = value < Engine.TargetFps - 4 and "Gold" or "Accent"})
        else
            bar.Visible = false
        end
    end
    UI.TargetLine.Position = UDim2.new(0, 0, 1 - Engine.TargetFps / top, 0)
    UI.GraphCaption:Set("Gold line: target " .. Engine.TargetFps .. " fps")
    UI.StatFrame:Set(table.concat({
        line("Frame rate", math.floor(stats.Fps + 0.5) .. " fps"),
        line("Frame time", formatNumber(stats.Ms, 1) .. " ms"),
        line("Engine time", formatNumber(stats.Cost, 2) .. " ms"),
    }, "\n"))
    UI.StatEngine:Set(table.concat({
        line("Effects on", tostring(Engine.activeCount()) .. " of " .. #FXList),
        line("Quality", Engine.Quality .. (Engine.Load < 1 and (" at " .. formatNumber(Engine.Load * 100) .. "%") or "")),
        line("Rays", Scene.RaysPerSecond .. " per second"),
    }, "\n"))
    local lights = 0
    for _, light in ipairs(FX.gi.Lights or {}) do if light.Level and light.Level > 0.01 then lights = lights + 1 end end
    local rim = 0
    for _ in pairs(FX.rim.Items or {}) do rim = rim + 1 end
    UI.StatWorld:Set(table.concat({
        line("Reflections", plural(SSR.Surfaces or 0, "surface") .. " · " .. plural(SSR.Copies or 0, "object")),
        line("Shading", plural(FX.mxao.CardCount or 0, "card")),
        line("Lights", lights .. " bounce · " .. rim .. " rim"),
    }, "\n"))
    local memory = "n/a"
    pcall(function() memory = formatNumber(game:GetService("Stats"):GetTotalMemoryUsageMb()) .. " MB" end)
    local technology = "n/a"
    pcall(function() technology = Lighting.Technology.Name end)
    local graphics = "Automatic"
    pcall(function()
        local level = UserSettings():GetService("UserGameSettings").SavedQualityLevel
        if level and level.Value > 0 then graphics = "Level " .. level.Value end
    end)
    UI.StatDevice:Set(table.concat({
        line("Device", isPhone and "Phone or tablet" or "Computer"),
        line("Memory", memory),
        line("Lighting", technology .. " · graphics " .. graphics),
    }, "\n"))
    local costs = {}
    for _, def in ipairs(FXList) do if def.Active then table.insert(costs, def) end end
    table.sort(costs, function(a, b) return a.Cost > b.Cost end)
    local lines = {}
    for index = 1, math.min(#costs, 8) do
        local def = costs[index]
        table.insert(lines, line(def.Title, formatNumber(def.Cost, 2) .. " ms" .. (def.Info ~= "" and ("  ·  " .. def.Info) or "")))
    end
    UI.StatCost:Set(#lines > 0 and table.concat(lines, "\n") or "No effect is running.")
end

-- SHADERS BUTTON -----------------------------------------------------------------
function UI.buildPill()
    local pill = new("TextButton", {Name = "ShadersButton", AutoButtonColor = false, Text = "", Size = UDim2.fromOffset(132, 36), BorderSizePixel = 0,
        ZIndex = 30, Position = UDim2.new(0, 14, 0.5, 28)}, Window.Surface)
    local position = saved["ui.pillPos"]
    if type(position) == "string" then
        local x, y = position:match("^(%-?[%d%.]+),(%-?[%d%.]+)$")
        if x then pill.Position = UDim2.fromOffset(tonumber(x), tonumber(y)) end
    end
    Window:_paint(pill, {BackgroundColor3 = "Raised"})
    pill.BackgroundTransparency = 0.08
    new("UICorner", {CornerRadius = UDim.new(0, 18)}, pill)
    Window:_stroke(pill, 0.35, "Accent")
    UI.PillDot = new("Frame", {Position = UDim2.new(0, 14, 0.5, -4), Size = UDim2.fromOffset(8, 8), BorderSizePixel = 0, ZIndex = 31}, pill)
    new("UICorner", {CornerRadius = UDim.new(0.5, 0)}, UI.PillDot)
    UI.PillLabel = new("TextLabel", {Position = UDim2.fromOffset(30, 0), Size = UDim2.new(1, -38, 1, 0), BackgroundTransparency = 1, Text = "Shaders: On",
        Font = Lyra.Font.Bold, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 31}, pill)
    Window:_paint(UI.PillLabel, {TextColor3 = "Text"})
    UI.Pill = pill
    local pressing, moved, start, origin, touch
    Window:_on(pill.InputBegan, function(input)
        if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then return end
        pressing, moved = true, false
        start, origin = input.Position, pill.AbsolutePosition - Window.Surface.AbsolutePosition
        touch = input.UserInputType == Enum.UserInputType.Touch and input or nil
    end)
    Window:Connect(UserInputService.InputChanged, function(input)
        if not pressing then return end
        if touch and input ~= touch then return end
        if not touch and input.UserInputType ~= Enum.UserInputType.MouseMovement then return end
        local delta = input.Position - start
        if delta.Magnitude > 6 then moved = true end
        if moved then
            local size = Window.Surface.AbsoluteSize
            pill.Position = UDim2.fromOffset(clamp(origin.X + delta.X, 4, math.max(4, size.X - 136)), clamp(origin.Y + delta.Y, 4, math.max(4, size.Y - 40)))
        end
    end)
    Window:Connect(UserInputService.InputEnded, function(input)
        if not pressing then return end
        if touch and input ~= touch then return end
        if not touch and input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
        pressing = false
        if moved then
            Window:SetFlag("ui.pillPos", math.floor(pill.Position.X.Offset) .. "," .. math.floor(pill.Position.Y.Offset))
        else
            UI.Master:Toggle()
        end
    end)
    pill.Visible = UI.PillToggle:Get()
end
UI.buildPill()
pcall(function() Window.Orb.Position = UDim2.new(0, 16, 0.5, -36) end)

-- CHAT -------------------------------------------------------------------------
Window:Command("fx", function(args)
    local word = tostring(args or ""):lower()
    if word == "on" or word == "off" then
        UI.Master:Set(word == "on")
    else
        for _, name in ipairs(LOOK_ORDER) do
            if name:lower() == word then UI.applyLook(name); return end
        end
        UI.Master:Toggle()
    end
end)

-- WIRING -----------------------------------------------------------------------
Engine.Listeners.Failed = function(def, problem)
    UI.setEnabled(def, false)
    Window:Notify({Title = def.Title .. " turned off", Text = "It failed three times in this game: " .. problem:sub(1, 120), Kind = "warning", Duration = 8})
end
Engine.Listeners.Unloaded = function()
    if Window.Alive then Window:Destroy() end
end
Window:Connect(RunService.Heartbeat, function()
    local now = os.clock()
    if now < (UI.NextText or 0) then return end
    UI.NextText = now + 0.5
    local current = Window.CurrentTab
    if current == Home then UI.refreshHome()
    elseif current == StatsTab then UI.refreshStats()
    else
        for _, def in ipairs(FXList) do if UI.Pages[def.Id] == current then UI.refreshInfo(def) end end
    end
    if now >= UI.StatusHold and Window.Visible then
        Window:Status(string.format("Changes save by themselves  ·  %d fps  ·  %.1f ms", math.floor(Engine.Stats.Fps + 0.5), Engine.Stats.Ms), "info")
    end
end)

Engine.Api = {
    Version = VERSION,
    Window = Window,
    Effects = FX,
    Engine = Engine,
    Unload = function() Engine.unload() end,
    SetEnabled = function(id, on) if FX[id] then Window:SetFlag(enabledFlag(FX[id]), on == true) end end,
    Set = function(id, key, value) if FX[id] then Window:SetFlag(flagOf(FX[id], key), value) end end,
    ApplyLook = UI.applyLook,
    Export = UI.export,   -- every effect setting as JSON text (also copied to the clipboard)
    Import = UI.import,   -- applies a text from Export
    -- Building blocks, exposed for tests and for anyone extending the script.
    Internals = {Mirror = mirrorer, Projection = mirrorProjection, Lut = Lut, Props = Props, Scene = Scene, Probe = Probe},
}
Genv.LyraShaders = Engine.Api

Engine.start()
for _, def in ipairs(FXList) do UI.refreshRow(def) end
UI.refreshFooter()
UI.refreshHome()
Window:Notify({Title = "Lyra Shaders loaded", Text = "RightControl or /shaders shows and hides the window. The Shaders button switches the engine.",
    Kind = "success", Icon = "circle-check"})
return Engine.Api
