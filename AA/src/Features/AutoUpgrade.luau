-- AutoUpgrade module: original lexical scope retained.
return function()
-- Embedded Auto Upgrade (kept in its own lexical scope)
do
-- Anime Adventures Auto Upgrade U1: read-only scheduler preview
-- LIVE requests intentionally disabled until upgrade_unit_ingame arguments are verified.
repeat task.wait() until game:IsLoaded()
local Players=game:GetService("Players")
local player=Players.LocalPlayer
local W=game:GetService("Workspace")
local env=(type(getgenv)=="function" and getgenv()) or _G
if env.AAAutoUpgrade and env.AAAutoUpgrade.Destroy then env.AAAutoUpgrade:Destroy() end

local cfg={
    Enabled=false,
    Priority={1,2,3,4,5,6},
    Slots={false,false,false,false,true,false},
    TargetLevel={-1,-1,-1,-1,-1,-1}, -- -1: Max
    CostOverrides={}, -- optional: [slot]={[upgradeLevel]=exact NEXT upgrade cost}
    CostDiscounts={}, -- additive fractions, e.g. {0.10,0.20} = 30% reduction
    AllowLowerPriorityWhenUnaffordable=false,
    ReserveMoney=0,
    ScanInterval=1,
    Mode="PREVIEW", -- switch to LIVE explicitly
    VerifyTimeout=2,
    RequestDelay=0.5,
    MaxUpgradesPerRun=99,
}
local app={Config=cfg,LastPlan={},Running=false,Stopped=false,Uncertain=false,Requests=0,Status="Idle",LastUnit="-",LastCost=0,Verified=0}
env.AAAutoUpgrade=app
local function log(...) print("[AAAutoUpgrade]",...) end
local function equippedUuid(slot)
    local gui=player:FindFirstChild("PlayerGui")
    local sp=gui and gui:FindFirstChild("spawn_units")
    local ui=sp and sp:FindFirstChild(tostring(slot),true)
    return ui and ui:GetAttribute("_equipped_frame_unit_uuid")
end
local function resource()
    local st=player:FindFirstChild("_stats")
    local v=st and st:FindFirstChild("resource")
    return v and tonumber(v.Value)
end
local function getStat(st,name)
    local v=st and st:FindFirstChild(name)
    return v and v:IsA("ValueBase") and v.Value or nil
end
local unitData=nil
local okData,data=pcall(function()
    return require(game:GetService("ReplicatedStorage").src.Data.Units)
end)
if okData and type(data)=="table" then unitData=data end

local function effectiveCost(baseCost,discounts)
    if type(baseCost)~="number" or baseCost<0 then return nil end
    local root=W:FindFirstChild("_DATA")
    local modifiers=root and root:FindFirstChild("LevelModifiers")
    local scaleValue=modifiers and modifiers:FindFirstChild("player_cost_scale")
    local scale=scaleValue and tonumber(scaleValue.Value) or 1
    if not scale or scale~=scale then return nil end
    local reduction=0
    for _,v in ipairs(discounts or {}) do
        local amount=tonumber(v)
        if amount and amount==amount and amount>0 then reduction+=amount end
    end
    return math.ceil(baseCost*math.max(0,scale-reduction))
end
function app:GetEffectiveCost(baseCost) return effectiveCost(baseCost,cfg.CostDiscounts) end
local function findCandidates()
    local folder=W:FindFirstChild("_UNITS")
    local result={}
    if not folder then return result,"_UNITS not found" end
    local byUuid={}
    for slot=1,6 do
        if cfg.Slots[slot] then
            local uuid=equippedUuid(slot)
            if type(uuid)=="string" and uuid~="" then
                byUuid[uuid]=byUuid[uuid] or {}
                table.insert(byUuid[uuid],slot)
            end
        end
    end
    for _,unit in ipairs(folder:GetChildren()) do
        local stats=unit:FindFirstChild("_stats")
        local owner=getStat(stats,"player")
        if owner==player then
            local uuid=getStat(stats,"uuid")
            local slots=uuid and byUuid[tostring(uuid)]
            if slots and #slots==1 then
                local slot=slots[1]
                local level=tonumber(getStat(stats,"upgrade"))
                local maxLevel=tonumber(getStat(stats,"max_upgrade"))
                local goal=tonumber(cfg.TargetLevel[slot])
                if level and maxLevel then
                    goal=goal and goal>=0 and math.min(goal,maxLevel) or maxLevel
                    if level<goal then
                        local tableCosts=cfg.CostOverrides[slot]
                        local cost=tableCosts and tonumber(tableCosts[level])
                        if not cost then
                            local id=getStat(stats,"id")
                            local definition=unitData and id and unitData[tostring(id)]
                            local nextUpgrade=definition and definition.upgrade and definition.upgrade[level+1]
                            local base=nextUpgrade and tonumber(nextUpgrade.cost)
                            local multiplier=tonumber(getStat(stats,"upgrade_cost_multiplier")) or 1
                            if base then cost=effectiveCost(base*multiplier,cfg.CostDiscounts) end
                        end
                        if cost and cost<0 then cost=nil end
                        table.insert(result,{
                            Unit=unit,Slot=slot,Level=level,Target=goal,Cost=cost,
                            Priority=tonumber(cfg.Priority[slot]) or slot,
                        })
                    end
                end
            end
        end
    end
    table.sort(result,function(a,b)
        if a.Priority~=b.Priority then return a.Priority<b.Priority end
        if a.Cost and b.Cost and a.Cost~=b.Cost then return a.Cost<b.Cost end
        if a.Cost and not b.Cost then return true end
        if b.Cost and not a.Cost then return false end
        if a.Slot~=b.Slot then return a.Slot<b.Slot end
        if a.Level~=b.Level then return a.Level<b.Level end
        return a.Unit:GetFullName()<b.Unit:GetFullName()
    end)
    return result
end
function app:Preview()
    local units,err=findCandidates()
    local money=resource()
    self.LastPlan=units
    log("PREVIEW","owned candidates",#units,"money",money or "unknown",err or "")
    for i,u in ipairs(units) do
        log("QUEUE",i,"slot",u.Slot,"priority",u.Priority,u.Unit.Name,
            "level",u.Level.."/"..u.Target,"next-cost",u.Cost or "UNKNOWN",
            "affordable",u.Cost and money and money-cfg.ReserveMoney>=u.Cost or "UNKNOWN")
    end
    if #units==0 then log("No units eligible (or slot UUIDs missing)") end
    return units
end
local function upgradeRemote()
    local rs=game:GetService("ReplicatedStorage")
    local e=rs:FindFirstChild("endpoints")
    local c=e and e:FindFirstChild("client_to_server")
    local remote=c and c:FindFirstChild("upgrade_unit_ingame")
    return remote and remote:IsA("RemoteFunction") and remote or nil
end
function app:UpgradeOnce()
    if self.Uncertain then
        local pending=self.PendingUpgrade
        if pending then
            local stats=pending.Unit and pending.Unit:FindFirstChild("_stats")
            local observed=stats and tonumber(getStat(stats,"upgrade"))
            if observed and observed>pending.Level then
                self.Uncertain=false;self.PendingUpgrade=nil;self.Verified+=1
                self.Status="Late verified "..pending.Unit.Name.." | Level "..pending.Level.." -> "..observed
                return true,"Late verified"
            end
            if os.clock()-pending.Since<12 then
                self.Status="Rechecking upgrade result ("..math.floor(os.clock()-pending.Since).."/12s)"
                return false,"Rechecking pending upgrade"
            end
        end
        self.Uncertain=false;self.PendingUpgrade=nil
    end
    if cfg.Mode~="LIVE" then return false,"Mode is PREVIEW; no request sent" end
    local remote=upgradeRemote()
    if not remote then return false,"upgrade_unit_ingame missing" end
    local queue=findCandidates()
    local money=resource()
    if not money then return false,"resource missing" end
    local selected=nil
    local currentPriority=nil
    for _,u in ipairs(queue) do
        if u.Cost~=nil then
            if currentPriority==nil then currentPriority=u.Priority end
            if u.Priority>currentPriority and not cfg.AllowLowerPriorityWhenUnaffordable then break end
            if money-(tonumber(cfg.ReserveMoney) or 0)>=u.Cost then selected=u;break end
        end
    end
    if not selected then
        self.Status=#queue==0 and "No eligible units" or "Waiting for money / eligible upgrade"
        return false,"No affordable, priced, eligible unit"
    end
    local unit=selected.Unit
    local stats=unit:FindFirstChild("_stats")
    local owner=getStat(stats,"player")
    local oldLevel=tonumber(getStat(stats,"upgrade"))
    if owner~=player or unit.Parent~=W:FindFirstChild("_UNITS") or oldLevel~=selected.Level then
        return false,"Unit ownership or level changed"
    end
    if self.Requests>=math.max(1,tonumber(cfg.MaxUpgradesPerRun) or 30) then
        self.Status="Upgrade request batch reached; continuing"
        self.Requests=0
    end
    self.Requests+=1
    self.LastUnit=unit.Name
    self.LastCost=selected.Cost
    self.Status="Upgrading "..unit.Name.." | Slot "..selected.Slot.." | Level "..oldLevel.." -> "..(oldLevel+1).." | Cost "..tostring(selected.Cost)
    log("UPGRADE REQUEST",unit.Name,"slot",selected.Slot,"old level",oldLevel,"expected cost",selected.Cost)
    -- Source references pass the placed Model itself, not its inventory UUID.
    local ok,reply=pcall(function() return remote:InvokeServer(unit) end)
    if not ok then warn("[AAAutoUpgrade] Request error",reply) end
    local deadline=os.clock()+math.clamp(tonumber(cfg.VerifyTimeout) or 2,0.5,8)
    repeat
        local observed=tonumber(getStat(stats,"upgrade"))
        if observed and observed>oldLevel then
            self.Verified+=1
            self.Status="Verified "..unit.Name.." | Level "..oldLevel.." -> "..observed
            log("UPGRADE VERIFIED",unit.Name,oldLevel,"->",observed)
            return true,"Verified"
        end
        if self.Stopped then break end
        task.wait(0.1)
    until os.clock()>=deadline
    self.Uncertain=true
    self.PendingUpgrade={Unit=unit,Level=oldLevel,Since=os.clock()}
    self.Status="Waiting to recheck upgrade result: "..unit.Name
    warn("[AAAutoUpgrade] UPGRADE NOT CONFIRMED; recheck before any retry",unit.Name,oldLevel,"reply",tostring(reply))
    return false,"Rechecking pending upgrade"
end
function app:Start()
    if self.Running then return end
    self.Running=true;self.Stopped=false;self.Uncertain=false;self.PendingUpgrade=nil;self.Requests=0;self.Verified=0
    self.Status=cfg.Mode=="LIVE" and "Starting Auto Upgrade" or "Previewing upgrades"
    local live=cfg.Mode=="LIVE"
    log("Scheduler started",live and "LIVE" or "PREVIEW")
    task.spawn(function()
        while self.Running and not self.Stopped do
            if live then
                local ok,reason=self:UpgradeOnce()
                if not ok and reason~="No affordable, priced, eligible unit" and reason~="Rechecking pending upgrade" then
                    self.Status="Waiting / retrying: "..tostring(reason)
                    log("Scheduler retry",reason)
                end
            else
                self:Preview()
            end
            task.wait(math.max(0.5,tonumber(live and cfg.RequestDelay or cfg.ScanInterval) or 1))
        end
        self.Running=false
    end)
end
function app:Stop() self.Stopped=true;self.Running=false;if not self.Uncertain and not tostring(self.Status):find("Paused:",1,true) then self.Status="Stopped" end;log("Stopped") end
function app:Destroy() self:Stop() end
log("U2 loaded: PREVIEW default; set Config.Mode='LIVE' to allow verified upgrades")

end

end
