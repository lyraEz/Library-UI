-- The smallest useful Lyra UI hub: one tab, a few controls and the built-in settings.
local Lyra = loadstring(game:HttpGet("https://raw.githubusercontent.com/lyraEz/Library-UI/main/src/Lyra.lua"))()

local Window = Lyra:CreateWindow({
    Title = "My Hub",
    Subtitle = "by you  ·  v1.0",
})

local Main = Window:Tab({Title = "Main", Icon = "star"})
Main:Section("Main", "Your features go here.")

Main:Toggle({Title = "Enabled", Description = "Turns the feature on.", Flag = "Enabled", Callback = function(on)
    print("Enabled:", on)
end})

Main:Slider({Title = "Power", Min = 0, Max = 100, Default = 50, Suffix = "%", Flag = "Power", Callback = function(value)
    print("Power:", value)
end})

Main:Button({Title = "Say hello", Icon = "bell", Primary = true, Callback = function()
    Window:Notify({Title = "Hello!", Text = "Lyra UI is working.", Kind = "success"})
end})

Window:SettingsTab()
return Window
