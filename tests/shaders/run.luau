--[[
    Lyra Shaders test: runs Lyra UI and shaders/LyraShaders.lua inside the LuaU-Mock-Kit harness
    (a simulated Roblox world with real CFrame maths), the way an executor would.

        lune run tests/shaders/run.luau          (from the repository root)

    It needs the harness checked out next to this repository (../LuaU-Mock-Kit); change the
    "harness" alias in tests/shaders/.luaurc to point somewhere else.

    Checked: every effect starts, runs and stops without errors; the reflection projection lands each
    mirrored point exactly where the true reflection is; mirrored parts keep their shape; LUT files
    (.cube 1D/3D, PNG strips with stored, fixed and dynamic deflate blocks) decode and fit; the UI
    buttons work; looks, engine on/off and unload put the game's lighting back.
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local Harness = require("@harness")

local passed, failed = 0, 0
local function check(condition, message)
    if condition then
        passed += 1
    else
        failed += 1
        print("FAIL " .. message)
    end
end
local function near(a, b, eps)
    return math.abs(a - b) <= (eps or 0.03)
end

local env = Harness.createEnvironment()
local Instance, Types = env.Instance, env.Types
local V3, CF, C3, Enum = Types.Vector3, Types.CFrame, Types.Color3, Types.Enum
local ws = env.workspace
local Lighting = env.game:GetService("Lighting")

-- A room: a marble floor, a plastic wall, a glass wall, a ceiling, crates and a lamp.
local function part(props)
    local p = Instance.new("Part")
    p.Anchored = true
    for key, value in props do p[key] = value end
    p.Parent = ws
    return p
end
part({Name = "Floor", Size = V3.new(200, 1, 200), CFrame = CF.new(0, -0.5, 0), Material = Enum.Material.Marble, Color = C3.fromRGB(40, 40, 46)})
part({Name = "WallN", Size = V3.new(60, 20, 2), CFrame = CF.new(0, 10, -30), Material = Enum.Material.SmoothPlastic})
part({Name = "WallE", Size = V3.new(2, 20, 60), CFrame = CF.new(30, 10, 0), Material = Enum.Material.Glass, Transparency = 0.2})
part({Name = "Ceiling", Size = V3.new(60, 1, 60), CFrame = CF.new(0, 20.5, 0)})
for i = 1, 30 do
    part({Name = "Crate" .. i, Size = V3.new(2, 2, 2), CFrame = CF.new((i % 6) * 4 - 12, 1, math.floor(i / 6) * 4 - 10)})
end
-- Under the floor (hidden while it reflects) and a pillar sunk into it (its copy is trimmed at the floor).
local basement = part({Name = "Basement", Size = V3.new(10, 1, 10), CFrame = CF.new(5, -5, 5)})
part({Name = "Pillar", Size = V3.new(2, 8, 2), CFrame = CF.new(-20, 2, 20)})
local lamp = Instance.new("PointLight")
lamp.Brightness, lamp.Range = 3, 20
lamp.Parent = part({Name = "Lamp", Size = V3.new(1, 1, 1), CFrame = CF.new(-5, 8, -5), Material = Enum.Material.Neon})

local original = {Lighting.Ambient, Lighting.OutdoorAmbient, Lighting.ExposureCompensation, Lighting.Brightness, Lighting.EnvironmentDiffuseScale}
env.start()
local player = env.addPlayer({Name = "Lyra", UserId = 155196242})
env.advance(1)

local executor = env.installExecutor({hui = player:FindFirstChild("PlayerGui"), extra = {
    sethiddenproperty = function(instance, property, value) instance[property] = value end,
}})
local function frames(count)
    for _ = 1, count do env.step(1 / 60) end
end
local function noErrors(label)
    local errors = env.takeErrors()
    check(#errors == 0, label .. ": " .. (errors[1] and tostring(errors[1].message) or ""))
    local warnings = env.outputText("warn")
    check(#warnings == 0, label .. " warned: " .. tostring(warnings[1]))
    table.clear(env.output)
end
local function asPlayer(fn) env.asClient(player, fn) end

-- Load Lyra UI, then the shaders.
local okLyra, lyra = env.runSource(player, fs.readFile("src/Lyra.lua"), "Lyra.lua")
assert(okLyra, tostring(lyra))
executor.genv.LyraUI_Library = lyra
local okShaders, problem = env.runSource(player, fs.readFile("shaders/LyraShaders.lua"), "LyraShaders.lua")
assert(okShaders, tostring(problem))
local api = executor.genv.LyraShaders
check(type(api) == "table" and api.Version ~= nil, "API published")
frames(120)
noErrors("boot")
local I = api.Internals

-- 1. Reflection maths --------------------------------------------------------------------
local rng = Types.Random.new(7)
local function randomVector(low, high) return V3.new(rng:NextNumber(low, high), rng:NextNumber(low, high), rng:NextNumber(low, high)) end
local worst, shapeOk, frameOk = 0, true, true
for trial = 1, 400 do
    local n = trial % 3 == 0 and V3.new(0, 1, 0) or trial % 3 == 1 and randomVector(-1, 1).Unit or V3.new(1, 0, 0)
    local p0 = randomVector(-20, 20)
    local mirror = I.Mirror(p0, n)
    local a = n:Cross(math.abs(n.Y) < 0.9 and V3.new(0, 1, 0) or V3.new(1, 0, 0)).Unit
    local b = n:Cross(a).Unit
    local U, V = a, b
    if U:Cross(V):Dot(n) > 0 then V = -V end
    local W, H = rng:NextNumber(5, 120), rng:NextNumber(5, 120)
    local face = p0 + a * rng:NextNumber(-10, 10) + b * rng:NextNumber(-10, 10)
    -- The mirror part is built as CFrame.fromMatrix(centre, -U, -V): its Front face must point along n.
    local frame = CF.fromMatrix(face, -U, -V)
    frameOk = frameOk and (frame.LookVector - n).Magnitude < 1e-4 and (frame.RightVector + U).Magnitude < 1e-4
    local eye = face + n * rng:NextNumber(0.5, 40) + a * rng:NextNumber(-60, 60) + b * rng:NextNumber(-60, 60)
    local projection = I.Projection(eye, face, n, U, V, W, H, 1e6)
    if projection then
        local aspect = (projection.Size.X.Scale * W) / (projection.Size.Y.Scale * H)
        local tanV = math.tan(math.rad(projection.FieldOfView) / 2)
        for _ = 1, 10 do
            local point = face + n * rng:NextNumber(0.2, 30) + a * rng:NextNumber(-40, 40) + b * rng:NextNumber(-40, 40)
            local mirrored = mirror(CF.new(point)).Position
            -- Where the true reflection is: the line from the eye to the mirrored point crosses the surface.
            local de, dm = (eye - face):Dot(n), (mirrored - face):Dot(n)
            local truth = eye + (mirrored - eye) * (de / (de - dm))
            -- Where the viewport draws it.
            local rel = projection.CFrame:PointToObjectSpace(mirrored)
            local u, v = rel.X / (-rel.Z * tanV * aspect), rel.Y / (-rel.Z * tanV)
            if math.abs(u) <= 1 and math.abs(v) <= 1 then
                local cx = projection.Position.X.Scale + (u + 1) / 2 * projection.Size.X.Scale
                local cy = projection.Position.Y.Scale + (1 - v) / 2 * projection.Size.Y.Scale
                worst = math.max(worst, (truth - (face + U * ((cx - 0.5) * W) + V * ((cy - 0.5) * H))).Magnitude)
            end
        end
    end
    local cf = CF.new(randomVector(-10, 10)) * CF.Angles(rng:NextNumber(0, 6), rng:NextNumber(0, 6), rng:NextNumber(0, 6))
    local m = mirror(cf)
    shapeOk = shapeOk and math.abs(m.RightVector:Cross(m.UpVector):Dot(-m.LookVector) - 1) < 1e-4
    local size = randomVector(1, 6)
    for sx = -1, 1, 2 do
        for sy = -1, 1, 2 do
            for sz = -1, 1, 2 do
                local corner = mirror(CF.new(cf * V3.new(sx * size.X / 2, sy * size.Y / 2, sz * size.Z / 2))).Position
                local best = math.huge
                for tx = -1, 1, 2 do
                    for ty = -1, 1, 2 do
                        for tz = -1, 1, 2 do
                            best = math.min(best, (corner - m * V3.new(tx * size.X / 2, ty * size.Y / 2, tz * size.Z / 2)).Magnitude)
                        end
                    end
                end
                shapeOk = shapeOk and best < 1e-3
            end
        end
    end
end
check(worst < 1e-3, string.format("reflections land on the true reflection (worst %.6f studs)", worst))
check(shapeOk, "mirrored parts are proper rotations with the mirrored shape")
check(frameOk, "mirror part faces the surface normal")

-- 2. LUT files ----------------------------------------------------------------------------
local function cube(size, fn)
    local lines = {"TITLE \"test\"", "LUT_3D_SIZE " .. size}
    for bi = 0, size - 1 do
        for gi = 0, size - 1 do
            for ri = 0, size - 1 do
                local r, g, b = fn(ri / (size - 1), gi / (size - 1), bi / (size - 1))
                table.insert(lines, string.format("%.6f %.6f %.6f", r, g, b))
            end
        end
    end
    return table.concat(lines, "\n")
end
-- A PNG strip with stored (uncompressed) deflate blocks, built here so all three block kinds are covered.
local function storedStrip(size)
    local rows = {}
    for gi = 0, size - 1 do
        local row = {string.char(0)}
        for bi = 0, size - 1 do
            for ri = 0, size - 1 do
                table.insert(row, string.char(math.floor(ri / (size - 1) * 255 + 0.5), math.floor(gi / (size - 1) * 255 + 0.5), math.floor(bi / (size - 1) * 255 + 0.5)))
            end
        end
        table.insert(rows, table.concat(row))
    end
    local raw = table.concat(rows)
    local blocks = {"\120\1"}
    local i = 1
    while i <= #raw do
        local piece = raw:sub(i, i + 999)
        i += 1000
        local final = i > #raw and 1 or 0
        table.insert(blocks, string.char(final) .. string.pack("<I2<I2", #piece, 0xFFFF - #piece) .. piece)
    end
    table.insert(blocks, "\0\0\0\0")
    local function chunk(kind, data) return string.pack(">I4", #data) .. kind .. data .. "\0\0\0\0" end
    return "\137PNG\r\n\26\n" .. chunk("IHDR", string.pack(">I4>I4", size * size, size) .. "\8\2\0\0\0") .. chunk("IDAT", table.concat(blocks)) .. chunk("IEND", "")
end
executor.folders.LyraShaders = true
executor.folders["LyraShaders/luts"] = true
executor.files["LyraShaders/luts/identity.cube"] = cube(9, function(r, g, b) return r, g, b end)
executor.files["LyraShaders/luts/contrast.cube"] = cube(9, function(r, g, b)
    local function c(v) return math.clamp((v - 0.5) * 1.3 + 0.5, 0, 1) end
    return c(r), c(g), c(b)
end)
executor.files["LyraShaders/luts/mono.cube"] = cube(9, function(r, g, b)
    local l = 0.2126 * r + 0.7152 * g + 0.0722 * b
    return l, l, l
end)
executor.files["LyraShaders/luts/curve.cube"] = "LUT_1D_SIZE 4\n0 0 0\n0.3 0.33 0.36\n0.6 0.66 0.7\n0.9 1 1\n"
executor.files["LyraShaders/luts/stored.png"] = storedStrip(8)
for _, name in {"identity.png", "warm.png", "not-a-strip.png"} do
    executor.files["LyraShaders/luts/" .. name] = fs.readFile("tests/shaders/fixtures/" .. name)
end
for _, name in {"identity.png", "stored.png", "identity.cube"} do
    local look, why = I.Lut.load(name)
    check(look ~= nil, name .. " loads: " .. tostring(why))
    if look then
        check(near(look.Tint.R, 1) and near(look.Tint.G, 1) and near(look.Tint.B, 1), name .. " keeps colours")
        check(near(look.Contrast, 0) and near(look.Brightness, 0) and near(look.Saturation, 0, 0.05), name .. " fits as neutral")
    end
end
local warm = I.Lut.load("warm.png")
check(warm ~= nil and near(warm.Tint.G, 0.9) and near(warm.Tint.B, 0.72), "warm strip fits its tint")
local contrast = I.Lut.load("contrast.cube")
check(contrast ~= nil and contrast.Contrast > 0.15, "contrast cube fits a contrast boost")
local mono = I.Lut.load("mono.cube")
check(mono ~= nil and mono.Saturation < -0.85, "mono cube fits as desaturated")
check(I.Lut.load("curve.cube") ~= nil, "1D cube loads")
local _, rejected = I.Lut.load("not-a-strip.png")
check(rejected ~= nil and rejected:find("N²") ~= nil, "a PNG that is not a strip is refused with a reason")
check(#I.Lut.files() == 8, "LUT folder is listed (" .. #I.Lut.files() .. ")")

-- 3. Every effect on --------------------------------------------------------------------------
for _, def in api.Effects do
    asPlayer(function() api.SetEnabled(def.Id, true) end)
    frames(60)
    check(def.Active, def.Id .. " starts")
    noErrors("enable " .. def.Id)
end
frames(300)
noErrors("all effects running")
local ssr = api.Effects.ssr
local floor, pillar = ws:FindFirstChild("Floor"), ws:FindFirstChild("Pillar")
check(ssr.Plane ~= nil and math.abs(ssr.Plane.Y) < 1e-3, "the floor under you is the reflection plane")
check(floor.LocalTransparencyModifier > 0.2 and not floor.CastShadow, "the floor turns see-through on this screen (" .. floor.LocalTransparencyModifier .. ")")
check(floor.Transparency == 0, "the floor's real transparency is untouched")
check(basement.LocalTransparencyModifier == 1, "what is under the floor is hidden")
check(ssr.Copies[floor] == nil, "the floor itself is not copied")
local head = player.Character:FindFirstChild("Head")
local headCopy = ssr.Copies[head]
check(headCopy ~= nil, "your character is reflected")
if headCopy then
    check(math.abs(headCopy.Clone.Position.Y + head.Position.Y) < 1e-3, "the reflected head sits mirrored under the floor")
    check(headCopy.Clone.Parent:FindFirstChildOfClass("Humanoid") ~= nil, "reflected characters keep a Humanoid for clothing")
    check(not headCopy.Clone.CanQuery and not headCopy.Clone.CanCollide and not headCopy.Clone.CanTouch, "copies are invisible to raycasts, physics and touches")
    check(headCopy.Clone:IsDescendantOf(env.workspace.CurrentCamera), "copies live in the camera, never replicated")
    local root = player.Character:FindFirstChild("HumanoidRootPart")
    root.CFrame += V3.new(3, 0, 0)
    frames(2)
    check(math.abs(headCopy.Clone.Position.X - head.Position.X) < 1e-3, "the reflection follows you the next frame")
end
local crateCopy = ssr.Copies[ws:FindFirstChild("Crate1")]
check(crateCopy ~= nil and math.abs(crateCopy.Clone.Position.Y + 1) < 1e-3, "objects are mirrored under the floor")
local pillarCopy = ssr.Copies[pillar]
check(pillarCopy ~= nil and math.abs(pillarCopy.Clone.Size.Y - 6) < 1e-3 and math.abs(pillarCopy.Clone.Position.Y + 3) < 1e-3,
    "a part sunk into the floor is trimmed so its copy never pokes through")
local wallMirror
for _, mirror in ssr.Order do
    if math.abs(mirror.Group.Normal.Y) < 0.25 then wallMirror = mirror end
end
check(wallMirror ~= nil, "a wall gets a mirror")
if wallMirror then check(wallMirror.View.ImageTransparency < 0.95, "the wall mirror is visible") end
local cards, flat = 0, true
for _, entry in api.Effects.mxao.Parts do
    for _, card in entry.Cards do
        cards += 1
        flat = flat and math.abs(card.Part.CFrame.LookVector.Y) > 0.99
    end
end
check(cards >= 100 and flat, "crease shading lies flat along the crates (" .. cards .. " cards)")

-- 4. The interface --------------------------------------------------------------------------
local Window = api.Window
local effectsTab
for _, tab in Window.Tabs do
    if tab.Title == "Effects" then effectsTab = tab end
end
local bloomRow
for _, child in effectsTab.Frame:GetChildren() do
    for _, label in child:GetDescendants() do
        if label:IsA("TextLabel") and label.Text == "Bloom" then bloomRow = child end
    end
end
check(bloomRow ~= nil, "the Effects page lists Bloom")
if bloomRow then
    local buttons = {}
    for _, child in bloomRow:GetChildren() do
        if child:IsA("TextButton") then table.insert(buttons, child) end
    end
    table.sort(buttons, function(x, y) return x.Position.X.Offset < y.Position.X.Offset end)
    env.click(buttons[1], player)
    frames(2)
    check(not api.Effects.bloom.Enabled, "the row's button turns Bloom off")
    env.click(buttons[1], player)
    frames(2)
    check(api.Effects.bloom.Enabled, "and on again")
    env.click(buttons[2], player)
    frames(2)
    check(Window.CurrentTab.Title == "Bloom", "the arrow opens the Bloom page")
end
asPlayer(function() api.ApplyLook("Cinematic") end)
frames(60)
check(api.Effects.dof.Enabled and api.Effects.lut.Config.Source == "Print film", "the Cinematic look sets its effects")
asPlayer(function() api.ApplyLook("Noir") end)
frames(30)
check(api.Effects.colour.Config.Tone == "Noir", "the Noir look sets the tone")
noErrors("looks")
check(executor.files["LyraShaders/settings.json"] ~= nil, "settings are saved")
local exported
asPlayer(function() exported = api.Export() end)
check(executor.clipboard == exported and exported:find("fx.ssr.Strength", 1, true) ~= nil, "Export copies every setting")
asPlayer(function() api.Set("ssr", "Strength", 5) end)
check(api.Effects.ssr.Config.Strength == 5, "Set changes a parameter")
asPlayer(function() api.Import(exported) end)
check(api.Effects.ssr.Config.Strength ~= 5, "Import puts the exported settings back")
asPlayer(function() api.Set("lighting", "Technology", "Future") end)
frames(2)
check(Lighting.Technology == Enum.Technology.Future, "lighting technology changes with sethiddenproperty")
local chat = env.game:GetService("TextChatService")
chat:MockSendMessage(player, "/fx off")
frames(2)
check(not api.Effects.ssr.Active, "/fx off switches the engine off")
chat:MockSendMessage(player, "/fx on")
frames(2)
check(api.Effects.ssr.Active, "/fx on switches it back on")
noErrors("export, import and chat")

-- 5. Putting the game's look back --------------------------------------------------------------
Lighting.ClockTime = 9 -- the game's own day cycle while the time lock is on
frames(5)
asPlayer(function() Window:SetFlag("engine.on", false) end)
frames(5)
check(#Lighting:GetChildren() <= 1, "engine off removes every effect layer")
check(Lighting.ClockTime == 9, "the game's own time comes back")
check(floor.LocalTransparencyModifier == 0 and floor.CastShadow, "engine off makes the floor solid again")
check(basement.LocalTransparencyModifier == 0, "engine off shows what is under the floor again")
check(env.workspace.CurrentCamera:FindFirstChild("Reflections", true) == nil, "engine off removes the copies")
local now = {Lighting.Ambient, Lighting.OutdoorAmbient, Lighting.ExposureCompensation, Lighting.Brightness, Lighting.EnvironmentDiffuseScale}
for index, value in original do
    check(tostring(now[index]) == tostring(value), "lighting value " .. index .. " restored")
end
asPlayer(function() Window:SetFlag("engine.on", true) end)
frames(30)
check(ssr.Active, "engine on again")
asPlayer(function() api.Unload() end)
frames(5)
check(#Lighting:GetChildren() == 0, "unload leaves Lighting as it was")
check(Lighting.Technology == Enum.Technology.ShadowMap, "unload restores the lighting technology")
check(env.workspace.CurrentCamera:FindFirstChild("LyraShaders") == nil, "unload removes the world helpers")
check(executor.genv.LyraShaders == nil, "unload clears the global")
noErrors("unload")

print(string.format("%s: %d checks passed%s", failed == 0 and "OK" or "FAILED", passed, failed > 0 and (", " .. failed .. " failed") or ""))
process.exit(failed == 0 and 0 or 1)
