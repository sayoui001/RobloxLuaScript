-- AA Auto Buff V3 | fixed cooldown rotation + stable unit roster
-- Requires executor APIs getgenv/loadstring/game:HttpGet. Test in game before relying on it.
repeat task.wait() until game:IsLoaded()

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local player = Players.LocalPlayer
local env = getgenv()
local config = type(env.AABuffConfig) == "table" and env.AABuffConfig or {}
local autoStart = {
    erwin = config.erwin == true,
    wendy = config.wendy == true,
    leafa = config.leafa == true,
}

-- Stop previous versions when switching scripts to avoid competing workers.
for _, key in ipairs({"AABuffV2", "AABuffV3"}) do
    local previous = env[key]
    if previous and type(previous.StopAll) == "function" then
        pcall(function() previous.StopAll() end)
    end
end

local TYPE_ORDER = {"erwin", "wendy", "leafa"}
local TYPE_CONFIG = {
    erwin = "Erwin",
    wendy = "Wendy",
    leafa = "Leafa",
}
local REQUIRED_UNITS = 4
local DELAY_MARGIN = 0.15
local SCAN_DELAY = 1
local RETRY_DELAY = 2
local WAIT_SLICE = 0.1

local controller = {active = true, workers = {}}
env.AABuffV3 = controller

local function pause(seconds, alive)
    local deadline = os.clock() + seconds
    while alive() do
        local remaining = deadline - os.clock()
        if remaining <= 0 then break end
        task.wait(math.min(WAIT_SLICE, remaining))
    end
    return alive()
end

local function unitFolder()
    return Workspace:FindFirstChild("_UNITS")
end

local function isOwnedUnit(unit, kind, folder)
    if not folder or not unit or unit.Parent ~= folder then return false end
    if unit.Name:lower():sub(1, #kind) ~= kind then return false end
    local stats = unit:FindFirstChild("_stats")
    local owner = stats and stats:FindFirstChild("player")
    return owner ~= nil and owner.Value == player
end

local function discover(kind)
    local folder = unitFolder()
    local discovered = {}
    if folder then
        for _, unit in ipairs(folder:GetChildren()) do
            if isOwnedUnit(unit, kind, folder) then
                table.insert(discovered, unit)
            end
        end
    end
    return discovered, folder
end

-- Retain surviving instances in their original order; add newly placed units at end.
local function reconcile(old, discovered)
    local present = {}
    for _, unit in ipairs(discovered) do present[unit] = true end

    local updated, retained = {}, {}
    for _, unit in ipairs(old) do
        if present[unit] then
            table.insert(updated, unit)
            retained[unit] = true
        end
    end
    for _, unit in ipairs(discovered) do
        if not retained[unit] then
            table.insert(updated, unit)
        end
    end

    local changed = #updated ~= #old
    if not changed then
        for i, unit in ipairs(updated) do
            if old[i] ~= unit then changed = true; break end
        end
    end
    return updated, changed
end

local function cooldownOf(unit)
    local stats = unit and unit:FindFirstChild("_stats")
    local cdObject = stats and stats:FindFirstChild("active_attack_cooldown")
    local cd = cdObject and cdObject.Value
    if type(cd) ~= "number" or cd ~= cd or cd <= 0 or cd == math.huge then
        return nil
    end
    return cd
end

local function remoteFunction()
    local endpoints = ReplicatedStorage:FindFirstChild("endpoints")
    local client = endpoints and endpoints:FindFirstChild("client_to_server")
    local remote = client and client:FindFirstChild("use_active_attack")
    return remote and remote:IsA("RemoteFunction") and remote or nil
end

for _, kind in ipairs(TYPE_ORDER) do
    controller.workers[kind] = {
        enabled = false, generation = 0, running = false,
        state = "DISABLED", unitCount = 0, nextIndex = 1,
        lastUse = nil, lastError = nil, cooldown = nil,
    }
end

local function start(kind)
    local worker = controller.workers[kind]
    worker.enabled = true
    worker.generation = worker.generation + 1
    local token = worker.generation
    worker.running = true
    worker.state = "WAITING_UNITS"

    local function alive()
        return controller.active and env.AABuffV3 == controller
            and worker.enabled and worker.generation == token
    end

    task.spawn(function()
        local ok, fatal = xpcall(function()
            local roster = {}
            local nextIndex = 1
            local nextAttemptAt = 0

            while alive() do
                local found, folder = discover(kind)
                local updated, changed = reconcile(roster, found)
                roster = updated
                worker.unitCount = #roster

                if changed then
                    -- New roster: start from first surviving unit, without an immediate
                    -- extra invoke if the preceding roster just used a special.
                    nextIndex = 1
                end

                if #roster ~= REQUIRED_UNITS then
                    worker.state = "WAITING_UNITS"
                    worker.cooldown = nil
                    pause(SCAN_DELAY, alive)
                else
                    -- A Curse may give units different fixed cooldowns. Use the maximum
                    -- to avoid rotating back to a slower unit before its cooldown ends.
                    local highestCooldown = 0
                    local valid = true
                    for _, unit in ipairs(roster) do
                        if not isOwnedUnit(unit, kind, folder) then
                            valid = false
                            break
                        end
                        local cd = cooldownOf(unit)
                        if not cd then valid = false; break end
                        highestCooldown = math.max(highestCooldown, cd)
                    end

                    if not valid then
                        worker.state = "WAITING_UNITS"
                        pause(SCAN_DELAY, alive)
                    else
                        worker.cooldown = highestCooldown
                        local interval = (highestCooldown / REQUIRED_UNITS) + DELAY_MARGIN
                        local remaining = nextAttemptAt - os.clock()
                        if remaining > 0 then
                            worker.state = "COOLDOWN"
                            pause(remaining, alive)
                        elseif alive() then
                            local selected = roster[nextIndex]
                            local currentFolder = unitFolder()
                            local remote = remoteFunction()
                            if not isOwnedUnit(selected, kind, currentFolder) or not remote then
                                worker.state = "WAITING_UNITS"
                                pause(SCAN_DELAY, alive)
                            else
                                worker.state = "BUFFING"
                                -- InvokeServer can yield. We cannot cancel the in-flight
                                -- request; its result is ignored if this worker was stopped.
                                local invokeOk, response = pcall(function()
                                    return remote:InvokeServer(selected)
                                end)
                                if not alive() then break end
                                if invokeOk then
                                    worker.lastUse = os.clock()
                                    worker.lastError = nil
                                    nextIndex = (nextIndex % REQUIRED_UNITS) + 1
                                    worker.nextIndex = nextIndex
                                    nextAttemptAt = worker.lastUse + interval
                                else
                                    worker.state = "ERROR"
                                    worker.lastError = tostring(response)
                                    warn("[AABuffV3][" .. kind .. "] " .. worker.lastError)
                                    -- No immediate retry: server may have applied the move
                                    -- despite a lost response.
                                    nextAttemptAt = os.clock() + math.max(RETRY_DELAY, interval)
                                    pause(RETRY_DELAY, alive)
                                end
                            end
                        end
                    end
                end
            end
        end, function(err) return tostring(err) end)

        if worker.generation == token then
            worker.running = false
            worker.enabled = false
            worker.state = ok and "DISABLED" or "ERROR"
            if not ok then
                worker.lastError = fatal
                warn("[AABuffV3][" .. kind .. "] worker crashed: " .. tostring(fatal))
            end
        end
    end)
end

function controller.SetEnabled(kind, enabled)
    local worker = controller.workers[kind]
    if not controller.active or not worker then return end
    enabled = enabled == true
    if worker.enabled == enabled then return end
    if enabled then
        start(kind)
    else
        worker.enabled = false
        worker.generation = worker.generation + 1
        worker.state = "DISABLED"
        worker.running = false
    end
end

function controller.StopAll()
    controller.active = false
    for _, worker in pairs(controller.workers) do
        worker.enabled = false
        worker.generation = worker.generation + 1
        worker.state = "DISABLED"
        worker.running = false
    end
end

-- Keep the familiar UI from V2. Status is available at getgenv().AABuffV3.workers.
local loaded, Material = pcall(function()
    return loadstring(game:HttpGet("https://raw.githubusercontent.com/Kinlei/MaterialLua/master/Module.lua"))()
end)
if not loaded or not Material then
    warn("[AABuffV3] GUI library failed: " .. tostring(Material))
    controller.StopAll()
    return
end

local made, uiError = pcall(function()
    local ui = Material.Load({
        Title = "AA Auto Buff V3", Style = 1,
        SizeX = 210, SizeY = 185, Theme = "Dark"
    })
    local buffs = ui.New({Title = " Buff"})
    local info = ui.New({Title = " Info"})

    for _, kind in ipairs(TYPE_ORDER) do
        local currentKind = kind
        buffs.Toggle({
            Text = " " .. TYPE_CONFIG[currentKind] .. " Buff",
            Enabled = autoStart[currentKind],
            Callback = function(value)
                controller.SetEnabled(currentKind, value)
            end
        })
    end

    info.Button({
        Text = " Stop All",
        Callback = function()
            controller.StopAll()
            warn("[AABuffV3] Stopped. Re-execute to restart.")
        end
    })
end)
if not made then
    controller.StopAll()
    warn("[AABuffV3] GUI setup failed: " .. tostring(uiError))
else
    for _, kind in ipairs(TYPE_ORDER) do
        if autoStart[kind] then
            controller.SetEnabled(kind, true)
        end
    end
end
