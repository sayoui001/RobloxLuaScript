repeat task.wait() until game:IsLoaded()
repeat task.wait() until game:GetService("Workspace"):WaitForChild("_waves_started").Value
repeat task.wait() until game:GetService("Workspace"):FindFirstChild("_UNITS")

getgenv().AutoBuff = true

local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")
local workspaceUnits = game:GetService("Workspace")._UNITS
local me = players.LocalPlayer
local MyName = me.Name

local function useBuff(unit)
    local success, err = pcall(function()
        replicatedStorage.endpoints.client_to_server.use_active_attack:InvokeServer(unit)
    end)
    if not success then
        warn("Error in useBuff: " .. err)
        return false
    end
    return true
end

while getgenv().AutoBuff do
    local myBuffUnits = {}

    local success, err = pcall(function()
        for _, unit in pairs(workspaceUnits:GetChildren()) do
            local stats = unit:FindFirstChild("_stats")
            if stats and stats.player and stats.player.Value == me and 
               (unit.Name:match("^erwin") or unit.Name:match("^leafa") or unit.Name:match("^wendy")) then
                table.insert(myBuffUnits, unit)
            end
        end
    end)

    if not success then
        warn("Error while processing units: " .. err)
    end

    if #myBuffUnits == 4 then
        local nextBuff = 1
        local buffCooldown = myBuffUnits[1]._stats.active_attack_cooldown.Value
        local buffTime = (15 * (buffCooldown / 60)) + 0.05

        while getgenv().AutoBuff do
            local success = useBuff(myBuffUnits[nextBuff])
            if not success then
                warn("Breaking loop due to error in useBuff")
                break 
            end

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