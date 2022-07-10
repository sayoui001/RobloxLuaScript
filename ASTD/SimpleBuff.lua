repeat wait() until game:IsLoaded() 
_G.AutoErwin = false
_G.AutoMerlin = false
_G.AutoErwinX2 = false
_G.AutoMerlinX2 = false

local Material = loadstring(game:HttpGet("https://raw.githubusercontent.com/Kinlei/MaterialLua/master/Module.lua"))()
local me = game.Players.LocalPlayer
local remote = game.ReplicatedStorage.Remotes.Input

local MainUI = Material.Load({
    Title = "Simple ASTD Buff",
    Style = 1,
    SizeX = 200,
    SizeY = 150,
    Theme = "Dark"
})

local ErwinTab = MainUI.New({
    Title = " Erwin "
})

local MerlinTab = MainUI.New({
    Title = " Merlin "
})

local CreditTab = MainUI.New({
    Title = " Credit "
})

local ErwinMain = ErwinTab.Toggle({
    Text = "  Erwin Buff",
    Callback = function(Value)
        _G.AutoErwin = Value
        if Value then
            ErwinBuff()
        end
    end,
    Enabled = false
})

local ErwinMainX2 = ErwinTab.Toggle({
    Text = "  Erwin Buff X2",
    Callback = function(Value)
        _G.AutoErwinX2 = Value
        if Value then
            ErwinBuffX2()
        end
    end,
    Enabled = false
})

local MerlinMain = MerlinTab.Toggle({
    Text = "  Merlin Buff",
    Callback = function(Value)
        _G.AutoMerlin = Value
        if Value then
            MerlinBuff()
        end
    end,
    Enabled = false
})

local MerlinMainX2 = MerlinTab.Toggle({
    Text = "  Merlin Buff X2",
    Callback = function(Value)
        _G.AutoMerlinX2 = Value
        if Value then
            MerlinBuffX2()
        end
    end,
    Enabled = false
})

local CreditMain = CreditTab.Button({
    Text = "  By  :  xLUC1F3Rx#0491",
    Callback = function()
    end
})

function ErwinBuff()
    spawn(function()
        while _G.AutoErwin == true do
            local me = game.Players.LocalPlayer
            local remote = game.ReplicatedStorage.Remotes.Input
            local Erwin1 = {}
            local Erwin2 = {}
            local Erwin3 = {}

            for _, v in pairs(game:GetService("Workspace").Unit:GetChildren()) do
                if v.Name == 'Erwin' and v.Owner.Value == me then
                    table.insert(Erwin1, v)
                end
            end

            if #Erwin1 == 4 then
                while true do
                    remote:FireServer('UseSpecialMove', Erwin1[1])
                    wait(15.4)
                    if not _G.AutoErwin then
                        break
                    end
                    remote:FireServer('UseSpecialMove', Erwin1[3])
                    wait(15.4)
                    if not _G.AutoErwin then
                        break
                    end
                    remote:FireServer('UseSpecialMove', Erwin1[2])
                    wait(15.4)
                    if not _G.AutoErwin then
                        break
                    end
                    remote:FireServer('UseSpecialMove', Erwin1[4])
                    wait(15.4)
                    if not _G.AutoErwin then
                        break
                    end
                end
            elseif #Erwin1 == 8 then
                for i = 1, 4 do
                    table.insert(Erwin2, Erwin1[1])
                    table.remove(Erwin1, 1)
                end
                for i = 1, 4 do
                    table.insert(Erwin3, Erwin1[1])
                    table.remove(Erwin1, 1)
                end
                while true do
                    remote:FireServer('UseSpecialMove', Erwin2[1])
                    wait(1)
                    remote:FireServer('UseSpecialMove', Erwin3[1])
                    wait(14.4)
                    if not _G.AutoErwin then
                        break
                    end
                    remote:FireServer('UseSpecialMove', Erwin2[3])
                    wait(1)
                    remote:FireServer('UseSpecialMove', Erwin3[3])
                    wait(14.4)
                    if not _G.AutoErwin then
                        break
                    end
                    remote:FireServer('UseSpecialMove', Erwin2[2])
                    wait(1)
                    remote:FireServer('UseSpecialMove', Erwin3[2])
                    wait(14.4)
                    if not _G.AutoErwin then
                        break
                    end
                    remote:FireServer('UseSpecialMove', Erwin2[4])
                    wait(1)
                    remote:FireServer('UseSpecialMove', Erwin3[4])
                    wait(14.4)
                    if not _G.AutoErwin then
                        break
                    end
                end
            elseif #Erwin1 > 4 and #Erwin1 < 8 then
                repeat
                    wait(1)
                    table.remove(Erwin1, 1)
                until #Erwin1 == 4
                while true do
                    remote:FireServer('UseSpecialMove', Erwin1[1])
                    wait(15.4)
                    if not _G.AutoErwin then
                        break
                    end
                    remote:FireServer('UseSpecialMove', Erwin1[3])
                    wait(15.4)
                    if not _G.AutoErwin then
                        break
                    end
                    remote:FireServer('UseSpecialMove', Erwin1[2])
                    wait(15.4)
                    if not _G.AutoErwin then
                        break
                    end
                    remote:FireServer('UseSpecialMove', Erwin1[4])
                    wait(15.4)
                    if not _G.AutoErwin then
                        break
                    end
                end
            end
            if not _G.AutoErwin then
                break
            end
            wait(2)
        end
    end)
end

function MerlinBuff()
    spawn(function()
        while _G.AutoMerlin == true do

            local Merlin1 = {}
            local Merlin2 = {}
            local Merlin3 = {}

            for _, v in pairs(game:GetService("Workspace").Unit:GetChildren()) do
                if v.Name == 'Merlin' and v.Owner.Value == me then
                    table.insert(Merlin1, v)
                end
            end

            if #Merlin1 == 2 then
                while true do
                    remote:FireServer('UseSpecialMove', Merlin1[1])
                    wait(30.8)
                    if not _G.AutoMerlin then
                        break
                    end
                    remote:FireServer('UseSpecialMove', Merlin1[2])
                    wait(30.8)
                    if not _G.AutoMerlin then
                        break
                    end
                end

            elseif #Merlin1 == 4 then
                for i = 1, 2 do
                    table.insert(Merlin2, Merlin1[1])
                    table.remove(Merlin1, 1)
                end
                for i = 1, 2 do
                    table.insert(Merlin3, Merlin1[1])
                    table.remove(Merlin1, 1)
                end
                while true do
                    remote:FireServer('UseSpecialMove', Merlin2[1])
                    wait(1)
                    remote:FireServer('UseSpecialMove', Merlin3[1])
                    wait(29.8)
                    if not _G.AutoMerlin then
                        break
                    end
                    remote:FireServer('UseSpecialMove', Merlin2[2])
                    wait(1)
                    remote:FireServer('UseSpecialMove', Merlin3[2])
                    wait(29.8)
                    if not _G.AutoMerlin then
                        break
                    end
                end

            elseif #Merlin1 > 2 and #Merlin1 < 4 then
                repeat
                    wait(1)
                    table.remove(Merlin1, 1)
                until #Merlin1 == 2
                while true do
                    remote:FireServer('UseSpecialMove', Merlin1[1])
                    wait(30.8)
                    if not _G.AutoMerlin then
                        break
                    end
                    remote:FireServer('UseSpecialMove', Merlin1[2])
                    wait(30.8)
                    if not _G.AutoMerlin then
                        break
                    end
                end
            end
            if not _G.AutoMerlin then
                break
            end
            wait(2)
        end
    end)
end

function ErwinBuffX2()
    spawn(function()
        while _G.AutoErwinX2 == true do
            local me = game.Players.LocalPlayer
            local remote = game.ReplicatedStorage.Remotes.Input
            local Erwin1 = {}
            local Erwin2 = {}
            local Erwin3 = {}

            for _, v in pairs(game:GetService("Workspace").Unit:GetChildren()) do
                if v.Name == 'Erwin' and v.Owner.Value == me then
                    table.insert(Erwin1, v)
                end
            end

            if #Erwin1 == 4 then
                while true do
                    remote:FireServer('UseSpecialMove', Erwin1[1])
                    wait(7.7)
                    if not _G.AutoErwinX2 then
                        break
                    end
                    remote:FireServer('UseSpecialMove', Erwin1[3])
                    wait(7.7)
                    if not _G.AutoErwinX2 then
                        break
                    end
                    remote:FireServer('UseSpecialMove', Erwin1[2])
                    wait(7.7)
                    if not _G.AutoErwinX2 then
                        break
                    end
                    remote:FireServer('UseSpecialMove', Erwin1[4])
                    wait(7.7)
                    if not _G.AutoErwinX2 then
                        break
                    end
                end
            elseif #Erwin1 == 8 then
                for i = 1, 4 do
                    table.insert(Erwin2, Erwin1[1])
                    table.remove(Erwin1, 1)
                end
                for i = 1, 4 do
                    table.insert(Erwin3, Erwin1[1])
                    table.remove(Erwin1, 1)
                end
                while true do
                    remote:FireServer('UseSpecialMove', Erwin2[1])
                    wait(1)
                    remote:FireServer('UseSpecialMove', Erwin3[1])
                    wait(14.4)
                    if not _G.AutoErwinX2 then
                        break
                    end
                    remote:FireServer('UseSpecialMove', Erwin2[3])
                    wait(1)
                    remote:FireServer('UseSpecialMove', Erwin3[3])
                    wait(6.7)
                    if not _G.AutoErwinX2 then
                        break
                    end
                    remote:FireServer('UseSpecialMove', Erwin2[2])
                    wait(1)
                    remote:FireServer('UseSpecialMove', Erwin3[2])
                    wait(6.7)
                    if not _G.AutoErwinX2 then
                        break
                    end
                    remote:FireServer('UseSpecialMove', Erwin2[4])
                    wait(1)
                    remote:FireServer('UseSpecialMove', Erwin3[4])
                    wait(6.7)
                    if not _G.AutoErwinX2 then
                        break
                    end
                end
            elseif #Erwin1 > 4 and #Erwin1 < 8 then
                repeat
                    wait(1)
                    table.remove(Erwin1, 1)
                until #Erwin1 == 4
                while true do
                    remote:FireServer('UseSpecialMove', Erwin1[1])
                    wait(7.7)
                    if not _G.AutoErwinX2 then
                        break
                    end
                    remote:FireServer('UseSpecialMove', Erwin1[3])
                    wait(7.7)
                    if not _G.AutoErwinX2 then
                        break
                    end
                    remote:FireServer('UseSpecialMove', Erwin1[2])
                    wait(7.7)
                    if not _G.AutoErwinX2 then
                        break
                    end
                    remote:FireServer('UseSpecialMove', Erwin1[4])
                    wait(7.7)
                    if not _G.AutoErwinX2 then
                        break
                    end
                end
            end
            if not _G.AutoErwinX2 then
                break
            end
            wait(2)
        end
    end)
end

function MerlinBuffX2()
    spawn(function()
        while _G.AutoMerlinX2 == true do

            local Merlin1 = {}
            local Merlin2 = {}
            local Merlin3 = {}

            for _, v in pairs(game:GetService("Workspace").Unit:GetChildren()) do
                if v.Name == 'Merlin' and v.Owner.Value == me then
                    table.insert(Merlin1, v)
                end
            end

            if #Merlin1 == 2 then
                while true do
                    remote:FireServer('UseSpecialMove', Merlin1[1])
                    wait(15.4)
                    if not _G.AutoMerlinX2 then
                        break
                    end
                    remote:FireServer('UseSpecialMove', Merlin1[2])
                    wait(15.4)
                    if not _G.AutoMerlinX2 then
                        break
                    end
                end

            elseif #Merlin1 == 4 then
                for i = 1, 2 do
                    table.insert(Merlin2, Merlin1[1])
                    table.remove(Merlin1, 1)
                end
                for i = 1, 2 do
                    table.insert(Merlin3, Merlin1[1])
                    table.remove(Merlin1, 1)
                end
                while true do
                    remote:FireServer('UseSpecialMove', Merlin2[1])
                    wait(1)
                    remote:FireServer('UseSpecialMove', Merlin3[1])
                    wait(14.4)
                    if not _G.AutoMerlinX2 then
                        break
                    end
                    remote:FireServer('UseSpecialMove', Merlin2[2])
                    wait(1)
                    remote:FireServer('UseSpecialMove', Merlin3[2])
                    wait(14.4)
                    if not _G.AutoMerlinX2 then
                        break
                    end
                end

            elseif #Merlin1 > 2 and #Merlin1 < 4 then
                repeat
                    wait(1)
                    table.remove(Merlin1, 1)
                until #Merlin1 == 2
                while true do
                    remote:FireServer('UseSpecialMove', Merlin1[1])
                    wait(15.4)
                    if not _G.AutoMerlinX2 then
                        break
                    end
                    remote:FireServer('UseSpecialMove', Merlin1[2])
                    wait(15.4)
                    if not _G.AutoMerlinX2 then
                        break
                    end
                end
            end
            if not _G.AutoMerlinX2 then
                break
            end
            wait(2)
        end
    end)
end
