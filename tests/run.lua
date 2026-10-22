--[[
    Drives the showcase and every window behaviour through tests/mock.lua.
    Fails on any error raised inside the library, its tasks or its callbacks.
]]
local checks = 0
local function check(condition, message)
    checks = checks + 1
    if not condition then error("CHECK FAILED: " .. message, 2) end
end
local function settle(seconds) task.wait(seconds or 0.6) end
local function center(item) return item.AbsolutePosition + item.AbsoluteSize / 2 end
local function lyraWarnings()
    local list = {}
    for _, line in ipairs(Mock.Warnings) do if line:find("[Lyra UI]", 1, true) then table.insert(list, line) end end
    return list
end
local UIS = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local Lighting = game:GetService("Lighting")

local finished = false
task.spawn(function()
    local Lyra = Mock.Module
    check(type(Lyra) == "table" and Lyra.Version == "1.0.0", "module loads")

    -- Showcase --------------------------------------------------------------------------------------
    local Window = runShowcase()
    settle()
    check(Lyra.IconSheet and Lyra.IconSheet:find("LyraUI_icons_v1.png", 1, true) ~= nil, "icon sheet decodes and loads")
    check(Window.Alive and Window.Gui.Parent == Mock.PlayerGui, "showcase window is parented to PlayerGui")
    check(#Window.Tabs == 7, "showcase has 7 tabs, got " .. #Window.Tabs)
    check(Window.CurrentTab.Title == "Home", "first tab is selected")
    check(Lighting:FindFirstChild("LyraUI_Blur_Lyra Showcase") ~= nil, "blur effect created")
    check(#Window.Toasts.Active == 1, "welcome toast shown")
    local gui = Window.Gui

    for _, tab in ipairs(Window.Tabs) do
        Window:SelectTab(tab.Title)
        settle(0.3)
        check(tab.Page.Visible and Window.CurrentTab == tab, "tab " .. tab.Title .. " opens")
    end
    Window:SelectTab("Home")

    -- Home: quick actions, confirmation, strip.
    Mock.click(Mock.button(gui, "Notify"))
    settle()
    check(#Window.Toasts.Active == 2, "notify adds a toast")
    Mock.click(Mock.button(gui, "Confirm"))
    check(Window.Modal.Visible, "confirm opens the dialog")
    Mock.click(Window.ModalConfirm.Root)
    settle()
    check(not Window.Modal.Visible and Window.StatusText.Text == "Demo action finished.", "confirm runs its callback")
    Mock.click(Mock.button(gui, "Confirm"))
    settle(11)
    check(not Window.Modal.Visible, "confirm times out on its own")
    Mock.click(Mock.button(gui, "Add"))
    Mock.click(Mock.button(gui, "Add"))
    settle()
    check(Mock.findText(gui, "Step 2", true) ~= nil, "strip shows added entries")
    local guide = Mock.findText(gui, "<u>How it works</u>", true)
    check(guide ~= nil, "guide link exists")
    Mock.click(guide.Parent:FindFirstChildOfClass("TextButton"))
    check(Mock.findText(gui, "<u>Hide how it works</u>", true) ~= nil, "guide opens")

    -- Controls.
    Window:SelectTab("Controls")
    settle(0.3)
    local controls = Window.CurrentTab.Page
    local toggleCard = Mock.findText(controls, "Auto collect", true).Parent
    Mock.click(toggleCard:FindFirstChildOfClass("TextButton"))
    settle()
    check(Window.Flags.AutoCollect == true, "toggle sets its flag")
    check(Window.StatusText.Text == "Auto collect is on.", "toggle callback runs")
    local sliderCard = Mock.findText(controls, "Field of view", true).Parent
    local hit
    for _, item in ipairs(sliderCard:GetDescendants()) do if item:IsA("TextButton") then hit = item end end
    local start = center(hit)
    Mock.drag(hit, start, start + Vector2.new(400, 0), 5)
    settle()
    check(Window.Flags.FieldOfView == 110, "slider drags to its maximum, got " .. tostring(Window.Flags.FieldOfView))
    check(workspace.CurrentCamera.FieldOfView == 110, "slider callback runs")
    local stepperCard = Mock.findText(controls, "Round length", true).Parent
    local plus
    for _, item in ipairs(stepperCard:GetDescendants()) do if item:IsA("TextButton") then plus = item end end
    Mock.click(plus)
    settle()
    check(Window.Flags.RoundLength == 90, "stepper steps up")
    local dropCard = Mock.findText(controls, "Quality", true).Parent
    Mock.click(Mock.button(dropCard, "High"))
    settle()
    check(Window.DropLayer and Window.DropLayer.Visible, "dropdown opens its list")
    Mock.click(Mock.button(Window.DropLayer, "Ultra"))
    settle()
    check(Window.Flags.Quality == "Ultra" and not Window.DropLayer.Visible, "dropdown picks a value and closes")
    local keyCard = Mock.findText(controls, "Quick action", true).Parent
    Mock.click(Mock.button(keyCard, "G"))
    check(Window.Capture ~= nil, "keybind waits for a key")
    Mock.key("H")
    settle()
    check(Window.Flags.QuickKey == "H", "keybind rebinds")
    local toasts = #Window.Toasts.Active
    Mock.key("H")
    settle()
    check(#Window.Toasts.Active == toasts + 1 or #Window.Toasts.Active == 4, "keybind runs its callback")
    local nickname = Mock.findText(controls, "Type a name and press Enter", false)
    check(nickname == nil, "placeholder is not text")
    local boxes = {}
    for _, item in ipairs(controls:GetDescendants()) do if item:IsA("TextBox") then table.insert(boxes, item) end end
    Mock.type(boxes[1], "Vega", true)
    settle()
    check(Window.Flags.Nickname == "Vega" and Window.StatusText.Text == "Hello, Vega!", "input submits on enter")
    Mock.click(Mock.button(controls, "Pets"))
    settle()
    check(Window.StatusText.Text == "Filter: Pets", "chips select")
    Mock.click(Mock.button(controls, "Recent"))
    settle()
    check(Window.StatusText.Text == "Showing recent.", "segmented selects")
    Mock.click(Mock.button(controls, "Show advanced options"))
    check(Mock.findText(controls, "Hide advanced options", true) ~= nil and Mock.findText(controls, "Developer mode", true) ~= nil, "collapsible opens")
    Mock.type(boxes[2], "line one\nline two", false)
    settle()
    check(Window.Flags.Notes == "line one\nline two", "text area saves its flag")
    Mock.click(Mock.button(controls, "Copy"))
    settle()
    check(Mock.Clipboard ~= nil and Mock.Clipboard:find("AutoCollect", 1, true) ~= nil, "action button runs")

    -- Players and playlist.
    Window:SelectTab("Players")
    settle(0.3)
    local people = Window.CurrentTab.Page
    check(Mock.findText(people, "Showing 1 of 1 players", true) ~= nil, "player list renders")
    Mock.click(Mock.button(people, "Wave"))
    settle()
    check(Window.StatusText.Text == "You waved at Lyra Tester.", "row button runs")
    local search
    for _, item in ipairs(people:GetDescendants()) do if item:IsA("TextBox") then search = item; break end end
    search.Text = "nobody"
    settle()
    check(Mock.findText(people, "No players found", true) ~= nil, "search shows the empty state")
    search.Text = ""
    settle()
    local songs = {}
    for _, item in ipairs(people:GetDescendants()) do if item:IsA("TextLabel") and item.Text == "Lyra Sessions" then table.insert(songs, item.Parent) end end
    check(#songs == 5, "playlist has 5 rows, got " .. #songs)
    local first = songs[1]
    local grip
    for _, item in ipairs(first:GetChildren()) do if item:IsA("TextButton") and item.Text == "" and item.Size.X.Offset == 92 then grip = item end end
    check(grip ~= nil, "reorderable rows have a grip")
    local listTop = first.Parent.AbsolutePosition.Y
    local scale = Window.CurrentScale
    Mock.drag(grip, Vector2.new(20, listTop + 10), Vector2.new(20, listTop + 64 * scale * 3.1), 6)
    settle()
    check(Window.StatusText.Text == "Moved song 1 to position 3.", "drag reorders the playlist (" .. Window.StatusText.Text .. ")")
    local order = {}
    for _, item in ipairs(people:GetDescendants()) do if item:IsA("TextLabel") and item.Text == "Lyra Sessions" then table.insert(order, item.Parent) end end
    local titles = {}
    for _, row in ipairs(order) do
        for _, label in ipairs(row:GetChildren()) do
            if label:IsA("TextLabel") and label.TextSize == 14 and label.Text ~= "Lyra Sessions" and tonumber(label.Text) == nil then titles[row.LayoutOrder] = label.Text end
        end
    end
    check(titles[3] == "Moonlight" and titles[1] == "Vega", "playlist order follows the drag")
    Mock.click(Mock.button(order[1], ""))

    -- Shop grid.
    Window:SelectTab("Shop")
    settle(0.3)
    local shop = Window.CurrentTab.Page
    check(Mock.findText(shop, "Starlight Crown", true) ~= nil, "grid shows cards")
    Mock.click(Mock.button(shop, "Hats"))
    settle()
    check(Mock.findText(shop, "Moon Visor", true) == nil and Mock.findText(shop, "Nebula Cape", true) ~= nil, "grid filters by chip")
    Mock.click(Mock.button(shop, "Buy"))
    settle()
    check(Window.Toasts.Active[#Window.Toasts.Active] ~= nil, "grid button runs")

    -- Viewer without a character.
    Window:SelectTab("Viewer")
    settle(0.3)
    Mock.click(Mock.button(Window.CurrentTab.Page, "Load"))
    settle()
    check(Mock.findText(Window.CurrentTab.Page, "Spawn a character first.", true) ~= nil, "preview explains a missing character")

    -- Window chrome ---------------------------------------------------------------------------------
    local grip2 = Window.ResizeGrip
    local before = Window.Main.Size.X.Offset
    local gripAt = center(grip2)
    Mock.drag(grip2, gripAt, gripAt - Vector2.new(400, 60), 4)
    settle()
    check(Window.Settings.WindowW < before and Window.Narrow, "resize grip shrinks the window into the narrow layout")
    check(Window.MenuButton.Root.Visible and not Window.Nav.Visible, "narrow windows hide the rail behind the menu button")
    Mock.click(Window.MenuButton.Root)
    check(Window.Drawer and Window.Nav.Visible and Window.DrawerScrim.Visible, "menu button opens the drawer")
    Mock.click(Window.DrawerScrim)
    check(not Window.Drawer, "scrim closes the drawer")
    Mock.drag(grip2, center(grip2), center(grip2) + Vector2.new(250, 0), 4)
    settle()
    check(not Window.Narrow and Window.LastMini == true, "medium width shows the icon rail")
    Window:ResetSize()
    settle()
    check(Window.Settings.WindowW == 0 and not Window.Narrow and Window.LastMini == false, "reset restores the wide layout")
    local position = Window.Main.Position
    Mock.drag(Window.Header, Vector2.new(position.X.Offset + 80, position.Y.Offset + 20), Vector2.new(position.X.Offset + 20, position.Y.Offset + 5), 3)
    check(Window.Main.Position ~= position, "header drags the window")
    Window:Minimize(true)
    settle()
    check(not Window.Content.Visible and Window.Main.Size.Y.Offset == 52, "minimize collapses to the header")
    Window:Minimize(false)
    Window:Maximize(true)
    settle()
    check(Window.Main.Size.X.Offset >= 1200, "maximize fills the screen")
    Window:Maximize(false)
    settle()

    -- Close, floating button, keybind, chat and Roblox menu reopen.
    Mock.click(Mock.button(Window.Header, ""))
    settle(1)
    check(not Window.Visible and not Window.Main.Visible and Window.Orb.Visible, "close flies the window into the floating button")
    Mock.click(Window.Orb)
    settle(1)
    check(Window.Visible and Window.Main.Visible and not Window.Orb.Visible, "floating button reopens the window")
    Mock.key("RightControl")
    settle(1)
    check(not Window.Visible, "shortcut key hides the window")
    Mock.key("RightControl")
    settle(1)
    check(Window.Visible, "shortcut key shows the window")
    Window:SetVisible(false)
    settle(1)
    Mock.Player.Chatted:Fire("/lyra")
    settle(1)
    check(Window.Visible, "chat command reopens the window")
    Window:SetVisible(false)
    settle(1)
    Mock.EmoteCommand.Triggered:Fire(nil, "/e lyra")
    settle(1)
    check(Window.Visible, "emote chat command reopens the window")
    Window:SetVisible(false)
    settle(1)
    for _ = 1, 3 do GuiService.MenuOpened:Fire(); GuiService.MenuClosed:Fire(); settle(0.2) end
    settle(1)
    check(Window.Visible, "opening the Roblox menu 3 times reopens the window")
    Mock.Player.Chatted:Fire("/hello stars")
    settle()
    check(Mock.findText(Window.Toasts.Container, "Hello, stars!", true) ~= nil, "custom chat command runs with arguments")

    -- Floating button off: the first close asks first, and the hint names the ways back.
    Window.SettingControls.FloatingButton:Set(false)
    settle()
    check(Window.Settings.FloatingButton == false, "settings toggle changes the setting")
    Mock.click(Mock.button(Window.Header, ""))
    check(Window.Modal.Visible and Window.ModalTitle.Text == "Hide Lyra Showcase?", "first hide asks for confirmation")
    Mock.click(Window.ModalConfirm.Root)
    settle(1)
    check(not Window.Visible and Window.Badge ~= nil and not Window.Orb.Visible, "hide without the floating button uses the flight badge")
    check(Mock.findText(Window.Toasts.Container, "To reopen it, press RightControl, open and close the Roblox menu 3 times, or type /lyra in chat.", true) ~= nil, "hidden hint names every way back")
    Window:Show()
    settle(1)
    Window.Settings.MenuReopen = false
    local keyboard = Mock.InputService
    Mock.info(keyboard).Extra.KeyboardEnabled = false
    Window.ChatOK = false
    Mock.click(Mock.button(Window.Header, ""))
    check(Window.ModalTitle.Text == "Nothing can reopen the window", "closing with no way back is guarded")
    Mock.click(Window.ModalConfirm.Root)
    settle(1)
    check(Window.Settings.MenuReopen == true and not Window.Visible, "guard turns the Roblox menu shortcut on before hiding")
    Mock.info(keyboard).Extra.KeyboardEnabled = true
    Window.ChatOK = true
    Window:Show()
    settle(1)
    Window.SettingControls.FloatingButton:Set(true)

    -- Settings, themes and scale.
    Window:SelectTab("Settings")
    settle(0.3)
    Window:SetTheme("Rose")
    settle()
    check(Window.Main.BackgroundColor3 == Lyra.Themes.Rose.Base, "theme repaints the window")
    check(Window.HeaderTitle.TextColor3 == Lyra.Themes.Rose.Text, "theme repaints text")
    check(Window.SettingControls.Theme:Get() == "Rose", "theme dropdown follows SetTheme")
    Window:SetTheme({Accent = Color3.fromRGB(255, 0, 0)})
    settle()
    check(Window.WindowStroke.Color == Color3.fromRGB(255, 0, 0) and Window.Main.BackgroundColor3 == Lyra.Themes.Lavender.Base, "custom theme table works")
    Window:SetTheme("Midnight")
    local scaleCard = Mock.findText(Window.CurrentTab.Page, "Interface size", true).Parent
    local scalePlus
    for _, item in ipairs(scaleCard:GetDescendants()) do if item:IsA("TextButton") then scalePlus = item end end
    Mock.click(scalePlus)
    settle()
    check(Window.Settings.Scale == 70 and Window.CurrentScale == 0.7, "interface size stepper scales the window")
    Window:SetScale(0)
    Mock.click(Mock.button(Window.CurrentTab.Page, "Show advanced options"))
    local motion = Mock.findText(Window.CurrentTab.Page, "Reduced motion", true).Parent
    Mock.click(motion:FindFirstChildOfClass("TextButton"))
    settle()
    check(Window.Settings.ReducedMotion == true, "reduced motion toggle")
    Window.SettingControls.ReducedMotion:Set(false)

    -- Config is written and restored by a second run.
    settle(1)
    local saved = Mock.Files["LyraUI/Showcase.json"]
    check(saved ~= nil, "config file written")
    local data = game:GetService("HttpService"):JSONDecode(saved)
    check(data.Flags.AutoCollect == true and data.Flags.Quality == "Ultra" and data.Settings.Theme == "Midnight", "config holds flags and settings")
    local inputConnections = UIS.InputBegan:Count()
    local second = runShowcase()
    settle()
    check(not Window.Alive and Window.Gui.Parent == nil, "running again replaces the old window")
    check(second.Flags.AutoCollect == true and second.Flags.Quality == "Ultra" and second.Flags.QuickKey == "H", "flags restored")
    check(second.ThemeName == "Midnight", "saved theme restored")
    check(second.StatusText.Text == "Auto collect is on.", "restored toggle runs its callback")
    check(UIS.InputBegan:Count() <= inputConnections, "old window disconnected its input handlers")
    second:Destroy()
    check(second.Gui.Parent == nil and Lighting:FindFirstChild("LyraUI_Blur_Lyra Showcase") == nil, "destroy removes the window and the blur")

    -- Direct API coverage on a fresh window with vector icons (no custom assets).
    Lyra.IconSheet = false
    local W = Lyra.new({Title = "API", Name = "API", ConfigFile = false, FloatingButton = false, Theme = "Mint", Logo = 12345, Size = Vector2.new(700, 500)})
    settle()
    check(W.ConfigPath == nil and W.Theme == Lyra.Themes.Mint, "options are applied")
    local T = W:Tab("One", "star")
    local left, right = T:Columns()
    left:Paragraph({Text = "<b>Rich</b> text", RichText = true})
    local label = right:Label("count")
    label:Set("changed", "Green")
    T:Divider()
    local image = T:Image({Image = "rbxassetid://1", Caption = "Banner"})
    image:SetImage("rbxassetid://2")
    T:Empty("Nothing", "Still nothing", "box")
    local row = T:Row({Title = "Row", Subtitle = "sub", Icon = "user", Buttons = {{Title = "Go", Icon = "arrow"}}})
    row:SetSelected(true); row:SetTitle("Row 2"); row:SetSubtitle("sub 2"); row:SetImage("rbxassetid://3")
    local group = T:Group("CAPTION")
    local bad = group:Button({Title = "Broken", Callback = function() error("boom") end})
    bad:Fire()
    settle()
    check(#lyraWarnings() == 1 and W.StatusText.Text:find("boom", 1, true) ~= nil, "a failing callback is reported, not fatal")
    table.clear(Mock.Warnings)
    bad:SetEnabled(false); bad:SetText("Disabled"); bad:SetPrimary(true)
    local drop = T:Dropdown({Options = {{Value = 1, Label = "One"}, {Value = 2, Label = "Two"}}, Placeholder = "Pick"})
    check(drop:Get() == nil, "dropdown with a placeholder starts empty")
    drop:SetOptions({"A", "B"})
    drop:Set("B")
    check(drop:Get() == "B", "dropdown SetOptions and Set")
    local chips = T:Chips({Options = {"X", "Y"}, Small = true})
    chips:SetOptions({"Z"})
    check(chips:Get() == "Z", "chips SetOptions resets a missing value")
    local stepper = T:Stepper({Title = "Step", Min = 0, Max = 1, Step = 0.25})
    stepper:Set(0.75)
    check(stepper:Get() == 0.75, "decimal stepper")
    local slider = T:Slider({Title = "Slide", Min = 0, Max = 1, Step = 0.1, Default = 0.3})
    slider:Set(0.66)
    check(slider:Get() == 0.7, "slider snaps to its step, got " .. tostring(slider:Get()))
    local input = T:Input({Placeholder = "Numbers", Numeric = true, MaxLength = 4, Button = true})
    input.Box.Text = "12ab345"
    check(input:Get() == "1234", "numeric input filters and limits, got " .. input:Get())
    input:Set("7")
    input:Focus()
    local area = T:Code({Text = "print(1)", Editable = false})
    check(area:Get() == "print(1)", "code box")
    local preview = T:Preview({Height = 260})
    local model = Instance.new("Model")
    Instance.new("Part", model)
    preview:Loading(true, "Loading")
    settle(1)
    preview:SetModel(model)
    check(model.Parent == preview.World and preview.Viewport.Visible, "preview shows a model")
    Mock.drag(preview.Viewport, Vector2.new(100, 100), Vector2.new(160, 120), 3)
    Mock.wheel(preview.Viewport, true)
    settle()
    check(preview.Rotation ~= 0 and preview.Zoom < 1, "preview rotates and zooms")
    preview:SetImage("rbxassetid://5", "Image only")
    preview:Clear()
    check(model.Parent == nil, "preview clear destroys the model")
    local strip = T:Strip({Items = {{Label = "A", Image = "rbxassetid://1"}, {Label = "B", Current = true}}})
    strip:Set({})
    local listObject = T:List({Items = {{Title = "One"}, {Title = "Two"}}})
    listObject:Remove(1)
    check(#listObject:Get() == 1, "list remove")
    listObject:Clear()
    local gridObject = T:Grid({Items = {{Title = "Card", Image = "rbxassetid://1", Checked = true, Button = false}}})
    gridObject.Cards[1]:SetCaption("caption")
    gridObject:Clear()
    local link = T:Link({Title = "Docs", Url = "https://example.com/?a=1&b=<2>"})
    Mock.click(link.Button.Root)
    check(Mock.Clipboard == "https://example.com/?a=1&b=<2>", "link copies the raw url")
    local collapsed = T:Collapsible({Title = "More", Open = true})
    collapsed:Toggle({Title = "Inner"})
    collapsed:SetOpen(false)
    check(not collapsed:IsOpen(), "collapsible SetOpen")
    T:Profile({Title = "Someone", Handle = "@someone"})
    local keybind = T:Keybind({Title = "Key"})
    check(keybind:Get() == "None", "keybind without default")
    local T2 = W:Tab({Title = "Two"})
    T2:Section({Title = "Hidden tab"})
    T2:SetVisible(false)
    check(not T2.RailButton.Root.Visible, "hidden tab leaves the rail")
    T2:SetVisible(true)
    T2:Select()
    group:SetVisible(false)
    W:SetTitle("API 2", "sub")
    W:Status("Loading", "loading")
    check(W.StatusDot.BackgroundColor3 == W.Theme.Accent, "status colours the dot")
    local handle = W:Notify({Title = "Action", Text = "With a button", Action = {Text = "Open", Callback = function() W:Status("action", "success") end}, Featured = true, Duration = 0})
    check(handle ~= nil, "featured toast")
    handle:Dismiss()
    W:Notify("Just a title")
    W.Toasts:Clear()
    W:Confirm("Title", "Text", function() end)
    Mock.click(W.ModalCancel.Root)
    W:SetVisible(false)
    settle(1)
    check(not W.Main.Visible and W.Badge and not W.Badge.Visible, "flight badge hides after the flight")
    W:Show()
    settle(1)
    W:Destroy()
    check(Lyra.GetWindow("API") == nil, "destroyed windows leave the registry")

    -- Minimal example and start hidden.
    Lyra.IconSheet = nil
    Mock.Files["LyraUI/My_Hub.json"] = '{"Version":1,"Settings":{"StartHidden":true,"Scale":85},"Flags":{"Power":80}}'
    local minimal = runMinimal()
    settle()
    check(not minimal.Visible and minimal.Orb.Visible and minimal.Settings.Scale == 85, "start hidden opens straight into the floating button")
    check(minimal.Flags.Power == 80, "minimal example restores its slider")
    Lyra.DestroyAll()
    check(not minimal.Alive, "DestroyAll")

    finished = true
end)

for _ = 1, 2000 do
    if finished or #Mock.Errors > 0 then break end
    Mock.advance(0.05)
end
Mock.advance(20)

if #Mock.Errors > 0 then
    print("FAILED with " .. #Mock.Errors .. " error(s):")
    for _, problem in ipairs(Mock.Errors) do print(problem) end
    error("tests failed")
end
if not finished then error("the scenario did not finish") end
local warnings = lyraWarnings()
if #warnings > 0 then
    for _, line in ipairs(warnings) do print(line) end
    error("unexpected Lyra UI warnings")
end
print(string.format("OK: %d checks passed", checks))
