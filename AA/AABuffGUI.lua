repeat task.wait() until game:IsLoaded()
repeat task.wait() until game:GetService("Workspace"):WaitForChild("_waves_started").Value
repeat task.wait() until game:GetService("Workspace"):FindFirstChild("_UNITS")

getgenv().AutoBuff = true

local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")
local workspaceUnits = game:GetService("Workspace")._UNITS
local me = players.LocalPlayer

-- GUI section
local Material = loadstring(game:HttpGet("https://raw.githubusercontent.com/Kinlei/MaterialLua/master/Module.lua"))()

local MainUI = Material.Load({
    Title = "AA Auto Buff",
    Style = 1,
    SizeX = 200,
    SizeY = 185,
    Theme = "Dark"
})

local BuffTab = MainUI.New({ Title = " Buff" })
local MoreTab = MainUI.New({ Title = " More" })
local CreditTab = MainUI.New({ Title = " Info" })

local function toggleBuff(unitType, callback)
    return BuffTab.Toggle({
        Text = "  " .. unitType .. " Buff",
        Callback = callback,
        Enabled = false
    })
end

local ErwainMain = toggleBuff("Erwin", function(Value)
    getgenv().AutoErwin = Value
    if Value then ErwinBuff("erwin") end
end)

local WendyMain = toggleBuff("Wendy", function(Value)
    getgenv().AutoWendy = Value
    if Value then WendyBuff("wendy") end
end)

local LeafaMain = toggleBuff("Leafa", function(Value)
    getgenv().AutoLeafa = Value
    if Value then LeafaBuff("leafa") end
end)

MoreTab.Button({ Text = " SOON", Callback = function() end })
CreditTab.Button({ Text = " Discord : xluc1f3rx", Callback = function() end })
-- Function section
function useBuff(unit)
    replicatedStorage.endpoints.client_to_server.use_active_attack:InvokeServer(unit)
end
-- General Buff Function
function generalBuff(unitType)
    spawn(function()
        while getgenv().AutoBuff do
            
            local myBuffUnits = {}

            for _, unit in pairs(workspaceUnits:GetChildren()) do
                local stats = unit:FindFirstChild("_stats")
                if stats and stats.player.Value == me and unit.Name:match("^" .. unitType) then
                    table.insert(myBuffUnits, unit)
                end
            end

            if #myBuffUnits == 4 then
                local nextBuff = 1
                local buffCooldown = myBuffUnits[1]._stats.active_attack_cooldown.Value
                local buffTime = (15 * (buffCooldown / 60)) + 0.05

                while getgenv().AutoBuff do
                    
                    useBuff(myBuffUnits[nextBuff])
                    nextBuff = nextBuff % 4 + 1

                    if buffCooldown <= 60 then
                        task.wait(15.25)
                    else
                        task.wait(buffTime)
                    end
                end
            else
                task.wait(1)
            end
        end
    end)
end
-- Buffing Functions for specific units
function ErwinBuff() generalBuff("erwin") end
function WendyBuff() generalBuff("wendy") end
function LeafaBuff() generalBuff("leafa") end