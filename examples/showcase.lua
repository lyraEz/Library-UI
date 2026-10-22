--[[
    Lyra UI showcase: every element in one hub.
    Run it in your executor, then take the parts you need.
]]
local Lyra = loadstring(game:HttpGet("https://raw.githubusercontent.com/lyraEz/Library-UI/main/src/Lyra.lua"))()

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

local Window = Lyra:CreateWindow({
    Title = "Lyra Showcase",
    Subtitle = "Lyra UI  ·  v" .. Lyra.Version,
    Theme = "Lavender",
    Keybind = Enum.KeyCode.RightControl,
    ChatCommand = "lyra", -- type /lyra (or /e lyra) in chat to bring the window back
    ConfigFile = "LyraUI/Showcase",
    Status = "Ready to explore.",
})

-- HOME -----------------------------------------------------------------------
local Home = Window:Tab({Title = "Home", Icon = "user"})
Home:Section("Welcome to Lyra UI", "Every control here is a native Roblox instance. Drag the corner to resize the window: the side rail turns into icons, then into a drawer.")

local Quick = Home:Group({Title = "QUICK ACTIONS"})
Quick:ButtonRow({
    {Title = "Notify", Icon = "bell", Primary = true, Callback = function()
        Window:Notify({Title = "Hello there", Text = "This is a Lyra toast. Tap it to close it.", Kind = "success", Icon = "circle-check"})
    end},
    {Title = "Confirm", Icon = "info", Callback = function()
        Window:Confirm({Title = "Run the demo action?", Text = "This dialog closes on its own after 10 seconds.", Confirm = "Run it", Seconds = 10,
            Callback = function() Window:Status("Demo action finished.", "success") end})
    end},
    {Title = "Settings", Icon = "settings", Callback = function() Window:SelectTab("Settings") end},
})

local activity = {}
local Timeline
local function renderTimeline()
    local items = {}
    for index, entry in ipairs(activity) do
        table.insert(items, {Label = entry, Icon = "star", Current = index == #activity, Callback = function()
            Window:Status("You picked " .. entry .. ".", "info")
        end})
    end
    Timeline:Set(items)
    Timeline:SetHint(#activity > 0 and (#activity .. " entries · tap one") or "")
end
Timeline = Home:Strip({Title = "Activity", Icon = "history", Empty = "Entries you add appear here.", Buttons = {
    {Title = "Add", Icon = "plus", Primary = true, Callback = function()
        table.insert(activity, "Step " .. (#activity + 1))
        renderTimeline()
    end},
    {Title = "Undo", Icon = "undo", Callback = function()
        table.remove(activity)
        renderTimeline()
    end},
    {Title = "Clear", Icon = "trash", Callback = function()
        activity = {}
        renderTimeline()
    end},
}})

Home:Guide({Title = "How it works", Lines = {
    "1. Create a window with Lyra:CreateWindow.",
    "2. Add tabs with Window:Tab and fill them with elements.",
    "3. Give an element a Flag to save its value between runs.",
}, Note = "Close the window with the X: the floating button, the shortcut key or /lyra in chat bring it back."})

-- CONTROLS -------------------------------------------------------------------
local Controls = Window:Tab({Title = "Controls", Icon = "sliders-horizontal"})
Controls:Section("Controls", "Values with a Flag are saved to a file and restored the next time the script runs.")
Controls:Toggle({Title = "Auto collect", Description = "Collects drops near your character.", Flag = "AutoCollect", Callback = function(on)
    Window:Status(on and "Auto collect is on." or "Auto collect is off.", on and "success" or "info")
end})
Controls:Slider({Title = "Field of view", Description = "Your camera's field of view.", Min = 50, Max = 110, Default = 70, Suffix = "°", Flag = "FieldOfView",
    Callback = function(value)
        local camera = workspace.CurrentCamera
        if camera then camera.FieldOfView = value end
    end})
Controls:Stepper({Title = "Round length", Description = "How long each round lasts.", Values = {30, 60, 90, 120, 180, 300}, Default = 60, Flag = "RoundLength",
    Format = function(seconds) return seconds < 60 and (seconds .. " s") or ((seconds / 60) .. " min") end})
Controls:Dropdown({Title = "Quality", Description = "Pick one of several named options.", Options = {"Low", "Medium", "High", "Ultra"}, Default = "High", Flag = "Quality"})
Controls:Keybind({Title = "Quick action", Description = "Press this key anywhere to run the action.", Default = Enum.KeyCode.G, Flag = "QuickKey",
    Callback = function() Window:Notify({Title = "Quick action", Text = "You pressed the shortcut.", Kind = "info", Icon = "gamepad-2"}) end})
Controls:Input({Title = "Nickname", Placeholder = "Type a name and press Enter", Icon = "pencil", Flag = "Nickname", Callback = function(text, enter)
    if enter and text ~= "" then Window:Status("Hello, " .. text .. "!", "success") end
end})
Controls:Chips({Options = {"All", "Weapons", "Pets", "Cosmetics", "Boosts"}, Callback = function(choice) Window:Status("Filter: " .. choice, "info") end})
Controls:Segmented({Options = {{Label = "Favorites", Icon = "star", Value = "Favorites"}, {Label = "Recent", Icon = "history", Value = "Recent"}},
    Callback = function(choice) Window:Status("Showing " .. choice:lower() .. ".", "info") end})
local Advanced = Controls:Collapsible()
Advanced:Toggle({Title = "Developer mode", Description = "Extra logs in the console.", Flag = "DeveloperMode"})
Advanced:Stepper({Title = "Retries", Description = "Attempts before giving up.", Min = 1, Max = 5, Default = 3, Flag = "Retries"})
Controls:TextArea({Placeholder = "Paste a config code here", Height = 70, Flag = "Notes"})
Controls:Action({Title = "Copy config", Description = "Copies your saved values as text.", Button = "Copy", Icon = "copy", Callback = function()
    local ok = pcall(setclipboard, game:GetService("HttpService"):JSONEncode(Window.Flags))
    Window:Status(ok and "Config copied." or "Clipboard is unavailable here.", ok and "success" or "warning")
end})

-- PLAYERS --------------------------------------------------------------------
local People = Window:Tab({Title = "Players", Icon = "users"})
People:Section("Players in this server", "Rows adapt to the window: on narrow windows their buttons keep only the icons.")
local playerList, playerCount
local function renderPlayers(term)
    term = (term or ""):lower()
    local rows, all = {}, Players:GetPlayers()
    for _, player in ipairs(all) do
        if term == "" or player.Name:lower():find(term, 1, true) or player.DisplayName:lower():find(term, 1, true) then
            table.insert(rows, {Title = player.DisplayName, Subtitle = "@" .. player.Name, Current = player == LocalPlayer,
                Image = "rbxthumb://type=AvatarHeadShot&id=" .. player.UserId .. "&w=150&h=150",
                Buttons = {
                    {Title = "Wave", Primary = true, Callback = function() Window:Status("You waved at " .. player.DisplayName .. ".", "success") end},
                    {Title = "Profile", Icon = "user", Callback = function() Window:Status(player.Name .. " · ID " .. player.UserId, "info") end},
                    {Icon = "star", Callback = function() Window:Notify({Title = "Added to favorites", Text = player.DisplayName, Kind = "success", Icon = "star"}) end},
                }})
        end
    end
    playerList:Set(rows)
    playerCount:Set("Showing " .. #rows .. " of " .. #all .. " players")
end
People:Input({Placeholder = "Search players by name", Changed = renderPlayers})
playerCount = People:Label("")
playerList = People:List({EmptyTitle = "No players found", EmptyText = "Try another name or clear the search."})
renderPlayers()
Window:Connect(Players.PlayerAdded, function() renderPlayers() end)
Window:Connect(Players.PlayerRemoving, function() task.defer(renderPlayers) end)

People:Section("Playlist", "Drag the number or the picture of a row to move it.")
local Playlist
Playlist = People:List({Reorderable = true, EmptyTitle = "Your playlist is empty", EmptyText = "Add songs to see them here.",
    OnReorder = function(from, to) Window:Status("Moved song " .. from .. " to position " .. to .. ".", "info") end})
for _, song in ipairs({"Moonlight", "Vega", "Nebula", "Afterglow", "Stardust"}) do
    Playlist:Add({Title = song, Subtitle = "Lyra Sessions", Icon = "star", Buttons = {
        {Title = "Play", Callback = function(item) Window:Status("Playing " .. item.Title .. ".", "success") end},
        {Icon = "x", Callback = function(item) Playlist:Remove(item) end},
    }})
end

-- SHOP -----------------------------------------------------------------------
local Shop = Window:Tab({Title = "Shop", Icon = "box"})
Shop:Section("Item shop", "A responsive grid: two columns on phones, more as the window grows.")
local catalog = {
    {Title = "Starlight Crown", Caption = "Hats  ·  250", Category = "Hats", Icon = "star", Tag = "NEW"},
    {Title = "Comet Trail", Caption = "Effects  ·  400", Category = "Effects", Icon = "refresh-cw"},
    {Title = "Moon Visor", Caption = "Faces  ·  120", Category = "Faces", Icon = "eye-off", Owned = true},
    {Title = "Nebula Cape", Caption = "Hats  ·  300", Category = "Hats", Icon = "shirt"},
    {Title = "Orbit Ring", Caption = "Effects  ·  180", Category = "Effects", Icon = "repeat", Tag = "SALE"},
    {Title = "Vega Mask", Caption = "Faces  ·  90", Category = "Faces", Icon = "user"},
}
local ShopGrid
local function fillShop(category)
    local items = {}
    for _, product in ipairs(catalog) do
        if category == "All" or product.Category == category then
            table.insert(items, {Title = product.Title, Caption = product.Caption, Icon = product.Icon, Tag = product.Tag, Checked = product.Owned,
                Button = {Title = product.Owned and "Equip" or "Buy", Primary = not product.Owned, Callback = function(_, card)
                    product.Owned = true
                    card:SetChecked(true)
                    Window:Notify({Title = product.Title, Text = "Added to your inventory.", Kind = "success", Icon = "box"})
                end}})
        end
    end
    ShopGrid:Set(items)
end
Shop:Chips({Options = {"All", "Hats", "Faces", "Effects"}, Callback = fillShop})
ShopGrid = Shop:Grid({})
fillShop("All")

-- VIEWER ---------------------------------------------------------------------
local Viewer = Window:Tab({Title = "Viewer", Icon = "gamepad-2"})
Viewer:Section("3D preview", "Show any model: drag to rotate, scroll or use the buttons to zoom.")
local Preview = Viewer:Preview({Title = "YOUR CHARACTER", Hint = "Tap Load to preview your character."})
Viewer:ButtonRow({
    {Title = "Load", Icon = "download", Primary = true, Callback = function()
        local character = LocalPlayer.Character
        if not character then Preview:Clear("Spawn a character first."); return end
        Preview:Loading(true, "Building the preview…")
        character.Archivable = true
        local clone = character:Clone()
        if not clone then Preview:Clear("This character cannot be copied."); return end
        for _, item in ipairs(clone:GetDescendants()) do
            if item:IsA("Script") or item:IsA("LocalScript") then item:Destroy() end
        end
        Preview:SetModel(clone)
    end},
    {Title = "Clear", Icon = "x", Callback = function() Preview:Clear() end},
})

-- ABOUT ----------------------------------------------------------------------
local About = Window:Tab({Title = "About", Icon = "code-xml"})
About:Section("Made by lyraEz", "Find the library and the community here.")
About:Profile({Caption = "GITHUB PROFILE", Title = "lyraEz", Handle = "@lyraEz", Initial = "L", ImageUrl = "https://github.com/lyraEz.png?size=256",
    Bio = "The moon reminds me that even in darkness, there's always a <b>beautiful light</b>", Url = "https://github.com/lyraEz", Label = "GitHub"})
About:Link({Title = "Discord", Subtitle = "Join the community", Icon = "discord", Url = "https://discord.gg/8bxXcn2Vfb"})

-- SETTINGS -------------------------------------------------------------------
local Settings = Window:SettingsTab()
Settings:Section("Showcase")
Settings:Action({Title = "Close the showcase", Description = "Removes the window and everything it created.", Button = "Close", Icon = "x",
    Callback = function()
        Window:Confirm({Title = "Close the showcase?", Text = "Run the script again to bring it back.", Confirm = "Close", Callback = function() Window:Destroy() end})
    end})

-- CHAT COMMANDS -----------------------------------------------------------------
Window:Command("hello", function(args)
    Window:Notify({Title = "Hello" .. (args ~= "" and (", " .. args) or "") .. "!", Text = "Sent from the chat with /hello.", Kind = "info", Icon = "bell"})
end)

Window:Notify({Title = "Lyra UI loaded", Text = "Press RightControl or type /lyra to show or hide the window.", Kind = "success", Icon = "circle-check"})
return Window
