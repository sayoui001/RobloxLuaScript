-- Anime Adventures Auto Buff V2
-- Work 01: independent cancellable buff workers
-- Work 02: dynamic discovery and validation of owned units
-- Timing is based on the original AA script and requires in-game verification.

repeat task.wait() until game:IsLoaded()

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local player = Players.LocalPlayer

local env = getgenv()
if env.AABuffV2 and type(env.AABuffV2.StopAll) == "function" then
    env.AABuffV2.StopAll()
end

local controller = { active = true, workers = {} }
env.AABuffV2 = controller

local CONFIG = {
    erwin = { label = "Erwin", requiredCount = 4 },
    wendy = { label = "Wendy", requiredCount = 4 },
    leafa = { label = "Leafa", requiredCount = 4 },
}
local TYPES = { "erwin", "wendy", "leafa" }
local POLL_SECONDS = 0.5

for _, unitType in ipairs(TYPES) do
    controller.workers[unitType] = { enabled = false, generation = 0, running = false }
end

local function waitUntilStopped(seconds, shouldRun)
    local remaining = seconds
    while remaining > 0 and shouldRun() do
        local delay = math.min(remaining, POLL_SECONDS)
        task.wait(delay)
        remaining = remaining - delay
    end
    return shouldRun()
end

local function ownedBuffUnits(unitType)
    local result = {}
    local folder = Workspace:FindFirstChild("_UNITS")
    if not folder then
        return result
    end

    for _, unit in ipairs(folder:GetChildren()) do
        local stats = unit:FindFirstChild("_stats")
        local owner = stats and stats:FindFirstChild("player")
        if owner and owner.Value == player and unit.Name:lower():sub(1, #unitType) == unitType then
            table.insert(result, unit)
        end
    end

    -- Track the last used instance in the worker; ordering here follows the current folder snapshot.
    return result
end

local function validUnit(unit, unitType)
    local folder = Workspace:FindFirstChild("_UNITS")
    if not folder or not unit or unit.Parent ~= folder then
        return false
    end
    local stats = unit:FindFirstChild("_stats")
    local owner = stats and stats:FindFirstChild("player")
    return owner ~= nil and owner.Value == player
        and unit.Name:lower():sub(1, #unitType) == unitType
end

local function getCooldown(unit)
    local stats = unit:FindFirstChild("_stats")
    local cooldown = stats and stats:FindFirstChild("active_attack_cooldown")
    if not cooldown or type(cooldown.Value) ~= "number" or cooldown.Value <= 0 then
        return nil
    end
    return cooldown.Value
end

local function getRemote()
    local endpoints = ReplicatedStorage:FindFirstChild("endpoints")
    local c2s = endpoints and endpoints:FindFirstChild("client_to_server")
    local remote = c2s and c2s:FindFirstChild("use_active_attack")
    if remote and remote:IsA("RemoteFunction") then
        return remote
    end
    return nil
end

local function startWorker(unitType)
    local worker = controller.workers[unitType]
    worker.generation = worker.generation + 1
    local generation = worker.generation
    worker.enabled = true
    worker.running = true

    local function shouldRun()
        return controller.active and worker.enabled
            and worker.generation == generation and env.AABuffV2 == controller
    end

    task.spawn(function()
        local lastUnit = nil
        while shouldRun() do
            local units = ownedBuffUnits(unitType)
            if #units ~= CONFIG[unitType].requiredCount then
                lastUnit = nil
                waitUntilStopped(1, shouldRun)
            else
                local nextIndex = 1
                if lastUnit then
                    for i, unit in ipairs(units) do
                        if unit == lastUnit then
                            nextIndex = (i % #units) + 1
                            break
                        end
                    end
                end

                local unit = units[nextIndex]
                local cooldown = validUnit(unit, unitType) and getCooldown(unit)
                local remote = getRemote()

                if cooldown and remote and shouldRun() then
                    -- Preserve the previous script's 4-unit interval formula.
                    local interval = cooldown <= 60 and 15.25
                        or (15 * (cooldown / 60)) + 0.05
                    local ok, err = pcall(function()
                        remote:InvokeServer(unit)
                    end)
                    if not ok then
                        warn("[AABuffV2] " .. unitType .. " invoke error: " .. tostring(err))
                        waitUntilStopped(1, shouldRun)
                    else
                        lastUnit = unit
                        waitUntilStopped(interval, shouldRun)
                    end
                else
                    waitUntilStopped(1, shouldRun)
                end
            end
        end
        if worker.generation == generation then
            worker.running = false
        end
    end)
end

function controller.SetEnabled(unitType, value)
    local worker = controller.workers[unitType]
    if not controller.active or not worker then return end
    local enabled = value == true
    if worker.enabled == enabled then return end
    if enabled then
        startWorker(unitType)
    else
        worker.enabled = false
        worker.generation = worker.generation + 1
    end
end

function controller.StopAll()
    controller.active = false
    for _, worker in pairs(controller.workers) do
        worker.enabled = false
        worker.generation = worker.generation + 1
    end
end

-- The GUI is loaded last, so failure to fetch it doesn't start hidden workers.
local ok, Material = pcall(function()
    return loadstring(game:HttpGet("https://raw.githubusercontent.com/Kinlei/MaterialLua/master/Module.lua"))()
end)
if not ok or not Material then
    warn("[AABuffV2] Could not load GUI: " .. tostring(Material))
    controller.StopAll()
    return
end

local MainUI = Material.Load({
    Title = "AA Auto Buff V2",
    Style = 1,
    SizeX = 210,
    SizeY = 185,
    Theme = "Dark"
})
local BuffTab = MainUI.New({ Title = " Buff" })
local InfoTab = MainUI.New({ Title = " Info" })

for _, unitType in ipairs(TYPES) do
    local key = unitType
    BuffTab.Toggle({
        Text = " " .. CONFIG[key].label .. " Buff",
        Enabled = false,
        Callback = function(value)
            controller.SetEnabled(key, value)
        end
    })
end

InfoTab.Button({
    Text = "Stop All Workers",
    Callback = function()
        controller.StopAll()
        warn("[AABuffV2] All workers stopped. Re-execute to restart.")
    end
})
