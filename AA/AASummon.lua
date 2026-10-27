-- Ensure the game is fully loaded
repeat task.wait() until game:IsLoaded()

-- Variables
getgenv().AutoStar = false       -- Start with AutoStar disabled
getgenv().AutoSakamoto = false   -- Start with AutoSakamoto disabled
getgenv().AutoClick = false      -- Start with AutoClick disabled

local replicatedStorage = game:GetService("ReplicatedStorage")
local endpoints = replicatedStorage:WaitForChild("endpoints"):WaitForChild("client_to_server")
local virtualInput = game:GetService("VirtualInputManager")
local player = game:GetService("Players").LocalPlayer

-- Fixed Click Location
local fixedX = 600 -- Change this to the desired X coordinate
local fixedY = 300 -- Change this to the desired Y coordinate

-- Function to buy from the banner
local function buyFromBanner(eventName, option)
    pcall(function()
        local args = {
            [1] = eventName,
            [2] = option
        }
        endpoints:WaitForChild("buy_from_banner"):InvokeServer(unpack(args))
    end)
end

-- Function for AutoStar
local function autoStarLoop()
    while getgenv().AutoStar do
        buyFromBanner("Christmas2024", "gems10")
        task.wait(1) -- 1-second delay
    end
end

-- Function for AutoSakamoto
local function autoSakamotoLoop()
    while getgenv().AutoSakamoto do
        buyFromBanner("SakamotoEvent", "gems10")
        task.wait(1) -- 1-second delay
    end
end

-- Function for AutoClick at a fixed location
local function autoClickLoop()
    while getgenv().AutoClick do
        pcall(function()
            virtualInput:SendMouseButtonEvent(fixedX, fixedY, 0, true, nil, 0) -- Mouse down at (X, Y)
            virtualInput:SendMouseButtonEvent(fixedX, fixedY, 0, false, nil, 0) -- Mouse up at (X, Y)
        end)
        task.wait(0.1) -- 0.1-second delay
    end
end

-- GUI setup
local Material = loadstring(game:HttpGet("https://raw.githubusercontent.com/Kinlei/MaterialLua/master/Module.lua"))()

local MainUI = Material.Load({
    Title = "AA Auto Features",
    Style = 1,
    SizeX = 200,
    SizeY = 200,
    Theme = "Dark"
})

local MainTab = MainUI.New({ Title = " Features" })

-- Toggle for AutoStar
MainTab.Toggle({
    Text = "Enable Auto Star",
    Callback = function(state)
        getgenv().AutoStar = state
        if state then
            autoStarLoop()
        end
    end,
    Enabled = false
})

-- Toggle for AutoSakamoto
MainTab.Toggle({
    Text = "Enable Auto Sakamoto",
    Callback = function(state)
        getgenv().AutoSakamoto = state
        if state then
            autoSakamotoLoop()
        end
    end,
    Enabled = false
})

-- Toggle for AutoClick
MainTab.Toggle({
    Text = "Enable Auto Click",
    Callback = function(state)
        getgenv().AutoClick = state
        if state then
            autoClickLoop()
        end
    end,
    Enabled = false
})
