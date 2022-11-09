repeat 
    wait() 
until game:IsLoaded() 

_G.Check = false
_G.AutoErwin = false
_G.AutoMerlin = false
_G.AutoBrook6 = false
_G.CurrentSpeed = 1

local Material = loadstring(game:HttpGet("https://raw.githubusercontent.com/Kinlei/MaterialLua/master/Module.lua"))()
local me = game.Players.LocalPlayer
local remote = game.ReplicatedStorage.Remotes.Input

local MainUI = Material.Load({
    Title = "ASTD Utilities",
    Style = 1,
    SizeX = 200,
    SizeY = 185,
    Theme = "Dark"
})

local BuffTab = MainUI.New({
    Title = " Buff"
})


local MoreTab = MainUI.New({
    Title = " More"
})

local CreditTab = MainUI.New({
    Title = " Info"
})

local ErwainMain = BuffTab.Toggle({
    Text = "  Erwin Buff",
    Callback = function(Value)
        _G.Check = Value
        _G.AutoErwin = Value
        if Value then
            CheckSpeed()
            ErwinBuff()
        end
    end,
    Enabled = false
})

local MerlinMain = BuffTab.Toggle({
    Text = "  Merlin Buff",
    Callback = function(Value)
        _G.Check = Value
        _G.AutoMerlin = Value
        if Value then
            CheckSpeed()
            MerlinBuff()
        end
    end,
    Enabled = false
})

local Brook6Main = BuffTab.Toggle({
    Text = "  Brook6 Buff",
    Callback = function(Value)
        _G.Check = Value
        _G.AutoBrook6 = Value
        if Value then
            CheckSpeed()
            Brook6Buff()
        end
    end,
    Enabled = false
})

local MoreMain = MoreTab.Button({
    Text = " SOON",
    Callback = function()
    end
})

local CreditMain = CreditTab.Button({
    Text = " By : xLUC1F3Rx#0491",
    Callback = function()
    end
})

function CheckSpeed()
    spawn(function()
        while _G.Check == true do
            if not _G.Check then
                break
            end
            if game:GetService("Players").LocalPlayer.PlayerGui.HUD.FastForward.TextLabel.Text == ("1X") then
                _G.CurrentSpeed = 1
            elseif game:GetService("Players").LocalPlayer.PlayerGui.HUD.FastForward.TextLabel.Text == ("2X") then
                _G.CurrentSpeed = 2
            end
            wait(1)    
        end
    end)
end

function ErwinBuff()
    spawn(function()

        local Erwin1 = {}
        local Erwin2 = {}
        local Erwin3 = {}

        for _, v in pairs(game:GetService("Workspace").Unit:GetChildren()) do
            if v.Name == 'Erwin' and v.Owner.Value == me then
                table.insert(Erwin1, v)
            end
        end

        function UseErwin1(a)
            if Erwin1[a].SpecialMove["Special_Enabled2"].Value == true then
                repeat
                    wait(1)
                    if not _G.AutoErwin then
                        break
                    end
                until Erwin1[a].SpecialMove["Special_Enabled2"].Value == false
                repeat
                    remote:FireServer('UseSpecialMove', Erwin1[a])
                    wait(0.1)
                until Erwin1[a].SpecialMove["Special_Enabled2"].Value == true
            elseif Erwin1[a].SpecialMove["Special_Enabled2"].Value == false then
                repeat
                    remote:FireServer('UseSpecialMove', Erwin1[a])
                    wait(0.1)
                until Erwin1[a].SpecialMove["Special_Enabled2"].Value == true
            end
        end

        function UseErwin2(a)
            if Erwin2[a].SpecialMove["Special_Enabled2"].Value == true then
                repeat
                    wait(1)
                    if not _G.AutoErwin then
                        break
                    end
                until Erwin2[a].SpecialMove["Special_Enabled2"].Value == false
                repeat
                    remote:FireServer('UseSpecialMove', Erwin2[a])
                    wait(0.1)
                until Erwin2[a].SpecialMove["Special_Enabled2"].Value == true
            elseif Erwin2[a].SpecialMove["Special_Enabled2"].Value == false then
                repeat
                    remote:FireServer('UseSpecialMove', Erwin2[a])
                    wait(0.1)
                until Erwin2[a].SpecialMove["Special_Enabled2"].Value == true
            end
        end

        function UseErwin3(a)
            if Erwin3[a].SpecialMove["Special_Enabled2"].Value == true then
                repeat
                    wait(1)
                    if not _G.AutoErwin then
                        break
                    end
                until Erwin3[a].SpecialMove["Special_Enabled2"].Value == false
                repeat
                    remote:FireServer('UseSpecialMove', Erwin3[a])
                    wait(0.1)
                until Erwin3[a].SpecialMove["Special_Enabled2"].Value == true
            elseif Erwin3[a].SpecialMove["Special_Enabled2"].Value == false then
                repeat
                    remote:FireServer('UseSpecialMove', Erwin3[a])
                    wait(0.1)
                until Erwin3[a].SpecialMove["Special_Enabled2"].Value == true
            end
        end

        while _G.AutoErwin == true do
            if #Erwin1 == 4 then
                local NextErwin1 = 1
                while true do
                    if NextErwin1 == 1 then
                        UseErwin1(1)
                        NextErwin1 = 3 
                    elseif NextErwin1 == 2 then
                        UseErwin1(2)
                        NextErwin1 = 4 
                    elseif NextErwin1 == 3 then
                        UseErwin1(3)
                        NextErwin1 = 2 
                    elseif NextErwin1 == 4 then  
                        UseErwin1(4)
                        NextErwin1 = 1 
                    end
                    if _G.CurrentSpeed == 1 then 
                        wait(15.5)
                    elseif _G.CurrentSpeed == 2 then
                        wait(8)
                    end
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
                local NextErwin2 = 1
                local NextErwin3 = 1
                while true do
                    if NextErwin2 == 1 then
                        UseErwin2(1)
                        NextErwin2 = 3 
                    elseif NextErwin2 == 2 then
                        UseErwin2(2)
                        NextErwin2 = 4 
                    elseif NextErwin2 == 3 then
                        UseErwin2(3)
                        NextErwin2 = 2 
                    elseif NextErwin2 == 4 then  
                        UseErwin2(4)
                        NextErwin2 = 1 
                    end
                    wait(1)
                    if not _G.AutoErwin then
                        break
                    end
                    if NextErwin3 == 1 then
                        UseErwin3(1)
                        NextErwin3 = 3 
                    elseif NextErwin3 == 2 then
                        UseErwin3(2)
                        NextErwin3 = 4 
                    elseif NextErwin3 == 3 then
                        UseErwin3(3)
                        NextErwin3 = 2 
                    elseif NextErwin3 == 4 then  
                        UseErwin3(4)
                        NextErwin3 = 1 
                    end
                    if _G.CurrentSpeed == 1 then 
                        wait(14.5)
                    elseif _G.CurrentSpeed == 2 then
                        wait(7)
                    end
                    if not _G.AutoErwin then
                        break
                    end
                end
            elseif #Erwin1 > 4 and #Erwin1 < 8 then
                repeat
                    wait(1)
                    table.remove(Erwin1, 1)
                until #Erwin1 == 4
                local NextErwin1 = 1
                while true do
                    if NextErwin1 == 1 then
                        UseErwin1(1)
                        NextErwin1 = 3 
                    elseif NextErwin1 == 2 then
                        UseErwin1(2)
                        NextErwin1 = 4 
                    elseif NextErwin1 == 3 then
                        UseErwin1(3)
                        NextErwin1 = 2 
                    elseif NextErwin1 == 4 then  
                        UseErwin1(4)
                        NextErwin1 = 1 
                    end
                    if _G.CurrentSpeed == 1 then 
                        wait(15.5)
                    elseif _G.CurrentSpeed == 2 then
                        wait(8)
                    end
                    if not _G.AutoErwin then
                        break
                    end
                end
            end
            if not _G.AutoErwin then
                break
            end
            wait(3)
        end
    end)
end

function Brook6Buff()
    spawn(function()

        local Brook61 = {}
        local Brook62 = {}
        local Brook63 = {}

        for _, v in pairs(game:GetService("Workspace").Unit:GetChildren()) do
            if v.Name == 'Brook6' and v.Owner.Value == me then
                table.insert(Brook61, v)
            end
        end

        function UseBrook61(a)
            if Brook61[a].SpecialMove["Special_Enabled2"].Value == true then
                repeat
                    wait(1)
                    if not _G.AutoBrook6 then
                        break
                    end
                until Brook61[a].SpecialMove["Special_Enabled2"].Value == false
                repeat
                    remote:FireServer('UseSpecialMove', Brook61[a])
                    wait(0.1)
                until Brook61[a].SpecialMove["Special_Enabled2"].Value == true
            elseif Brook61[a].SpecialMove["Special_Enabled2"].Value == false then
                repeat
                    remote:FireServer('UseSpecialMove', Brook61[a])
                    wait(0.1)
                until Brook61[a].SpecialMove["Special_Enabled2"].Value == true
            end
        end

        function UseBrook62(a)
            if Brook62[a].SpecialMove["Special_Enabled2"].Value == true then
                repeat
                    wait(1)
                    if not _G.AutoBrook6 then
                        break
                    end
                until Brook62[a].SpecialMove["Special_Enabled2"].Value == false
                repeat
                    remote:FireServer('UseSpecialMove', Brook62[a])
                    wait(0.1)
                until Brook62[a].SpecialMove["Special_Enabled2"].Value == true
            elseif Brook62[a].SpecialMove["Special_Enabled2"].Value == false then
                repeat
                    remote:FireServer('UseSpecialMove', Brook62[a])
                    wait(0.1)
                until Brook62[a].SpecialMove["Special_Enabled2"].Value == true
            end
        end

        function UseBrook63(a)
            if Brook63[a].SpecialMove["Special_Enabled2"].Value == true then
                repeat
                    wait(1)
                    if not _G.AutoBrook6 then
                        break
                    end
                until Brook63[a].SpecialMove["Special_Enabled2"].Value == false
                repeat
                    remote:FireServer('UseSpecialMove', Brook63[a])
                    wait(0.1)
                until Brook63[a].SpecialMove["Special_Enabled2"].Value == true
            elseif Brook63[a].SpecialMove["Special_Enabled2"].Value == false then
                repeat
                    remote:FireServer('UseSpecialMove', Brook63[a])
                    wait(0.1)
                until Brook63[a].SpecialMove["Special_Enabled2"].Value == true
            end
        end

        while _G.AutoBrook6 == true do
            if #Brook61 == 4 then
                local NextBrook61 = 1
                while true do
                    if NextBrook61 == 1 then
                        UseBrook61(1)
                        NextBrook61 = 3 
                    elseif NextBrook61 == 2 then
                        UseBrook61(2)
                        NextBrook61 = 4 
                    elseif NextBrook61 == 3 then
                        UseBrook61(3)
                        NextBrook61 = 2 
                    elseif NextBrook61 == 4 then  
                        UseBrook61(4)
                        NextBrook61 = 1 
                    end
                    if _G.CurrentSpeed == 1 then 
                        wait(15.5)
                    elseif _G.CurrentSpeed == 2 then
                        wait(8)
                    end
                    if not _G.AutoBrook6 then
                        break
                    end
                end
            elseif #Brook61 == 8 then
                for i = 1, 4 do
                    table.insert(Brook62, Brook61[1])
                    table.remove(Brook61, 1)
                end
                for i = 1, 4 do
                    table.insert(Brook63, Brook61[1])
                    table.remove(Brook61, 1)
                end
                local NextBrook62 = 1
                local NextBrook63 = 1
                while true do
                    if NextBrook62 == 1 then
                        UseBrook62(1)
                        NextBrook62 = 3 
                    elseif NextBrook62 == 2 then
                        UseBrook62(2)
                        NextBrook62 = 4 
                    elseif NextBrook62 == 3 then
                        UseBrook62(3)
                        NextBrook62 = 2 
                    elseif NextBrook62 == 4 then  
                        UseBrook62(4)
                        NextBrook62 = 1 
                    end
                    wait(1)
                    if not _G.AutoBrook6 then
                        break
                    end
                    if NextBrook63 == 1 then
                        UseBrook63(1)
                        NextBrook63 = 3 
                    elseif NextBrook63 == 2 then
                        UseBrook63(2)
                        NextBrook63 = 4 
                    elseif NextBrook63 == 3 then
                        UseBrook63(3)
                        NextBrook63 = 2 
                    elseif NextBrook63 == 4 then  
                        UseBrook63(4)
                        NextBrook63 = 1 
                    end
                    if _G.CurrentSpeed == 1 then 
                        wait(14.5)
                    elseif _G.CurrentSpeed == 2 then
                        wait(7)
                    end
                    if not _G.AutoBrook6 then
                        break
                    end
                end
            elseif #Brook61 > 4 and #Brook61 < 8 then
                repeat
                    wait(1)
                    table.remove(Brook61, 1)
                until #Brook61 == 4
                local NextBrook61 = 1
                while true do
                    if NextBrook61 == 1 then
                        UseBrook61(1)
                        NextBrook61 = 3 
                    elseif NextBrook61 == 2 then
                        UseBrook61(2)
                        NextBrook61 = 4 
                    elseif NextBrook61 == 3 then
                        UseBrook61(3)
                        NextBrook61 = 2 
                    elseif NextBrook61 == 4 then  
                        UseBrook61(4)
                        NextBrook61 = 1 
                    end
                    if _G.CurrentSpeed == 1 then 
                        wait(15.5)
                    elseif _G.CurrentSpeed == 2 then
                        wait(8)
                    end
                    if not _G.AutoBrook6 then
                        break
                    end
                end
            end
            if not _G.AutoBrook6 then
                break
            end
            wait(3)
        end
    end)
end

function MerlinBuff()
    spawn(function()
        local Merlin1 = {}
        local Merlin2 = {}
        local Merlin3 = {}

        for _, v in pairs(game:GetService("Workspace").Unit:GetChildren()) do
            if v.Name == 'Merlin' and v.Owner.Value == me then
                table.insert(Merlin1, v)
            end
        end

        function UseMerlin1(a)
            if Merlin1[a].SpecialMove["Special_Enabled2"].Value == true then
                repeat
                    wait(1)
                    if not _G.AutoMerlin then
                        break
                    end
                until Merlin1[a].SpecialMove["Special_Enabled2"].Value == false
                repeat
                    remote:FireServer('UseSpecialMove', Merlin1[a])
                    wait(0.1)
                until Merlin1[a].SpecialMove["Special_Enabled2"].Value == true
            elseif Merlin1[a].SpecialMove["Special_Enabled2"].Value == false then
                repeat
                    remote:FireServer('UseSpecialMove', Merlin1[a])
                    wait(0.1)
                until Merlin1[a].SpecialMove["Special_Enabled2"].Value == true
            end
        end

        function UseMerlin2(a)
            if Merlin2[a].SpecialMove["Special_Enabled2"].Value == true then
                repeat
                    wait(1)
                    if not _G.AutoMerlin then
                        break
                    end
                until Merlin2[a].SpecialMove["Special_Enabled2"].Value == false
                repeat
                    remote:FireServer('UseSpecialMove', Merlin2[a])
                    wait(0.1)
                until Merlin2[a].SpecialMove["Special_Enabled2"].Value == true
            elseif Merlin2[a].SpecialMove["Special_Enabled2"].Value == false then
                repeat
                    remote:FireServer('UseSpecialMove', Merlin2[a])
                    wait(0.1)
                until Merlin2[a].SpecialMove["Special_Enabled2"].Value == true
            end
        end

        function UseMerlin3(a)
            if Merlin3[a].SpecialMove["Special_Enabled2"].Value == true then
                repeat
                    wait(1)
                    if not _G.AutoMerlin then
                        break
                    end
                until Merlin3[a].SpecialMove["Special_Enabled2"].Value == false
                repeat
                    remote:FireServer('UseSpecialMove', Merlin3[a])
                    wait(0.1)
                until Merlin3[a].SpecialMove["Special_Enabled2"].Value == true
            elseif Merlin3[a].SpecialMove["Special_Enabled2"].Value == false then
                repeat
                    remote:FireServer('UseSpecialMove', Merlin3[a])
                    wait(0.1)
                until Merlin3[a].SpecialMove["Special_Enabled2"].Value == true
            end
        end

        while _G.AutoMerlin == true do
            if #Merlin1 == 2 then
                local NextMerlin1 = 1
                while true do
                    if NextMerlin1 == 1 then
                        UseMerlin1(1)
                        NextMerlin1 = 2 
                    elseif NextMerlin1 == 2 then
                        UseMerlin1(2)
                        NextMerlin1 = 1 
                    end
                    if _G.CurrentSpeed == 1 then 
                        wait(30.5)
                    elseif _G.CurrentSpeed == 2 then
                        wait(15.5)
                    end
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
                local NextMerlin2 = 1
                local NextMerlin3 = 1
                while true do
                    if NextMerlin2 == 1 then
                        UseMerlin2(1)
                        NextMerlin2 = 2 
                    elseif NextMerlin2 == 2 then
                        UseMerlin2(2)
                        NextMerlin2 = 1 
                    end
                    wait(1)
                    if NextMerlin3 == 1 then
                        UseMerlin3(1)
                        NextMerlin3 = 2 
                    elseif NextMerlin3 == 2 then
                        UseMerlin3(2)
                        NextMerlin3 = 1 
                    end
                    if _G.CurrentSpeed == 1 then 
                        wait(30.5)
                    elseif _G.CurrentSpeed == 2 then
                        wait(15.5)
                    end
                    if not _G.AutoMerlin then
                        break
                    end
                end
            elseif #Merlin1 > 2 and #Merlin1 < 4 then
                repeat
                    wait(1)
                    table.remove(Merlin1, 1)
                until #Merlin1 == 2
                local NextMerlin1 = 1
                while true do
                    if NextMerlin1 == 1 then
                        UseMerlin1(1)
                        NextMerlin1 = 2 
                    elseif NextMerlin1 == 2 then
                        UseMerlin1(2)
                        NextMerlin1 = 1 
                    end
                    if _G.CurrentSpeed == 1 then 
                        wait(30.5)
                    elseif _G.CurrentSpeed == 2 then
                        wait(15.5)
                    end
                    if not _G.AutoMerlin then
                        break
                    end
                end
            end
            if not _G.AutoMerlin then
                break
            end
            wait(3)
        end
    end)
end
