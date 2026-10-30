-- Generated from src. Do not edit.
local __factories = {}
local __cache = {}
local __loading = {}
local function requireModule(name)
    if __cache[name] ~= nil then return __cache[name] end
    local factory = __factories[name]
    assert(factory, 'Unknown bundled module: '..tostring(name))
    assert(not __loading[name], 'Circular dependency: '..name)
    __loading[name] = true
    local ok, value = pcall(factory)
    __loading[name] = nil
    if not ok then error(value, 2) end
    assert(value ~= nil, 'Module returned nil: '..name)
    __cache[name] = value
    return value
end
__factories["Core.RoadDetector"] = function()
-- Road detection using enemy Lane 1 waypoints. Other lanes remain future work.
return function(WS)
local function lanePoints()
    local bases=WS:FindFirstChild("_BASES")
    local pve=bases and bases:FindFirstChild("pve")
    local lanes=pve and pve:FindFirstChild("LANES")
    local lane=lanes and lanes:FindFirstChild("1")
    if not lane then return nil end
    local points={}
    local function add(part,index)
        if part and part:IsA("BasePart") then table.insert(points,{Index=index,Position=part.Position,Path=part:GetFullName()}) end
    end
    add(lane:FindFirstChild("spawn"),0)
    local numbered={}
    for _,part in ipairs(lane:GetChildren()) do
        local n=tonumber(part.Name)
        if n and part:IsA("BasePart") then table.insert(numbered,{n=n,part=part}) end
    end
    table.sort(numbered,function(a,b)return a.n<b.n end)
    for _,item in ipairs(numbered) do add(item.part,item.n) end
    add(lane:FindFirstChild("final"),#numbered+1)
    if #points<2 then return nil end
    return points
end
local function lanePosition(percent)
    local points=lanePoints()
    if not points then return nil end
    local length=0
    for i=1,#points-1 do length+=(points[i+1].Position-points[i].Position).Magnitude end
    if length<=0 then return nil end
    local target=length*math.clamp(tonumber(percent) or 50,0,100)/100
    local traveled=0
    for i=1,#points-1 do
        local a,b=points[i],points[i+1]
        local segment=(b.Position-a.Position).Magnitude
        if segment>0 and traveled+segment>=target then
            return a.Position:Lerp(b.Position,(target-traveled)/segment),nil,#points,length,a.Index,b.Index
        end
        traveled+=segment
    end
    local last=points[#points]
    return last.Position,nil,#points,length,points[#points-1].Index,last.Index
end
local function distanceToLaneXZ(position)
    local points=lanePoints()
    if not points then return nil end
    local p=Vector2.new(position.X,position.Z)
    local closest=math.huge
    for i=1,#points-1 do
        local a=Vector2.new(points[i].Position.X,points[i].Position.Z)
        local b=Vector2.new(points[i+1].Position.X,points[i+1].Position.Z)
        local d=b-a
        local len2=d:Dot(d)
        local t=len2>0 and math.clamp((p-a):Dot(d)/len2,0,1) or 0
        closest=math.min(closest,(p-(a+d*t)).Magnitude)
    end
    return closest
end

return {lanePoints=lanePoints,lanePosition=lanePosition,distanceToLaneXZ=distanceToLaneXZ}
end

end
__factories["Core.PlacementEngine"] = function()
-- Placement candidate planning, ground checks and spacing; behavior preserved.
return function(deps)
    local cfg = deps.cfg
    local WS = deps.WS
    local player = deps.player
    local savedPlacementAnchor = deps.savedPlacementAnchor
    local pathMidpoint = deps.pathMidpoint
    local distanceToLaneXZ = deps.distanceToLaneXZ
local function offsets()
    local list={}
    local radius=math.clamp(tonumber(cfg.Radius) or 12,1,45)
    local step=math.clamp(tonumber(cfg.GridStep) or 3,1,12)
    local count=math.floor(radius/step)
    for x=-count,count do for z=-count,count do
        local dx,dz=x*step,z*step
        if dx*dx+dz*dz<=radius*radius then
            table.insert(list,{dx=dx,dz=dz,d2=dx*dx+dz*dz})
        end
    end end
    table.sort(list,function(a,b)
        if a.d2==b.d2 then
            if a.dx==b.dx then return a.dz<b.dz end
            return a.dx<b.dx
        end
        return a.d2<b.d2
    end)
    return list
end
local function slowAnchorPercent(index)
    local base=math.clamp(tonumber(cfg.PathPercent) or 50,0,100)
    -- Slow 1/2/3/4: main -10%, main, main +10%, main -20%.
    local offsets={-10,0,10,-20}
    local delta=offsets[index+1] or (index-1)*10
    return math.clamp(base+delta,0,100)
end
local function unitPlacementCandidates(kind,existing,required,mainCenter,offsetsList)
    local list={}
    local manual=savedPlacementAnchor()
    if manual then
        for _,offset in ipairs(offsetsList) do table.insert(list,{Center=manual,Offset=offset,Ordinal=0}) end
        return list
    end
    if kind=="Slow" then
        for index=existing,existing+required-1 do
            local percent=slowAnchorPercent(index)
            local anchor,err=pathMidpoint(percent)
            if not anchor then
                warn("[AAAutoPlay] Slow anchor missing",percent,err)
                return nil
            end
            for _,offset in ipairs(offsetsList) do
                table.insert(list,{Center=anchor,Offset=offset,Ordinal=index-existing+1,Percent=percent})
            end
        end
    elseif kind=="Farm" then
        local base=math.clamp(tonumber(cfg.PathPercent) or 50,0,100)
        -- Distribute around the configured path position, never outside +/- 10%.
        local percents={base-10,base+10}
        for _,offset in ipairs(offsetsList) do
            for _,p in ipairs(percents) do
                local percent=math.clamp(p,0,100)
                local anchor,err=pathMidpoint(percent)
                if not anchor then
                    warn("[AAAutoPlay] Farm anchor missing",percent,err)
                    return nil
                end
                table.insert(list,{Center=anchor,Offset=offset,Ordinal=0,Percent=percent})
            end
        end
    else
        for _,offset in ipairs(offsetsList) do
            table.insert(list,{Center=mainCenter,Offset=offset,Ordinal=0})
        end
    end
    return list
end
local placementDirectionCache={Key=nil,Tangent=nil}
local function placementDirection()
    local key=tostring(cfg.CurrentMapKey)..":"..tostring(cfg.PathPercent)
    if placementDirectionCache.Key==key and placementDirectionCache.Tangent then return placementDirectionCache.Tangent end
    placementDirectionCache.Key=key
    placementDirectionCache.Tangent=nil
    local pct=math.clamp(tonumber(cfg.PathPercent) or 50,2,98)
    local a=pathMidpoint(pct-2)
    local b=pathMidpoint(pct+2)
    if a and b then
        local delta=Vector3.new(b.X-a.X,0,b.Z-a.Z)
        if delta.Magnitude>0.01 then placementDirectionCache.Tangent=delta.Unit end
    end
    return placementDirectionCache.Tangent
end
local function findGround(center,offset)
    local params=RaycastParams.new()
    params.FilterType=Enum.RaycastFilterType.Exclude
    local ignore={}
    if player.Character then table.insert(ignore,player.Character) end
    for _,name in ipairs({"_BASES","_UNITS","_PATH_UNITS","ignore","_RoadDetectionV1_Debug","AAAutoPlacePreview","AAAutoPlaceRoadPreview"}) do
        local obj=WS:FindFirstChild(name)
        if obj then table.insert(ignore,obj) end
    end
    params.FilterDescendantsInstances=ignore
    local point=center+Vector3.new(offset.dx,0,offset.dz)
    if cfg.CenterMode=="PATH_MIDPOINT" and not savedPlacementAnchor() then
        local tangent=placementDirection()
        if not tangent then return nil end
        if tangent then
            local left=Vector3.new(-tangent.Z,0,tangent.X)
            local sign=cfg.PlacementSide=="RIGHT" and -1 or 1
            local lateral=cfg.PlacementSide=="CENTER" and offset.dx or (math.abs(offset.dx)+math.max(2,tonumber(cfg.GridStep) or 3))*sign
            point=center+left*lateral+tangent*offset.dz
        end
    end
    local distance=distanceToLaneXZ(point)
    if distance and distance<=math.clamp(tonumber(cfg.RoadHalfWidth) or 1,0.25,8) then return nil end
    local ray=WS:Raycast(point+Vector3.new(0,cfg.ScanHeight,0),Vector3.new(0,-(cfg.ScanHeight*2+20),0),params)
    if not ray or ray.Normal.Y<cfg.MinNormalY then return nil end
    local road=WS:FindFirstChild("_road")
    if road and ray.Instance and ray.Instance:IsDescendantOf(road) then return nil end
    if math.abs(ray.Position.Y-center.Y)>cfg.MaxHeightDifference then return nil end
    return ray.Position
end
local function farEnough(pos,positions)
    local space=math.max(1,tonumber(cfg.UnitSpacing) or 3)
    for _,p in ipairs(positions) do
        local dx,dz=pos.X-p.X,pos.Z-p.Z
        if dx*dx+dz*dz<space*space then return false end
    end
    return true
end

    return {offsets=offsets,slowAnchorPercent=slowAnchorPercent,unitPlacementCandidates=unitPlacementCandidates,findGround=findGround,farEnough=farEnough}
end

end
__factories["Core.PlacementVerifier"] = function()
-- Placement ownership, UUID counting and spawn confirmation; unchanged behavior.
return function(cfg, player)
local function ownedSnapshot(folder)
    local found={}
    for _,unit in ipairs(folder:GetChildren()) do
        if not cfg.Blacklist[unit.Name:lower()] then
            local stats=unit:FindFirstChild("_stats")
            local owner=stats and stats:FindFirstChild("player")
            if owner and owner.Value==player then found[unit]=true end
        end
    end
    return found
end
local function countOwnedByUuid(folder,uuid)
    local count=0
    for unit in pairs(ownedSnapshot(folder)) do
        local st=unit:FindFirstChild("_stats")
        local id=st and st:FindFirstChild("uuid")
        if id and tostring(id.Value)==tostring(uuid) then count+=1 end
    end
    return count
end
local function existingPositions(folder)
    local positions={}
    for unit in pairs(ownedSnapshot(folder)) do
        local ok,p=pcall(function()return unit:GetPivot().Position end)
        if ok then table.insert(positions,p) end
    end
    return positions
end
local function matchingNewUnit(folder,before,uuid,position)
    local closest,best=nil,math.huge
    for unit in pairs(ownedSnapshot(folder)) do
        if not before[unit] and unit.Parent==folder then
            local st=unit:FindFirstChild("_stats")
            local id=st and st:FindFirstChild("uuid")
            if id and tostring(id.Value)==tostring(uuid) then
                local ok,pivot=pcall(function() return unit:GetPivot().Position end)
                if ok then
                    local distance=(pivot-position).Magnitude
                    if distance<best and distance<=40 then closest,best=unit,distance end
                end
            end
        end
    end
    return closest
end
return {ownedSnapshot=ownedSnapshot,countOwnedByUuid=countOwnedByUuid,existingPositions=existingPositions,matchingNewUnit=matchingNewUnit}
end

end
__factories["Features.AutoUpgrade"] = function()
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

end
__factories["Features.AutoSkill"] = function()
-- AutoSkill extracted with original lexical scope and behavior.
return function(cfg)
-- Embedded Auto Skill | per-slot support
-- Kept in a lexical scope so its local app does not shadow Auto Place app.
do
-- AA Auto Skill | v0.1.0-test.2
-- Experimental: read-only by default. Explicitly set Enabled=true to attempt casts.
repeat task.wait() until game:IsLoaded()
local Players=game:GetService("Players")
local RS=game:GetService("ReplicatedStorage")
local WS=game:GetService("Workspace")
local player=Players.LocalPlayer
local env=(type(getgenv)=="function" and getgenv()) or _G
if env.AAAutoSkill and env.AAAutoSkill.Stop then env.AAAutoSkill:Stop() end
local app={
    Version="0.1.0-test.2",
    Slots=cfg.AutoSkillSlots,
    Enabled=false, -- opt in per slot; requires Auto Play running
    Running=false,
    Stopped=false,
    ScanInterval=1,
    MinRequestGap=1,
    RequestFallbackGap=3,
    PerUnit={},
    Status="Idle",
    Requests=0,
    Verified=0,
    NextCheck=0,
}
env.AAAutoSkill=app
local function stat(folder,name)
    local value=folder and folder:FindFirstChild(name)
    return value and value:IsA("ValueBase") and value.Value or nil
end
local function slotUuids()
    local found={}
    local gui=player:FindFirstChild("PlayerGui")
    local group=gui and gui:FindFirstChild("spawn_units")
    if not group then return found end
    for slot=1,6 do
        if app.Slots[slot]==true then
            local frame=group:FindFirstChild(tostring(slot),true)
            local uuid=frame and frame:GetAttribute("_equipped_frame_unit_uuid")
            if uuid then found[tostring(uuid)]=slot end
        end
    end
    return found
end
local function myUnits()
    local result={}
    local folder=WS:FindFirstChild("_UNITS")
    if not folder then return result end
    local enabledUuids=slotUuids()
    for _,unit in ipairs(folder:GetChildren()) do
        local stats=unit:FindFirstChild("_stats")
        local uuid=stat(stats,"uuid")
        local slot=uuid and enabledUuids[tostring(uuid)]
        if slot and stat(stats,"player")==player then
            table.insert(result,{Model=unit,Slot=slot,Stats=stats,Skill=stat(stats,"active_attack"),
                Cooldown=tonumber(stat(stats,"active_attack_cooldown")),
                LastCast=tonumber(stat(stats,"last_active_cast")),
                Queued=stat(stats,"active_queued_or_using")==true})
        end
    end
    return result
end
function app:Inspect()
    local units=myUnits()
    print("[AAAutoSkill] Version",self.Version,"Owned",#units,"Mode",self.Enabled and "LIVE" or "PREVIEW")
    for _,unit in ipairs(units) do
        print("[AAAutoSkill] UNIT Slot",unit.Slot,unit.Model.Name,"Skill",tostring(unit.Skill),"Cooldown",tostring(unit.Cooldown),"LastCast",tostring(unit.LastCast),"Queued",unit.Queued)
    end
    self.Status=#units>0 and ("Detected "..#units.." enabled unit(s)") or "Waiting for enabled Slot unit"
    return units
end
function app:Step()
    local units=myUnits()
    if #units==0 then self.Status="Waiting for enabled Slot units";return end
    local remote=RS:FindFirstChild("endpoints")
    remote=remote and remote:FindFirstChild("client_to_server")
    remote=remote and remote:FindFirstChild("use_active_attack")
    if not remote or not remote:IsA("RemoteFunction") then self.Status="Skill remote unavailable";return end
    for _,u in ipairs(units) do
        if self.Stopped then return end
        if self.Slots[u.Slot]~=true then continue end
        if type(u.Skill)~="string" or u.Skill=="" then
            self.Status="Slot "..u.Slot.." has no active skill"
        elseif u.Queued then
            self.Status="Skill queued / casting: "..u.Model.Name
        else
            -- Read current cooldown each tick; never cache old upgraded cooldown.
            local cd=math.max(1,tonumber(u.Cooldown) or 3)
            local key=u.Model
            local state=self.PerUnit[key]
            if not state then
                state={NextAt=0,LastCooldown=cd}
                self.PerUnit[key]=state
            elseif state.LastCooldown~=cd then
                -- The upgrade changed CD: adjust outstanding wait from last attempt.
                state.LastCooldown=cd
                if state.LastAttempt then
                    state.NextAt=state.LastAttempt+cd
                end
                print("[AAAutoSkill] Cooldown updated",u.Model.Name,cd)
            end
            if not self.Enabled then
                self.Status="PREVIEW: "..u.Model.Name.." | "..u.Skill.." | live CD "..cd.."s"
            elseif os.clock()<state.NextAt then
                self.Status="Cooldown "..u.Model.Name.." | "..math.ceil(state.NextAt-os.clock()).."s | CD "..cd.."s"
            else
                -- Per-slot opt-in. Remote signature still experimental; observe result.
                state.LastAttempt=os.clock()
                state.NextAt=state.LastAttempt+math.max(cd,self.MinRequestGap)
                local before=tonumber(stat(u.Stats,"last_request_active_cast"))
                local ok,reply=pcall(function()return remote:InvokeServer(u.Model)end)
                self.Requests+=1
                task.wait(0.2)
                local after=tonumber(stat(u.Stats,"last_request_active_cast"))
                local verified=after and after~=before
                if verified then
                    self.Verified+=1
                else
                    -- Unconfirmed: continue observing without immediate spam.
                    state.NextAt=math.max(state.NextAt,os.clock()+self.RequestFallbackGap)
                end
                self.Status=(verified and "Skill observed" or "Skill not confirmed").." | "..u.Model.Name.." | CD "..cd.."s"
                print("[AAAutoSkill]",self.Status,"reply",tostring(reply),"remoteOK",ok)
            end
        end
    end
end
function app:Start()
    if self.Running then return end
    self.Stopped=false
    self.Running=true
    task.spawn(function()
        while not self.Stopped and env.AAAutoSkill==self do
            local ok,err=pcall(function()self:Step()end)
            if not ok then self.Status="Error: "..tostring(err);warn("[AAAutoSkill]",err) end
            task.wait(math.max(0.25,tonumber(self.ScanInterval) or 0.5))
        end
        self.Running=false
    end)
end
function app:Stop()self.Stopped=true;self.Running=false;self.Status="Stopped"end
print("[AAAutoSkill] Module loaded",app.Version,"per-slot controls in Units tab")
end -- Auto Skill local scope

end

end
__factories["Core.Settings"] = function()
-- Settings reader with original validation rules.
return function(defaults,HttpService,settingsPath,persistKeys)
local function readSettings()
    if type(readfile)~="function" then return {} end
    local ok,data=pcall(function() return HttpService:JSONDecode(readfile(settingsPath)) end)
    if not ok or type(data)~="table" then return {} end
    local safe={}
    for _,key in ipairs(persistKeys) do
        if key=="AutoBuffEnabled" then
            if type(data.AutoBuffEnabled)=="table" then
                safe.AutoBuffEnabled={}
                for _,kind in ipairs({"erwin","wendy","leafa"}) do
                    safe.AutoBuffEnabled[kind]=data.AutoBuffEnabled[kind]==true
                end
            end
        elseif key=="UnitTypes" then
            if type(data.UnitTypes)=="table" then
                local types={}
                for i=1,6 do
                    local kind=data.UnitTypes[i]
                    types[i]=(kind=="Slow" or kind=="Farm" or kind=="Buff") and kind or "Damage"
                end
                safe.UnitTypes=types
            end
        elseif key=="UnitPriority" then
            if type(data.UnitPriority)=="table" then
                local priorities={}
                for i=1,6 do priorities[i]=math.clamp(math.floor(tonumber(data.UnitPriority[i]) or i),1,6) end
                safe.UnitPriority=priorities
            end
        elseif key=="AutoSkillSlots" then
            if type(data.AutoSkillSlots)=="table" then
                safe.AutoSkillSlots={}
                for i=1,6 do safe.AutoSkillSlots[i]=data.AutoSkillSlots[i]==true end
            end
        elseif key=="StartWave" then
            if type(data.StartWave)=="table" then
                safe.StartWave={}
                for i=1,6 do safe.StartWave[i]=math.clamp(math.floor(tonumber(data.StartWave[i]) or 1),1,100) end
            end
        elseif key=="Slots" then
            if type(data.Slots)=="table" then
                local slots={}
                for i=1,6 do slots[i]=math.clamp(math.floor(tonumber(data.Slots[i]) or 0),0,10) end
                safe.Slots=slots
            end
        elseif key=="CenterMode" then
            if table.find({"PATH_MIDPOINT","MOUSE","PLAYER","POSITION"},data[key]) then safe[key]=data[key] end
        elseif type(defaults[key])=="number" then
            if type(data[key])=="number" and data[key]==data[key] and math.abs(data[key])<100000 then safe[key]=data[key] end
        elseif type(defaults[key])=="boolean" and type(data[key])=="boolean" then
            safe[key]=data[key]
        end
    end
    if type(data.MapPlacementAnchors)=="table" then
        safe.MapPlacementAnchors={}
        for key,coords in pairs(data.MapPlacementAnchors) do
            if type(key)=="string" and #key<=180 and type(coords)=="table" then
                local x,y,z=tonumber(coords[1]),tonumber(coords[2]),tonumber(coords[3])
                if x and y and z and x==x and y==y and z==z and math.abs(x)<100000 and math.abs(y)<100000 and math.abs(z)<100000 then
                    safe.MapPlacementAnchors[key]={x,y,z}
                end
            end
        end
    end
    if type(data.MapPlacementSides)=="table" then
        safe.MapPlacementSides={}
        for key,value in pairs(data.MapPlacementSides) do
            if type(key)=="string" and #key<=180 and (value=="LEFT" or value=="CENTER" or value=="RIGHT") then
                safe.MapPlacementSides[key]=value
            end
        end
    end
    if type(data.MapPathPercents)=="table" then
        safe.MapPathPercents={}
        for key,value in pairs(data.MapPathPercents) do
            if type(key)=="string" and #key<=180 and type(value)=="number" and value==value then
                safe.MapPathPercents[key]=math.clamp(value,0,100)
            end
        end
    end
    if type(data.Upgrade)=="table" then
        local u=data.Upgrade
        local upgrade={}
        if type(u.Enabled)=="boolean" then upgrade.Enabled=u.Enabled end
        if type(u.Slots)=="table" then
            upgrade.Slots={}
            for i=1,6 do upgrade.Slots[i]=u.Slots[i]==true end
        end
        if type(u.TargetLevel)=="table" then
            upgrade.TargetLevel={}
            for i=1,6 do upgrade.TargetLevel[i]=math.clamp(math.floor(tonumber(u.TargetLevel[i]) or -1),-1,20) end
        end
        if type(u.CostDiscounts)=="table" then
            upgrade.CostDiscounts={}
            for _,v in ipairs(u.CostDiscounts) do
                local n=tonumber(v)
                if n and n==n and n>=0 and n<=1 and #upgrade.CostDiscounts<16 then table.insert(upgrade.CostDiscounts,n) end
            end
        end
        if type(u.ReserveMoney)=="number" and u.ReserveMoney>=0 and u.ReserveMoney<1e12 then upgrade.ReserveMoney=u.ReserveMoney end
        if type(u.AllowLowerPriorityWhenUnaffordable)=="boolean" then upgrade.AllowLowerPriorityWhenUnaffordable=u.AllowLowerPriorityWhenUnaffordable end
        safe.Upgrade=upgrade
    end
    return safe
end
return readSettings
end

end
__factories["Core.SettingsPersistence"] = function()
-- Settings write/clear methods; existing behavior retained.
return function(deps)
local app=deps.app
local cfg=deps.cfg
local env=deps.env
local persistKeys=deps.persistKeys
local applyMapPathPercent=deps.applyMapPathPercent
local mapPathPercents=deps.mapPathPercents
local mapPlacementSides=deps.mapPlacementSides
local mapPlacementAnchors=deps.mapPlacementAnchors
local HttpService=deps.HttpService
local settingsPath=deps.settingsPath
local log=deps.log
function app:SaveSettings()
    if type(writefile)~="function" then
        warn("[AAAutoPlace] writefile unavailable; settings cannot be saved")
        return false
    end
    local data={}
    for _,key in ipairs(persistKeys) do
        if key=="UnitTypes" then
            data.UnitTypes={}
            for i=1,6 do data.UnitTypes[i]=cfg.UnitTypes[i] end
        elseif key=="AutoSkillSlots" then
            data.AutoSkillSlots={}
            for i=1,6 do data.AutoSkillSlots[i]=cfg.AutoSkillSlots[i]==true end
        elseif key=="StartWave" then
            data.StartWave={}
            for i=1,6 do data.StartWave[i]=math.clamp(math.floor(tonumber(cfg.StartWave[i]) or 1),1,100) end
        elseif key=="UnitPriority" then
            data.UnitPriority={}
            for i=1,6 do data.UnitPriority[i]=math.clamp(math.floor(tonumber(cfg.UnitPriority[i]) or i),1,6) end
        elseif key=="Slots" then
            data.Slots={}
            for i=1,6 do data.Slots[i]=math.clamp(math.floor(tonumber(cfg.Slots[i]) or 0),0,10) end
        else data[key]=cfg[key] end
    end
    local key=applyMapPathPercent()
    if key then mapPathPercents[key]=math.clamp(tonumber(cfg.PathPercent) or 50,0,100) end
    data.MapPathPercents=mapPathPercents
    data.MapPlacementSides=mapPlacementSides
    data.MapPlacementAnchors=mapPlacementAnchors
    local upgrade=env.AAAutoUpgrade
    if upgrade and type(upgrade.Config)=="table" then
        local uc=upgrade.Config
        data.Upgrade={Enabled=uc.Enabled==true,Slots={},TargetLevel={},CostDiscounts={},ReserveMoney=math.max(0,tonumber(uc.ReserveMoney) or 0),AllowLowerPriorityWhenUnaffordable=uc.AllowLowerPriorityWhenUnaffordable==true}
        for i=1,6 do
            data.Upgrade.Slots[i]=uc.Slots[i]==true
            data.Upgrade.TargetLevel[i]=math.clamp(math.floor(tonumber(uc.TargetLevel[i]) or -1),-1,20)
        end
        for _,v in ipairs(uc.CostDiscounts or {}) do
            local n=tonumber(v)
            if n and n==n and n>=0 and n<=1 and #data.Upgrade.CostDiscounts<16 then table.insert(data.Upgrade.CostDiscounts,n) end
        end
    end
    local ok,err=pcall(function() writefile(settingsPath,HttpService:JSONEncode(data)) end)
    if not ok then warn("[AAAutoPlace] Settings save failed:",err);return false end
    log("Settings saved to",settingsPath)
    return true
end
function app:ClearSavedSettings()
    if type(delfile)~="function" then
        warn("[AAAutoPlace] delfile unavailable; cannot clear saved settings")
        return false
    end
    local ok,err=pcall(function() delfile(settingsPath) end)
    if not ok then warn("[AAAutoPlace] Clear settings failed:",err);return false end
    log("Saved settings cleared; re-execute for defaults")
    return true
end
end

end
__factories["UI.MainWindow"] = function()
-- UI module: original WindUI callbacks preserved.
return function(deps)
local app=deps.app
local cfg=deps.cfg
local env=deps.env
local player=deps.player
local upgradeApp=deps.upgradeApp
local startAutoPlay=deps.startAutoPlay
local stopAutoPlay=deps.stopAutoPlay
local applyMapPathPercent=deps.applyMapPathPercent
local mapPathPercents=deps.mapPathPercents
local mapPlacementSides=deps.mapPlacementSides
local mapPlacementAnchors=deps.mapPlacementAnchors
local statusText=deps.statusText
local log=deps.log
local SCRIPT_VERSION=deps.SCRIPT_VERSION
local saved=deps.saved
local isAutoPlayRunning=deps.isAutoPlayRunning
local syncAutoBuff=deps.syncAutoBuff
local function buildWindUI()
    local WindUI=loadstring(game:HttpGet("https://github.com/Footagesus/WindUI/releases/download/1.6.66/main.lua"))()
    local window=WindUI:CreateWindow({
        Title="AA Auto Play v"..SCRIPT_VERSION,Icon="gamepad-2",Folder="AAAutoPlay",
        Size=UDim2.fromOffset(585,470),Theme="Dark",
        HideSearchBar=true,Resizable=true,ToggleKey=Enum.KeyCode.RightShift,
        OpenButton={Title="Open AA Auto Play",Enabled=true,Draggable=true,OnlyMobile=false,Scale=0.65},
    })
    app.WindUIWindow=window
    local dashboard=window:Tab({Title="Dashboard",Icon="layout-dashboard"})
    dashboard:Paragraph({Title="Sequential / LIVE",Desc="Place all units first, then begin Auto Upgrade."})
    app.StatusParagraph=dashboard:Paragraph({Title="Auto Play Status",Desc=app.CurrentStatus or "Idle - ready to start"})
    app.UpgradeParagraph=dashboard:Paragraph({Title="Auto Upgrade",Desc="Idle | Sequential mode"})
    app.WaveParagraph=dashboard:Paragraph({Title="Wave Scheduler",Desc="Waiting for Wave data"})
    app.SkillParagraph=dashboard:Paragraph({Title="Auto Skill (Selected Slots)",Desc="Idle"})
    task.spawn(function()
        local last=""
        while app.WindUIWindow==window and env.AAAutoPlace==app do
            local upgrade=upgradeApp()
            local sk=env.AAAutoSkill
            if sk then pcall(function() app.SkillParagraph:SetDesc((sk.Enabled and "LIVE | " or "PREVIEW | ")..tostring(sk.Status).." | Casts "..tostring(sk.Verified).."/"..tostring(sk.Requests)) end) end
            pcall(function() app.WaveParagraph:SetDesc("Wave "..tostring(app.CurrentWave or "?").." | Next Placement "..tostring(app.NextPlacementWave or "-")) end)
            local details=upgrade and (tostring(upgrade.Status or "Idle").." | Verified "..tostring(upgrade.Verified or 0).." | Requests "..tostring(upgrade.Requests or 0).."/"..tostring(upgrade.Config.MaxUpgradesPerRun)) or "Unavailable"
            if details~=last then
                last=details
                pcall(function() app.UpgradeParagraph:SetDesc(details) end)
            end
            task.wait(0.5)
        end
    end)
    dashboard:Toggle({Title="Auto Play",Value=cfg.AutoPlayEnabled==true,Callback=function(v)
        cfg.AutoPlayEnabled=v==true
        if cfg.AutoPlayEnabled then startAutoPlay() else stopAutoPlay() end
        app:SaveSettings()
    end})
    local previewToggle
    previewToggle=dashboard:Toggle({Title="Show Placement Preview",Value=cfg.ShowPreview,Callback=function(v)app:SetPreview(v)end})
    dashboard:Button({Title="Refresh Preview",Callback=function()app:RefreshPreview()end})
    dashboard:Button({Title="Preview Upgrade Queue",Callback=function()local u=upgradeApp();if u then u:Preview()end end})
    local unitTab=window:Tab({Title="Units",Icon="users"})
    unitTab:Paragraph({Title="Per-slot configuration",Desc="Select a slot from the dropdown below. Changes affect the selected slot only."})
    local selected=1
    local changing=false
    local typeControl,countControl,priorityControl,enabledControl,targetControl,waveControl,skillControl
    local function syncControls()
        changing=true
        local upgrade=upgradeApp()
        typeControl:Select(cfg.UnitTypes[selected] or "Damage")
        countControl:Set(cfg.Slots[selected] or 0)
        priorityControl:Set(cfg.UnitPriority[selected] or selected)
        waveControl:Set(cfg.StartWave[selected] or 1)
        if skillControl then skillControl:Set(cfg.AutoSkillSlots[selected]==true) end
        enabledControl:Set(upgrade and upgrade.Config.Slots[selected]==true or false)
        targetControl:Set(upgrade and upgrade.Config.TargetLevel[selected] or -1)
        changing=false
    end
    unitTab:Dropdown({Title="Select Unit Slot",Values={"Slot 1","Slot 2","Slot 3","Slot 4","Slot 5","Slot 6"},Value="Slot 1",Callback=function(v)
        local number=tonumber(tostring(v):match("%d+"))
        if number and number>=1 and number<=6 then selected=number;if typeControl then syncControls()end end
    end})
    typeControl=unitTab:Dropdown({Title="Unit Type",Values={"Damage","Buff","Slow","Farm"},Value=cfg.UnitTypes[1] or "Damage",Callback=function(v)
        if not changing and table.find({"Damage","Buff","Slow","Farm"},v) then cfg.UnitTypes[selected]=v end
    end})
    countControl=unitTab:Slider({Title="Placement Count",Step=1,Value={Min=0,Max=10,Default=cfg.Slots[1] or 0},Callback=function(v)
        if not changing then cfg.Slots[selected]=math.clamp(math.floor(v),0,10)end
    end})
    waveControl=unitTab:Slider({Title="Start Placement at Wave",Step=1,Value={Min=1,Max=100,Default=cfg.StartWave[1] or 1},Callback=function(v)
        if not changing then cfg.StartWave[selected]=math.clamp(math.floor(v),1,100) end
    end})
    priorityControl=unitTab:Slider({Title="Priority (1 first)",Step=1,Value={Min=1,Max=6,Default=cfg.UnitPriority[1] or 1},Callback=function(v)
        if not changing then
            cfg.UnitPriority[selected]=math.clamp(math.floor(v),1,6)
            local u=upgradeApp();if u then u.Config.Priority[selected]=cfg.UnitPriority[selected]end
        end
    end})
    local u=upgradeApp()
    enabledControl=unitTab:Toggle({Title="Upgrade this Slot",Value=u and u.Config.Slots[1]==true or false,Callback=function(v)
        if not changing then local up=upgradeApp();if up then up.Config.Slots[selected]=v end end
    end})
    targetControl=unitTab:Slider({Title="Upgrade Target (-1 = MAX)",Step=1,Value={Min=-1,Max=20,Default=u and u.Config.TargetLevel[1] or -1},Callback=function(v)
        if not changing then local up=upgradeApp();if up then up.Config.TargetLevel[selected]=math.clamp(math.floor(v),-1,20)end end
    end})
    skillControl=unitTab:Toggle({Title="Auto Skill for this Slot",Value=cfg.AutoSkillSlots[1]==true,Callback=function(v)
        if not changing then
            cfg.AutoSkillSlots[selected]=v
            local sk=env.AAAutoSkill
            if sk then sk.Enabled=isAutoPlayRunning() and cfg.Mode=="LIVE" and table.find(cfg.AutoSkillSlots,true)~=nil end
        end
    end})
    local placement=window:Tab({Title="Placement",Icon="map-pin"})
    placement:Dropdown({Title="Center Mode",Values={"PATH_MIDPOINT","MOUSE","PLAYER","POSITION"},Value=cfg.CenterMode,Callback=function(v)cfg.CenterMode=v end})
    local pathSlider
    local sideControl
    sideControl=placement:Dropdown({Title="Placement Side - This Stage",Values={"LEFT","CENTER","RIGHT"},Value=cfg.PlacementSide,Callback=function(v)
        if v=="LEFT" or v=="CENTER" or v=="RIGHT" then
            cfg.PlacementSide=v
            if cfg.CurrentMapKey then mapPlacementSides[cfg.CurrentMapKey]=v end
            app:RefreshPreview()
        end
    end})
    local mapLabel=placement:Paragraph({Title="Current Stage",Desc=cfg.CurrentMapKey or "Waiting for map data"})
    placement:Paragraph({Title="Manual Placement Area",Desc="Set a verified buildable location with mouse. Saved separately per stage; overrides decorative road anchoring for all unit types."})
    placement:Button({Title="Use Mouse Position as Placement Center",Callback=function()
        local key=applyMapPathPercent()
        local mouse=player:GetMouse()
        local hit=mouse and mouse.Target
        if not key or not hit or not mouse.Hit then
            statusText("Manual placement: point mouse at buildable ground on a loaded stage")
            return
        end
        local point=mouse.Hit.Position
        mapPlacementAnchors[key]={point.X,point.Y,point.Z}
        app:SaveSettings()
        app:RefreshPreview()
        statusText("Manual placement center saved for this stage")
    end})
    placement:Button({Title="Clear Manual Placement Center",Callback=function()
        local key=applyMapPathPercent()
        if key then mapPlacementAnchors[key]=nil;app:SaveSettings() end
        app:RefreshPreview()
        statusText("Using automatic road-based placement again")
    end})
    pathSlider=placement:Slider({Title="Main Path Position (%) - This Stage",Step=5,Value={Min=0,Max=100,Default=cfg.PathPercent},Callback=function(v)
        cfg.PathPercent=math.clamp(tonumber(v) or 50,0,100)
        if cfg.CurrentMapKey then mapPathPercents[cfg.CurrentMapKey]=cfg.PathPercent end
    end})
    task.spawn(function()
        local shownKey=cfg.CurrentMapKey
        while app.WindUIWindow==window and env.AAAutoPlace==app do
            local key=applyMapPathPercent()
            if key and key~=shownKey then
                shownKey=key
                pcall(function() pathSlider:Set(cfg.PathPercent) end)
                pcall(function() sideControl:Select(cfg.PlacementSide) end)
                pcall(function() mapLabel:SetDesc(key) end)
                log("MAP PROFILE",key,"Main Path",cfg.PathPercent.."%")
            end
            task.wait(3)
        end
    end)
    placement:Slider({Title="Radius (studs)",Step=1,Value={Min=1,Max=45,Default=cfg.Radius},Callback=function(v)cfg.Radius=v end})
    placement:Slider({Title="Grid Step",Step=1,Value={Min=1,Max=12,Default=cfg.GridStep},Callback=function(v)cfg.GridStep=v end})
    placement:Button({Title="Refresh Map Preview",Callback=function()app:RefreshPreview()end})
    placement:Button({Title="Inspect Road (Console)",Callback=function()app:InspectRoad()end})
    placement:Toggle({Title="Road Preview",Value=cfg.ShowRoadPreview==true,Callback=function(enabled)
        cfg.ShowRoadPreview=enabled==true
        app:RefreshRoadPreview()
    end})
    placement:Toggle({Title="Slow Placement Preview",Value=cfg.ShowSlowPreview==true,Callback=function(enabled)
        cfg.ShowSlowPreview=enabled==true
        app:RefreshSlowPreview()
    end})
    placement:Button({Title="Refresh Slow Preview",Callback=function()app:RefreshSlowPreview()end})
    placement:Slider({Title="Road Half Width (studs)",Step=0.5,Value={Min=0.5,Max=6,Default=cfg.RoadHalfWidth},Callback=function(v)cfg.RoadHalfWidth=v;if cfg.ShowRoadPreview then app:RefreshRoadPreview()end end})
    local settings=window:Tab({Title="Settings",Icon="settings"})
    settings:Toggle({Title="Enable Auto Upgrade",Value=u and u.Config.Enabled==true or false,Callback=function(v)local up=upgradeApp();if up then up.Config.Enabled=v end end})

    local buffTab=window:Tab({Title="Auto Buff",Icon="zap"})
    buffTab:Paragraph({Title="V3 Rotation",Desc="Four units of one type are required; uses maximum cooldown / 4 + 0.15s."})
    for _,kind in ipairs({"erwin","wendy","leafa"}) do
        local currentKind=kind
        buffTab:Toggle({Title="Enable "..currentKind.." Buff",Value=cfg.AutoBuffEnabled[currentKind]==true,Callback=function(value)
            cfg.AutoBuffEnabled[currentKind]=value==true
            syncAutoBuff(isAutoPlayRunning())
        end})
    end
    settings:Paragraph({Title="Auto Save",Desc="Changes save automatically after 1.5 seconds to AAAutoPlaceSettings.json. SAVE SETTINGS is also available."})
    settings:Button({Title="SAVE SETTINGS",Icon="save",Callback=function()
        local ok=app:SaveSettings()
        WindUI:Notify({Title=ok and "Saved" or "Save Failed",Content=ok and "Auto Play settings saved" or "Check console",Duration=3})
    end})
    dashboard:Select()
    log("WindUI loaded: Dashboard selected / Units / Placement / Settings")
end
return buildWindUI
end

end
__factories["Features.AutoBuff"] = function()
-- AutoBuff: AABuffV3 worker/rotation rules, without the standalone MaterialLua UI.
return function(deps)
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local Workspace=game:GetService("Workspace")
local player=game:GetService("Players").LocalPlayer
local env=deps.env
local existing=env.AAAutoBuff
if existing and type(existing.StopAll)=="function" then existing.StopAll() end
for _,key in ipairs({"AABuffV2","AABuffV3"}) do
    local old=env[key]
    if old and type(old.StopAll)=="function" then pcall(old.StopAll) end
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
env.AAAutoBuff = controller

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
        return controller.active and env.AAAutoBuff == controller
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


return controller
end

end
-- AA AutoPlace Phase 1 | single-file, slots 1-6, bounded real placement
-- Default PREVIEW: only LIVE mode sends spawn_unit requests.
local SCRIPT_VERSION="1.4.0"
repeat task.wait() until game:IsLoaded()
local Players=game:GetService("Players")
local RS=game:GetService("ReplicatedStorage")
local WS=game:GetService("Workspace")
local player=Players.LocalPlayer
local env=(type(getgenv)=="function" and getgenv()) or _G
if env.AAAutoPlace and type(env.AAAutoPlace.Destroy)=="function" then
    pcall(function() env.AAAutoPlace:Destroy() end)
end
local defaults={
    Mode="LIVE", -- Auto Play starts in LIVE mode when Start is pressed
    CenterMode="PATH_MIDPOINT", -- PATH_MIDPOINT (default), MOUSE, PLAYER, POSITION
    CenterPosition=nil,
    PathPercent=50, -- 0=start of road, 100=end; defaults to halfway
    PlacementSide="CENTER", -- LEFT, CENTER or RIGHT, relative to enemy travel direction
    Radius=12, GridStep=3, UnitSpacing=3,
    RoadHalfWidth=1, ShowRoadPreview=false, ShowSlowPreview=false,
    UUIDWaitTimeout=15, ScanHeight=35,
    MaxHeightDifference=8, MinNormalY=0.85,
    Slots={1,1,1,1,1,1}, -- target total per slot
    UnitPriority={1,2,3,4,5,6},
    StartWave={1,1,1,1,1,1}, -- lower number places first
    UnitTypes={"Damage","Damage","Damage","Damage","Damage","Damage"},
    MaxTotalPlaced=12,
    CountExistingUnits=true,
    AutoSkillSlots={false,false,false,false,false,false},
    AutoPlayEnabled=false,
    AutoBuffEnabled={erwin=false,wendy=false,leafa=false},
    ShowPreview=true, AutoPreviewOnLoad=true, MaxPreviewMarkers=100,
    UILibrary="RayfieldGen2",
    Blacklist={elyssia_jellyfish=true,elyssia_eel=true},
}
-- Executor-local JSON settings. Never persist LIVE mode or a map-specific Vector3.
local HttpService=game:GetService("HttpService")
local settingsPath="AAAutoPlaceSettings.json"
local persistKeys={"RoadHalfWidth","ShowRoadPreview","ShowSlowPreview","CenterMode","PathPercent","Radius","GridStep","UnitSpacing","ShowPreview","Slots","UnitPriority","UnitTypes","StartWave","CountExistingUnits","AutoSkillSlots","AutoPlayEnabled","AutoBuffEnabled"}
local readSettings=requireModule("Core.Settings")(defaults,HttpService,settingsPath,persistKeys)
local saved=readSettings()
local override=type(env.AAAutoPlaceConfig)=="table" and env.AAAutoPlaceConfig or {}
local cfg={}
for k,v in pairs(defaults) do
    if override[k]~=nil then cfg[k]=override[k]
    elseif saved[k]~=nil then cfg[k]=saved[k]
    else cfg[k]=v end
end
cfg.Mode=override.Mode=="PREVIEW" and "PREVIEW" or "LIVE"
local mapPathPercents=saved.MapPathPercents or {}
local mapPlacementSides=saved.MapPlacementSides or {}
local mapPlacementAnchors=saved.MapPlacementAnchors or {}
local function identifyMap()
    local mc=WS:FindFirstChild("_MAP_CONFIG")
    if mc then
        for _,name in ipairs({"MapId","MapID","MapName","LevelId","LevelID","LevelName","Map","Level"}) do
            local v=mc:FindFirstChild(name)
            local raw=(v and v:IsA("ValueBase") and v.Value) or mc:GetAttribute(name)
            if (type(raw)=="string" and raw~="" and raw~="nil") or (type(raw)=="number" and raw>0) then
                return "map:"..tostring(game.PlaceId)..":"..name..":"..tostring(raw)
            end
        end
    end
    local road=WS:FindFirstChild("_road")
    if not road or not WS:FindFirstChild("_MAP_CONFIG") then return nil end
    local points={}
    for _,part in ipairs(road:GetDescendants()) do
        if part:IsA("BasePart") and (tonumber(part.Name) or part.Name:lower()=="main") then
            local p=part.Position
            table.insert(points,string.format("%.0f,%.0f,%.0f",p.X,p.Y,p.Z))
        end
    end
    if #points<2 then return nil end
    -- Prefer a stable explicit map identifier; geometry hashing is only a fallback.
    table.sort(points)
    local hash=2166136261
    for _,point in ipairs(points) do
        for i=1,#point do
            hash=bit32.bxor(hash,string.byte(point,i))
            hash=(hash*16777619)%4294967296
        end
    end
    return string.format("road:%d:%d:%08x",game.PlaceId,#points,hash)
end
local function applyMapPathPercent()
    local key=identifyMap()
    if not key then return nil end
    if cfg.CurrentMapKey~=key then
        cfg.CurrentMapKey=key
        cfg.PathPercent=math.clamp(tonumber(mapPathPercents[key]) or 50,0,100)
        cfg.PlacementSide=mapPlacementSides[key] or "CENTER"
        if type(override.PathPercent)=="number" then cfg.PathPercent=math.clamp(override.PathPercent,0,100) end
    end
    return key
end
applyMapPathPercent()
local app={Running=false,Cancelled=false,Config=cfg,LastResult=nil,Placed={},Connections={},PreviewFolder=nil}
env.AAAutoPlace=app
app.Version=SCRIPT_VERSION
print("[AAAutoPlay] VERSION",SCRIPT_VERSION)
local function log(...) print("[AAAutoPlace]",...) end
requireModule("Core.SettingsPersistence")({
    app=app,cfg=cfg,env=env,persistKeys=persistKeys,
    applyMapPathPercent=applyMapPathPercent,
    mapPathPercents=mapPathPercents,mapPlacementSides=mapPlacementSides,
    mapPlacementAnchors=mapPlacementAnchors,HttpService=HttpService,
    settingsPath=settingsPath,log=log,
})
local function statusText(msg)
    msg=tostring(msg)
    if app.CurrentStatus==msg then return end -- avoid repeated console/UI updates
    app.CurrentStatus=msg
    log(msg)
    if app.StatusLabel and app.StatusLabel.Parent then app.StatusLabel.Text=msg end
    if app.StatusParagraph then pcall(function() app.StatusParagraph:SetDesc(app.CurrentStatus) end) end
end
local function getSlotUuid(n)
    local ui=player:FindFirstChild("PlayerGui")
    local group=ui and ui:FindFirstChild("spawn_units")
    local slot=group and group:FindFirstChild(tostring(n),true)
    return slot and slot:GetAttribute("_equipped_frame_unit_uuid") or nil
end
local function waitSlotUuid(n,timeoutSeconds)
    local started=os.clock()
    local nextReport=0
    repeat
        if app.Cancelled then return nil end
        local gui=player:FindFirstChild("PlayerGui")
        local group=gui and gui:FindFirstChild("spawn_units")
        if gui and not group then group=gui:WaitForChild("spawn_units",0.5) end
        local slot=group and group:FindFirstChild(tostring(n),true)
        local uuid=slot and slot:GetAttribute("_equipped_frame_unit_uuid")
        if type(uuid)=="string" and uuid~="" then return uuid end
        if os.clock()>=nextReport then
            statusText("Waiting for UUID: Slot "..n.." ("..math.floor(os.clock()-started).."s) | Stop to cancel")
            nextReport=os.clock()+3
        end
        task.wait(0.2)
    until app.Cancelled
    return nil
end
local PlacementVerifier = requireModule("Core.PlacementVerifier")(cfg,player)
local ownedSnapshot = PlacementVerifier.ownedSnapshot
local countOwnedByUuid = PlacementVerifier.countOwnedByUuid
local existingPositions = PlacementVerifier.existingPositions
local matchingNewUnit = PlacementVerifier.matchingNewUnit
function app:InspectRoad()
    log("ROAD INSPECT START", "PlaceId", game.PlaceId)
    local mapConfig=WS:FindFirstChild("_MAP_CONFIG")
    if mapConfig then
        for _,field in ipairs({"MapLoaded","IsLobby","Area","Level"}) do
            local obj=mapConfig:FindFirstChild(field)
            if obj and obj:IsA("ValueBase") then
                log("MAP",field,tostring(obj.Value))
            end
        end
    end
    local roads={}
    local direct=WS:FindFirstChild("_road")
    if direct then table.insert(roads,direct) end
    for _,obj in ipairs(WS:GetDescendants()) do
        if obj.Name:lower()=="_road" and obj~=direct then
            table.insert(roads,obj)
        end
    end
    log("ROAD CONTAINERS",#roads)
    if #roads==0 then
        warn("[AAAutoPlace] ROAD_NOT_FOUND: No _road container in Workspace descendants")
        local hints=0
        for _,obj in ipairs(WS:GetDescendants()) do
            local name=obj.Name:lower()
            if (name:find("road",1,true) or name:find("waypoint",1,true) or name:find("path",1,true))
                and hints<25 and not obj:IsDescendantOf(WS:FindFirstChild("_UNITS") or WS.Terrain) then
                log("ROAD HINT",obj:GetFullName(),obj.ClassName)
                hints+=1
            end
        end
        return false
    end
    for _,road in ipairs(roads) do
        local directNodes,recursiveNodes,numberedModels=0,0,0
        local names={}
        for _,child in ipairs(road:GetChildren()) do
            if child:IsA("BasePart") and tonumber(child.Name) then directNodes+=1 end
            if child:IsA("Model") and tonumber(child.Name) then numberedModels+=1 end
            if #names<24 then table.insert(names,child.Name.."("..child.ClassName..")") end
        end
        for _,node in ipairs(road:GetDescendants()) do
            if node:IsA("BasePart") and tonumber(node.Name) then recursiveNodes+=1 end
        end
        log("ROAD",road:GetFullName(),"class",road.ClassName,"children",#road:GetChildren(),
            "direct-numbered-parts",directNodes,"nested-numbered-parts",recursiveNodes,
            "numbered-models",numberedModels)
        log("ROAD CHILDREN",table.concat(names,", "))
        if recursiveNodes<2 then
            warn("[AAAutoPlace] ROAD_FORMAT_UNSUPPORTED:",road:GetFullName(),
                "Expected at least 2 numeric-named BaseParts (direct or nested)")
        elseif directNodes<2 then
            log("ROAD FORMAT",road:GetFullName(),"nested numbered waypoints detected")
        end
    end
    return true
end
local RoadDetector = requireModule("Core.RoadDetector")(WS)
local lanePoints = RoadDetector.lanePoints
local lanePosition = RoadDetector.lanePosition
local distanceToLaneXZ = RoadDetector.distanceToLaneXZ
local function pathMidpoint(percentOverride)
    local position,err,count,length,fromNode,toNode=lanePosition(percentOverride or cfg.PathPercent)
    if position then return position,err,count,length,fromNode,toNode end
    -- Legacy _road fallback for maps without a usable Lane 1.
    applyMapPathPercent()
    -- Match InspectRoad: road may live under a nested map container.
    local road=WS:FindFirstChild("_road")
    if not road then
        local candidates={}
        for _,obj in ipairs(WS:GetDescendants()) do
            if obj.Name:lower()=="_road" and (obj:IsA("Folder") or obj:IsA("Model")) then
                table.insert(candidates,obj)
            end
        end
        if #candidates==1 then
            road=candidates[1]
            log("ROAD NESTED CONTAINER",road:GetFullName())
        elseif #candidates>1 then
            return nil,"multiple _road containers; inspect map before selecting"
        else
            return nil,"_road missing in Workspace descendants"
        end
    end
    -- Some maps store numbered road nodes under _road.new (or another nested Model).
    -- Prefer direct nodes for legacy maps, otherwise inspect nested descendants.
    local function collect(container,recursive)
        local found={}
        local source=recursive and container:GetDescendants() or container:GetChildren()
        for _,part in ipairs(source) do
            local index=tonumber(part.Name)
            if index and part:IsA("BasePart") then
                table.insert(found,{Index=index,Position=part.Position,Path=part:GetFullName()})
            end
        end
        return found
    end
    -- Choose the connected road group nearest the enemy spawn, not the largest "main" group.
    local nodes={}
    local bases=WS:FindFirstChild("_BASES")
    local pve=bases and bases:FindFirstChild("pve")
    local lanes=pve and pve:FindFirstChild("LANES")
    local spawnParts={}
    if lanes then
        for _,lane in ipairs(lanes:GetChildren()) do
            local spawn=lane:FindFirstChild("spawn")
            if spawn and spawn:IsA("BasePart") then table.insert(spawnParts,spawn) end
        end
    end
    if #spawnParts>0 then
        local groups={}
        local function addGroup(parts,label)
            if #parts<2 then return end
            local remaining=table.clone(parts)
            local ordered={}
            local previous=nil
            local bestStart,bestSpawnDist=nil,math.huge
            for _,part in ipairs(remaining) do
                for _,spawn in ipairs(spawnParts) do
                    local d=(part.Position-spawn.Position).Magnitude
                    if d<bestSpawnDist then bestStart,bestSpawnDist=part,d end
                end
            end
            if not bestStart then return end
            previous=bestStart.Position
            table.insert(ordered,bestStart)
            for i,part in ipairs(remaining) do if part==bestStart then table.remove(remaining,i);break end end
            local maxJump=0
            while #remaining>0 do
                local selected,closest=1,math.huge
                for i,part in ipairs(remaining) do
                    local d=(part.Position-previous).Magnitude
                    if d<closest then selected,closest=i,d end
                end
                maxJump=math.max(maxJump,closest)
                local part=table.remove(remaining,selected)
                table.insert(ordered,part)
                previous=part.Position
            end
            -- A group with disconnected pieces is not a dependable path.
            if maxJump>60 then return end
            table.insert(groups,{Parts=ordered,Name=label,Distance=bestSpawnDist,Jump=maxJump})
        end
        local function collectMain(container)
            local parts={}
            for _,part in ipairs(container:GetChildren()) do
                if part:IsA("BasePart") and part.Name:lower()=="main" then table.insert(parts,part) end
            end
            return parts
        end
        addGroup(collectMain(road),road:GetFullName())
        for _,child in ipairs(road:GetDescendants()) do
            if child:IsA("Folder") or child:IsA("Model") then
                addGroup(collectMain(child),child:GetFullName())
            end
        end
        table.sort(groups,function(a,b)
            if math.abs(a.Distance-b.Distance)>1 then return a.Distance<b.Distance end
            if a.Jump~=b.Jump then return a.Jump<b.Jump end
            return a.Name<b.Name
        end)
        if #groups>0 then
            local chosen=groups[1]
            -- Avoid selecting a nearby decorative route when equally plausible paths exist.
            if #groups==1 or groups[2].Distance-chosen.Distance>3 then
                for i,part in ipairs(chosen.Parts) do
                    table.insert(nodes,{Index=i,Position=part.Position,Path=part:GetFullName()})
                end
                log("ROAD SPAWN-ANCHORED",chosen.Name,"nodes",#nodes,"spawn distance",chosen.Distance,"max jump",chosen.Jump)
            else
                return nil,"ambiguous road groups near enemy spawn; set manual center"
            end
        end
    end
    if #spawnParts>0 and #nodes<2 then return nil,"no continuous main road group near enemy spawn; set manual center" end
    if #nodes<2 then nodes=collect(road,false) end
    -- Fallback for maps whose road pieces are all named "main" rather than 1,2,3...
    if #nodes<2 then
        local parts={}
        for _,part in ipairs(road:GetChildren()) do
            if part:IsA("BasePart") and part.Name:lower()=="main" then
                table.insert(parts,part)
            end
        end
        if #parts>=2 then
            local bases=WS:FindFirstChild("_BASES")
            local pve=bases and bases:FindFirstChild("pve")
            local lanes=pve and pve:FindFirstChild("LANES")
            local lane=lanes and (lanes:FindFirstChild("1") or lanes:GetChildren()[1])
            local spawn=lane and lane:FindFirstChild("spawn")
            if not spawn or not spawn:IsA("BasePart") then
                return nil,"unnumbered road pieces but enemy spawn unavailable"
            end
            local orderedParts={}
            local remaining=table.clone(parts)
            local previous=spawn.Position
            while #remaining>0 do
                local closest,bestIndex,bestDistance=nil,nil,math.huge
                for i,part in ipairs(remaining) do
                    local distance=(part.Position-previous).Magnitude
                    if distance<bestDistance then
                        closest,bestIndex,bestDistance=part,i,distance
                    end
                end
                if #orderedParts>0 and bestDistance>60 then
                    return nil,"unnumbered road has disconnected segments ("..tostring(math.floor(bestDistance)).." studs)"
                end
                table.insert(orderedParts,{Index=#orderedParts+1,Position=closest.Position,Path=closest:GetFullName()})
                previous=closest.Position
                table.remove(remaining,bestIndex)
            end
            nodes=orderedParts
            log("ROAD UNNUMBERED FALLBACK","pieces",#nodes,"nearest-neighbor from spawn")
        end
    end
    if #nodes<2 then
        local groups={}
        for _,child in ipairs(road:GetChildren()) do
            if child:IsA("Model") or child:IsA("Folder") then
                local candidate=collect(child,true)
                if #candidate>=2 then table.insert(groups,{Name=child.Name,Nodes=candidate}) end
            end
        end
        if #groups==1 then
            nodes=groups[1].Nodes
            log("ROAD GROUP SELECTED",groups[1].Name,"nodes",#nodes)
        elseif #groups>1 then
            local bases=WS:FindFirstChild("_BASES")
            local pve=bases and bases:FindFirstChild("pve")
            local lanes=pve and pve:FindFirstChild("LANES")
            local lane=lanes and (lanes:FindFirstChild("1") or lanes:GetChildren()[1])
            local spawn=lane and lane:FindFirstChild("spawn")
            if not spawn or not spawn:IsA("BasePart") then
                return nil,"multiple road groups but Lane 1 spawn unavailable"
            end
            local chosen,best=nil,math.huge
            for _,group in ipairs(groups) do
                local distance=math.huge
                for _,node in ipairs(group.Nodes) do
                    distance=math.min(distance,(node.Position-spawn.Position).Magnitude)
                end
                if distance<best then chosen,best=group,distance end
            end
            nodes=chosen.Nodes
            log("ROAD GROUP SELECTED FOR LANE 1",chosen.Name,"nodes",#nodes,"spawn distance",best)
        else
            nodes=collect(road,true)
            if #nodes>=2 then log("ROAD NESTED NODES",#nodes) end
        end
    end
    if #nodes<2 then return nil,"not enough numbered road parts (including nested)" end
    -- Maps may name every direct road node "10". Treat these as an unnumbered path,
    -- otherwise the duplicate-index permutation guard rejects more than 6 nodes.
    if #nodes>6 then
        local sameIndex=true
        for i=2,#nodes do
            if nodes[i].Index~=nodes[1].Index then sameIndex=false;break end
        end
        if sameIndex then
            local bases=WS:FindFirstChild("_BASES")
            local pve=bases and bases:FindFirstChild("pve")
            local lanes=pve and pve:FindFirstChild("LANES")
            local lane=lanes and (lanes:FindFirstChild("1") or lanes:GetChildren()[1])
            local spawn=lane and lane:FindFirstChild("spawn")
            if not spawn or not spawn:IsA("BasePart") then
                return nil,"duplicate-index road but Lane 1 spawn missing"
            end
            local remaining=table.clone(nodes)
            local orderedNodes={}
            local previous=spawn.Position
            while #remaining>0 do
                local bestIndex,bestDistance=1,math.huge
                for i,node in ipairs(remaining) do
                    local distance=(node.Position-previous).Magnitude
                    if distance<bestDistance then bestIndex,bestDistance=i,distance end
                end
                local node=table.remove(remaining,bestIndex)
                node.Index=#orderedNodes+1
                table.insert(orderedNodes,node)
                previous=node.Position
            end
            nodes=orderedNodes
            log("ROAD REPEATED INDEX FALLBACK","nodes",#nodes,"ordered from Lane 1 spawn")
        end
    end
    -- Some AA maps reuse waypoint numbers (e.g. 4, 12, 14) for intermediate turns.
    -- Keep every waypoint and choose the shortest local traversal for equal indices.
    table.sort(nodes,function(a,b)
        if a.Index~=b.Index then return a.Index<b.Index end
        return a.Path<b.Path
    end)
    local ordered={}
    local i=1
    while i<=#nodes do
        local j=i
        while j<#nodes and nodes[j+1].Index==nodes[i].Index do j+=1 end
        if j==i then
            table.insert(ordered,nodes[i])
        else
            local group={}
            for k=i,j do table.insert(group,nodes[k]) end
            if #group>6 then return nil,"too many duplicate nodes at index "..tostring(nodes[i].Index) end
            local preceding=ordered[#ordered]
            local following=nodes[j+1]
            local best,bestDistance=nil,math.huge
            local function permute(path,remaining,distance)
                if #remaining==0 then
                    local finish=distance
                    if following then finish+=(following.Position-path[#path].Position).Magnitude end
                    if finish<bestDistance then
                        bestDistance=finish
                        best=table.clone(path)
                    end
                    return
                end
                for k,node in ipairs(remaining) do
                    local last=path[#path] or preceding
                    local segment=last and (node.Position-last.Position).Magnitude or 0
                    local rest=table.clone(remaining)
                    table.remove(rest,k)
                    table.insert(path,node)
                    permute(path,rest,distance+segment)
                    table.remove(path)
                end
            end
            permute({},group,0)
            for _,node in ipairs(best) do table.insert(ordered,node) end
            log("ROAD DUPLICATE INDEX",nodes[i].Index,"waypoints",#group,"ordered by distance")
        end
        i=j+1
    end
    nodes=ordered
    -- Orient the route by the actual enemy spawn, independent of waypoint numbering.
    local bases=WS:FindFirstChild("_BASES")
    local pve=bases and bases:FindFirstChild("pve")
    local lanes=pve and pve:FindFirstChild("LANES")
    local spawns={}
    if lanes then
        for _,lane in ipairs(lanes:GetChildren()) do
            local spawn=lane:FindFirstChild("spawn")
            if spawn and spawn:IsA("BasePart") then table.insert(spawns,spawn) end
        end
    end
    if #spawns>0 then
        local first,last=nodes[1].Position,nodes[#nodes].Position
        local startDistance,endDistance=math.huge,math.huge
        for _,spawn in ipairs(spawns) do
            startDistance=math.min(startDistance,(spawn.Position-first).Magnitude)
            endDistance=math.min(endDistance,(spawn.Position-last).Magnitude)
        end
        if endDistance<startDistance then
            local reversed={}
            for k=#nodes,1,-1 do table.insert(reversed,nodes[k]) end
            nodes=reversed
            log("ROAD DIRECTION","REVERSED","spawn distance",endDistance,"vs",startDistance)
        else
            log("ROAD DIRECTION","FORWARD","spawn distance",startDistance,"vs",endDistance)
        end
    else
        warn("[AAAutoPlace] Enemy spawn not found; waypoint order fallback")
    end
    local length=0
    for i=1,#nodes-1 do
        length+=(nodes[i+1].Position-nodes[i].Position).Magnitude
    end
    if length<=0 then return nil,"road path has zero length" end
    local percent=math.clamp(tonumber(percentOverride) or tonumber(cfg.PathPercent) or 50,0,100)
    local target=length*(percent/100)
    local traveled=0
    for i=1,#nodes-1 do
        local a,b=nodes[i],nodes[i+1]
        local segment=(b.Position-a.Position).Magnitude
        if segment>0 and traveled+segment>=target then
            local result=a.Position:Lerp(b.Position,(target-traveled)/segment)
            return result,nil,#nodes,length,a.Index,b.Index
        end
        traveled+=segment
    end
    if target>=length then
        local last=nodes[#nodes]
        return last.Position,nil,#nodes,length,nodes[#nodes-1].Index,last.Index
    end
    return nil,"path position calculation failed"
end
local function savedPlacementAnchor()
    local coords=cfg.CurrentMapKey and mapPlacementAnchors[cfg.CurrentMapKey]
    if type(coords)=="table" and #coords==3 then return Vector3.new(coords[1],coords[2],coords[3]) end
    return nil
end
local function centerPosition()
    local manual=savedPlacementAnchor()
    if manual then return manual end
    if cfg.CenterMode=="PATH_MIDPOINT" then
        local position,err,count,length,fromNode,toNode=pathMidpoint()
        if position then
            log("PATH_POSITION",cfg.PathPercent.."%",position,"nodes",count,"length",length,"segment",fromNode,toNode)
        else
            warn("[AAAutoPlace] PATH_MIDPOINT unavailable:",err)
            app:InspectRoad()
        end
        return position
    end
    if cfg.CenterMode=="POSITION" then
        return typeof(cfg.CenterPosition)=="Vector3" and cfg.CenterPosition or nil
    elseif cfg.CenterMode=="PLAYER" then
        local root=player.Character and player.Character:FindFirstChild("HumanoidRootPart")
        return root and root.Position or nil
    end
    local mouse=player:GetMouse()
    return mouse and mouse.Hit and mouse.Hit.Position or nil
end
local PlacementEngine = requireModule("Core.PlacementEngine")({
    cfg=cfg, WS=WS, player=player,
    savedPlacementAnchor=savedPlacementAnchor,
    pathMidpoint=pathMidpoint,
    distanceToLaneXZ=distanceToLaneXZ,
})
local offsets = PlacementEngine.offsets
local slowAnchorPercent = PlacementEngine.slowAnchorPercent
local unitPlacementCandidates = PlacementEngine.unitPlacementCandidates
local findGround = PlacementEngine.findGround
local farEnough = PlacementEngine.farEnough
function app:ClearPreview()
    if self.PreviewFolder then self.PreviewFolder:Destroy();self.PreviewFolder=nil end
end
local function previewPoint(parent,pos,color,size,name)
    local part=Instance.new("Part")
    part.Name=name
    part.Shape=Enum.PartType.Ball
    part.Size=Vector3.new(size,size,size)
    part.Position=pos+Vector3.new(0,2,0)
    part.Anchored=true
    part.CanCollide=false
    part.CanTouch=false
    part.CanQuery=false
    part.Material=Enum.Material.Neon
    part.Color=color
    part.Parent=parent
    return part
end
function app:ShowPreview(center,offsetsList)
    self:ClearPreview()
    if not cfg.ShowPreview then return 0 end
    local folder=Instance.new("Folder")
    folder.Name="AAAutoPlacePreview"
    folder.Parent=WS
    self.PreviewFolder=folder
    local centerPart=previewPoint(folder,center,Color3.fromRGB(35,255,95),5,"PATH_MIDPOINT")
    local billboard=Instance.new("BillboardGui")
    billboard.Size=UDim2.fromOffset(180,36)
    billboard.StudsOffset=Vector3.new(0,4,0)
    billboard.AlwaysOnTop=true
    billboard.Parent=centerPart
    local label=Instance.new("TextLabel")
    label.Size=UDim2.fromScale(1,1)
    label.BackgroundTransparency=1
    label.Text="PATH "..tostring(math.clamp(tonumber(cfg.PathPercent) or 50,0,100)).."%"
    label.TextColor3=Color3.new(1,1,1)
    label.TextStrokeTransparency=0
    label.TextScaled=true
    label.Parent=billboard
    local total,shown=0,0
    local limit=math.clamp(math.floor(tonumber(cfg.MaxPreviewMarkers) or 100),0,300)
    for _,o in ipairs(offsetsList) do
        local pos=findGround(center,o)
        if pos then
            total+=1
            if shown<limit then
                previewPoint(folder,pos,Color3.fromRGB(40,155,255),1.25,"CANDIDATE")
                shown+=1
            end
        end
    end
    log("Preview markers",shown,"ground candidates",total)
    return total
end
function app:ShowTypePreview()
    if not cfg.ShowPreview or not self.PreviewFolder then return end
    local seen={}
    local shown=0
    for slot=1,6 do
        local kind=cfg.UnitTypes[slot] or "Damage"
        local count=math.clamp(math.floor(tonumber(cfg.Slots[slot]) or 0),0,10)
        if count>0 and (kind=="Slow" or kind=="Farm") then
            local percents={}
            if kind=="Slow" then
                for i=0,count-1 do table.insert(percents,slowAnchorPercent(i)) end
            else
                local base=math.clamp(tonumber(cfg.PathPercent) or 50,0,100)
                percents={base-10,base+10}
            end
            for _,p in ipairs(percents) do
                local percent=math.clamp(p,0,100)
                local key=kind..":"..percent
                if not seen[key] then
                    seen[key]=true
                    local anchor=pathMidpoint(percent)
                    if anchor then
                        local marker=previewPoint(self.PreviewFolder,anchor,
                            kind=="Slow" and Color3.fromRGB(255,160,40) or Color3.fromRGB(245,70,190),
                            2,kind.."_ANCHOR_"..tostring(percent))
                        local billboard=Instance.new("BillboardGui")
                        billboard.Size=UDim2.fromOffset(100,28)
                        billboard.StudsOffset=Vector3.new(0,3,0)
                        billboard.AlwaysOnTop=true
                        billboard.Parent=marker
                        local label=Instance.new("TextLabel")
                        label.Size=UDim2.fromScale(1,1)
                        label.BackgroundTransparency=1
                        label.Text=kind.." "..tostring(percent).."%"
                        label.TextColor3=Color3.new(1,1,1)
                        label.TextStrokeTransparency=0
                        label.TextScaled=true
                        label.Parent=billboard
                        shown+=1
                    end
                end
            end
        end
    end
    log("Type preview anchors",shown)
end
-- Visualize the exact Slow candidate generation without issuing spawn requests.
function app:ClearSlowPreview()
    local old=WS:FindFirstChild("AAAutoPlaceSlowPreview")
    if old then old:Destroy() end
end
function app:RefreshSlowPreview()
    self:ClearSlowPreview()
    if not cfg.ShowSlowPreview then return end
    local center=centerPosition()
    if not center then warn("[AAAutoPlay] Slow preview: center unavailable");return end
    local folder=Instance.new("Folder")
    folder.Name="AAAutoPlaceSlowPreview"
    folder.Parent=WS
    local offsetsList=offsets()
    local drawn=0
    for slot=1,6 do
        if cfg.UnitTypes[slot]=="Slow" then
            local target=math.clamp(math.floor(tonumber(cfg.Slots[slot]) or 0),0,10)
            if target>0 then
                local candidates=unitPlacementCandidates("Slow",0,target,center,offsetsList)
                if candidates then
                    local perOrdinal={}
                    local anchors={}
                    for _,candidate in ipairs(candidates) do
                        local ordinal=candidate.Ordinal
                        if not anchors[ordinal] then
                            anchors[ordinal]=true
                            local anchor=previewPoint(folder,candidate.Center,Color3.fromRGB(255,165,25),1.9,"Slow_Anchor_"..slot.."_"..ordinal)
                            local gui=Instance.new("BillboardGui")
                            gui.Size=UDim2.fromOffset(120,28);gui.StudsOffsetWorldSpace=Vector3.new(0,2.7,0)
                            gui.AlwaysOnTop=true;gui.MaxDistance=500;gui.Parent=anchor
                            local label=Instance.new("TextLabel")
                            label.Size=UDim2.fromScale(1,1);label.BackgroundTransparency=1
                            label.TextColor3=Color3.new(1,1,1);label.TextStrokeTransparency=0;label.TextScaled=true
                            label.Text="Slot "..slot.." Slow "..ordinal..(candidate.Percent and (" ("..candidate.Percent.."%)") or "")
                            label.Parent=gui
                        end
                        local count=perOrdinal[ordinal] or 0
                        if count<40 then
                            local pos=findGround(candidate.Center,candidate.Offset)
                            if pos then
                                perOrdinal[ordinal]=count+1
                                previewPoint(folder,pos,Color3.fromRGB(100,235,255),0.85,"Slow_Candidate_"..slot.."_"..ordinal.."_"..(count+1))
                                drawn+=1
                            end
                        end
                    end
                end
            end
        end
    end
    log("SLOW PREVIEW",drawn,"ground candidates (up to 40 per Slow anchor)")
end
function app:ClearRoadPreview()
    local folder=WS:FindFirstChild("AAAutoPlaceRoadPreview")
    if folder then folder:Destroy() end
end
function app:RefreshRoadPreview()
    self:ClearRoadPreview()
    if not cfg.ShowRoadPreview then return end
    local points=lanePoints()
    if not points then warn("[AAAutoPlay] Road preview: Lane 1 unavailable");return end
    local folder=Instance.new("Folder")
    folder.Name="AAAutoPlaceRoadPreview"
    folder.Parent=WS
    local width=math.clamp(tonumber(cfg.RoadHalfWidth) or 1,0.25,8)
    local function marker(name,cf,size,color,alpha)
        local p=Instance.new("Part")
        p.Name=name;p.Anchored=true;p.CanCollide=false;p.CanTouch=false;p.CanQuery=false;p.CastShadow=false
        p.Material=Enum.Material.Neon;p.Color=color;p.Transparency=alpha;p.Size=size;p.CFrame=cf;p.Parent=folder
        return p
    end
    for i=1,#points-1 do
        local a=points[i].Position+Vector3.new(0,0.55,0)
        local b=points[i+1].Position+Vector3.new(0,0.55,0)
        local length=(b-a).Magnitude
        if length>0.1 then
            local cf=CFrame.lookAt((a+b)/2,b)
            marker("Corridor_"..i,cf,Vector3.new(width*2,0.1,length),Color3.fromRGB(255,175,20),0.72)
            marker("Center_"..i,cf,Vector3.new(0.15,0.16,length),Color3.fromRGB(0,235,255),0.05)
        end
    end
    for i,item in ipairs(points) do
        local p=marker("Waypoint_"..tostring(item.Index),CFrame.new(item.Position+Vector3.new(0,1.1,0)),Vector3.new(0.9,0.9,0.9),
            i==1 and Color3.fromRGB(40,255,90) or i==#points and Color3.fromRGB(255,50,100) or Color3.fromRGB(30,115,255),0)
        p.Shape=Enum.PartType.Ball
        local gui=Instance.new("BillboardGui")
        gui.Size=UDim2.fromOffset(64,24);gui.StudsOffsetWorldSpace=Vector3.new(0,2,0);gui.AlwaysOnTop=true;gui.MaxDistance=400;gui.Parent=p
        local text=Instance.new("TextLabel")
        text.Size=UDim2.fromScale(1,1);text.BackgroundTransparency=1;text.TextColor3=Color3.new(1,1,1)
        text.TextStrokeTransparency=0;text.TextScaled=true;text.Text=tostring(item.Index);text.Parent=gui
    end
    log("ROAD PREVIEW",#points,"waypoints","half width",width)
end
function app:SetPreview(enabled)
    cfg.ShowPreview=enabled and true or false
    if not cfg.ShowPreview then self:ClearPreview()
    elseif not self.Running then self:RefreshPreview() end
end
function app:RefreshPreview()
    local center=centerPosition()
    if not center then statusText("Preview: center unavailable");return 0 end
    local count=self:ShowPreview(center,offsets())
    self:ShowTypePreview()
    statusText("Preview: "..count.." ground points")
    return count
end
function app:Stop()
    self:ClearPreview()
    self.Cancelled=true
    statusText("Stopped (in-flight request may finish)")
end
function app:Destroy()
    self:ClearSlowPreview()
    self:ClearRoadPreview()
    if self.AutoBuff then self.AutoBuff.StopAll() end
    if self.SaveSettings then pcall(function() self:SaveSettings() end) end
    if self.ControllerStop then self.ControllerStop() else self:Stop() end
    for _,conn in ipairs(self.Connections) do conn:Disconnect() end
    if self.Gui then self.Gui:Destroy() end
    if self.RayfieldWindow then pcall(function() self.RayfieldWindow:Unload() end) end
    if self.WindUIWindow then pcall(function() self.WindUIWindow:Destroy() end) end
end
-- Resolve the placement cost from the equipped unit's visual model.
-- Unknown gameplay variants are not guessed; only cosmetic suffixes are removed.
local placementData=nil
local placementDataOK,placementDefinitions=pcall(function()
    return require(RS.src.Data.Units)
end)
if placementDataOK and type(placementDefinitions)=="table" then placementData=placementDefinitions end
local function placementPrice(slotNumber)
    local gui=player:FindFirstChild("PlayerGui")
    local group=gui and gui:FindFirstChild("spawn_units")
    local frame=group and group:FindFirstChild(tostring(slotNumber),true)
    local world=frame and frame:FindFirstChild("WorldModel",true)
    local model=world and world:FindFirstChildOfClass("Model")
    local id=model and model.Name
    if not id or not placementData then return nil,id,"Unit data unavailable" end
    local definition=placementData[id]
    if not definition then
        local cosmeticBase=id:gsub(":shiny",""):gsub(":golden","")
        if cosmeticBase~=id then definition=placementData[cosmeticBase] end
        if not definition then
            local normalBase=cosmeticBase:gsub("_christmas$","")
            if normalBase~=cosmeticBase then definition=placementData[normalBase] end
        end
    end
    local base=definition and tonumber(definition.cost)
    if not base or base<0 then return nil,id,"Unknown placement cost" end
    local dataRoot=WS:FindFirstChild("_DATA")
    local modifiers=dataRoot and dataRoot:FindFirstChild("LevelModifiers")
    local scaleValue=modifiers and modifiers:FindFirstChild("player_cost_scale")
    local scale=scaleValue and tonumber(scaleValue.Value)
    if not scale or scale<0 then return nil,id,"Cost scale unavailable" end
    return math.ceil(base*scale),id,nil
end
local function placementMoney()
    local stats=player:FindFirstChild("_stats")
    local resource=stats and stats:FindFirstChild("resource")
    return resource and tonumber(resource.Value) or nil
end
function app:Run(activeWave)
    if self.Running then return end
    self.Running=true
    self.Cancelled=false
    self.Placed={}
    local result={placed=0,attempted=0,slots={},mode=cfg.Mode,completed=false}
    self.LastResult=result
    local center=centerPosition()
    if not center then statusText("No center found for "..tostring(cfg.CenterMode));self.Running=false;return end
    local offsetsList=offsets()
    local previewCount=self:ShowPreview(center,offsetsList)
    self:ShowTypePreview()
    local folder=WS:FindFirstChild("_UNITS")
    local ep=RS:FindFirstChild("endpoints")
    ep=ep and ep:FindFirstChild("client_to_server")
    local remote=ep and ep:FindFirstChild("spawn_unit")
    if not folder or not remote or not remote:IsA("RemoteFunction") then
        statusText("Missing _UNITS or spawn_unit");self.Running=false;return
    end
    if cfg.Mode~="LIVE" then
        result.candidates=previewCount
        statusText("PREVIEW: "..previewCount.." points; green center / blue candidates")
        self.Running=false
        return
    end
    if cfg.CountExistingUnits then self.Placed=existingPositions(folder) end
    local maxTotal=math.clamp(math.floor(tonumber(cfg.MaxTotalPlaced) or 12),1,50)
    local timeout=1 -- fixed maximum 1 second; do not use old persisted timeout
    local placementOrder={1,2,3,4,5,6}
    table.sort(placementOrder,function(a,b)
        local pa=math.clamp(math.floor(tonumber(cfg.UnitPriority[a]) or a),1,6)
        local pb=math.clamp(math.floor(tonumber(cfg.UnitPriority[b]) or b),1,6)
        if pa==pb then return a<b end
        return pa<pb
    end)
    log("Placement order",table.concat(placementOrder,","))
    for _,slotNumber in ipairs(placementOrder) do
        if self.Cancelled or result.resourcePause or result.placed>=maxTotal then break end
        local want=math.clamp(math.floor(tonumber(cfg.Slots[slotNumber]) or 0),0,10)
        local slotResult={requested=want,placed=0,attempted=0,existing=0}
        result.slots[slotNumber]=slotResult
        if want>0 and (not activeWave or activeWave>=math.clamp(tonumber(cfg.StartWave[slotNumber]) or 1,1,100)) then
            local uuid=waitSlotUuid(slotNumber,cfg.UUIDWaitTimeout)
            if type(uuid)~="string" or uuid=="" then
                if self.Cancelled then break end
                warn("[AAAutoPlace] Slot",slotNumber,"has no equipped UUID")
            else
                slotResult.existing=cfg.CountExistingUnits and countOwnedByUuid(folder,uuid) or 0
                local required=math.max(0,want-slotResult.existing)
                local kind=cfg.UnitTypes[slotNumber] or "Damage"
                local candidates=unitPlacementCandidates(kind,slotResult.existing,required,center,offsetsList)
                if not candidates then
                    warn("[AAAutoPlay] No valid path anchors for",kind,"slot",slotNumber)
                    statusText("Skipping Slot "..slotNumber..": path anchor unavailable")
                    break
                end
                log("Slot target",slotNumber,"type",kind,"target",want,"existing",slotResult.existing,"needed",required)
                for _,candidate in ipairs(candidates) do
                    -- Recheck actual units before another request, including late spawns.
                    if cfg.CountExistingUnits and countOwnedByUuid(folder,uuid)>=want then break end
                    if self.Cancelled or slotResult.placed>=required
                        or result.placed>=maxTotal then break end
                    local pos
                    if candidate.Ordinal==0 or candidate.Ordinal==slotResult.placed+1 then
                        pos=findGround(candidate.Center,candidate.Offset)
                    end
                    if pos and farEnough(pos,self.Placed) then
                        local price,unitId,reason=placementPrice(slotNumber)
                        local money=placementMoney()
                        if price==nil then
                            statusText("Slot "..slotNumber.." | "..tostring(unitId or "?").." | "..tostring(reason).." - waiting")
                            break -- No price: do not guess, retry on the next scheduler cycle.
                        elseif money==nil then
                            statusText("Slot "..slotNumber.." | Money unavailable - waiting")
                            break
                        elseif money<price then
                            statusText("Slot "..slotNumber.." | WAITING FOR MONEY "..math.floor(money).."/"..price)
                            break
                        end
                        local before=ownedSnapshot(folder)
                        slotResult.attempted+=1;result.attempted+=1
                        statusText("Placing Slot "..slotNumber.." ("..kind..") "..slotResult.placed.."/"..required.." | point "..slotResult.attempted.."/"..#candidates)
                        -- RemoteFunction invocation may yield; Stop prevents subsequent attempts.
                        local ok,reply=pcall(function()
                            return remote:InvokeServer(uuid,CFrame.new(pos))
                        end)
                        if not ok then warn("[AAAutoPlace] spawn_unit error:",reply) end
                        local spawned=nil
                        local deadline=os.clock()+timeout
                        repeat
                            spawned=matchingNewUnit(folder,before,uuid,pos)
                            if spawned or self.Cancelled then break end
                            task.wait(0.1)
                        until os.clock()>=deadline
                        if not spawned and not self.Cancelled then
                            statusText("Slot "..slotNumber.." not confirmed within 1s - trying next point")
                        end
                        if spawned then
                            slotResult.placed+=1;result.placed+=1
                            table.insert(self.Placed,pos)
                            statusText("Placed Slot "..slotNumber.." "..slotResult.placed.."/"..required)
                            log("CONFIRMED",slotNumber,spawned.Name,pos)
                        else
                            log("NOT CONFIRMED",slotNumber,pos,"reply",tostring(reply))
                        end
                        if self.Cancelled then break end
                        if not self.Cancelled then task.wait(0.5) end
                    end
                end
            end
        end
    end
    result.completed=not self.Cancelled
    for slot=1,6 do
        local target=math.clamp(math.floor(tonumber(cfg.Slots[slot]) or 0),0,10)
        local entry=result.slots[slot]
        if target>0 and (not activeWave or activeWave>=math.clamp(tonumber(cfg.StartWave[slot]) or 1,1,100)) and (not entry or entry.existing+entry.placed<target) then result.completed=false end
    end
    self.Running=false
    local outcome = result.resourcePause and "PAUSED (resource)" or (self.Cancelled and "STOPPED" or (result.completed and "PLACEMENT COMPLETE" or "PLACEMENT INCOMPLETE"))
    statusText(outcome.." "..result.placed.." placed / "..result.attempted.." attempts")
end
local function startRun()
    task.spawn(function()
        local ok,err=xpcall(function() app:Run() end,debug.traceback)
        if not ok then app.Running=false;warn("[AAAutoPlace] Fatal:",err);statusText("ERROR - see console") end
    end)
end

-- AutoUpgrade loaded from bundled module.
requireModule("Features.AutoUpgrade")()

-- AutoSkill from bundled module.
requireModule("Features.AutoSkill")(cfg)

local function upgradeApp() return env.AAAutoUpgrade end
if upgradeApp() then
    local uc=upgradeApp().Config
    local savedUpgrade=saved.Upgrade
    uc.Enabled=not (savedUpgrade and savedUpgrade.Enabled==false)
    for i=1,6 do
        if savedUpgrade and savedUpgrade.Slots then
            uc.Slots[i]=savedUpgrade.Slots[i]==true
        else
            uc.Slots[i]=(cfg.Slots[i] or 0)>0
        end
        uc.TargetLevel[i]=savedUpgrade and savedUpgrade.TargetLevel and savedUpgrade.TargetLevel[i] or -1
        uc.Priority[i]=cfg.UnitPriority[i] or i
    end
    uc.CostDiscounts=savedUpgrade and savedUpgrade.CostDiscounts or {}
    uc.ReserveMoney=savedUpgrade and savedUpgrade.ReserveMoney or 0
    uc.AllowLowerPriorityWhenUnaffordable=savedUpgrade and savedUpgrade.AllowLowerPriorityWhenUnaffordable or false
end
local function readCurrentWave()
    local gui=player:FindFirstChild("PlayerGui")
    local waves=gui and gui:FindFirstChild("Waves")
    local bar=waves and waves:FindFirstChild("HealthBar")
    local value=bar and bar:FindFirstChild("WaveNumber")
    local number=value and (value:IsA("ValueBase") and tonumber(value.Value) or (value:IsA("TextLabel") and tonumber(value.Text)))
    if number and number>=0 then return math.floor(number) end
    return nil
end
app.GetCurrentWave=readCurrentWave

local buffApp=requireModule("Features.AutoBuff")({env=env})
local function syncAutoBuff(enabled)
    for _,kind in ipairs({"erwin","wendy","leafa"}) do
        buffApp.SetEnabled(kind,enabled and cfg.Mode=="LIVE" and cfg.AutoBuffEnabled[kind]==true)
    end
end
app.AutoBuff=buffApp
local autoPlayRunning=false
local autoPlayCancelled=false
local schedulerGeneration=0
local startAutoPlay
startAutoPlay=function()
    if autoPlayRunning then return end
    schedulerGeneration+=1
    local myGeneration=schedulerGeneration
    autoPlayRunning=true
    autoPlayCancelled=false
    app.AutoPlayState="RUNNING"
    syncAutoBuff(true)
    local skillApp=env.AAAutoSkill
    if skillApp then skillApp.Slots=cfg.AutoSkillSlots;skillApp.Enabled=cfg.Mode=="LIVE" and table.find(cfg.AutoSkillSlots,true)~=nil;skillApp:Start() end
    task.spawn(function()
        local upgrade=upgradeApp()
        local lastPhase=""
        while not autoPlayCancelled and schedulerGeneration==myGeneration and env.AAAutoPlace==app do
            local wave=readCurrentWave()
            app.CurrentWave=wave
            if wave==nil then
                if upgrade and upgrade.Running then upgrade:Stop() end
                app.AutoPlayState="WAITING_FOR_WAVE"
                statusText("WAITING FOR WAVE DATA (Waves.HealthBar.WaveNumber)")
                task.wait(1)
            else
                local units=WS:FindFirstChild("_UNITS")
                local due=false
                local nextWave=nil
                for slot=1,6 do
                    local target=math.clamp(math.floor(tonumber(cfg.Slots[slot]) or 0),0,10)
                    if target>0 then
                        local startWave=math.clamp(math.floor(tonumber(cfg.StartWave[slot]) or 1),1,100)
                        if wave<startWave then
                            if not nextWave or startWave<nextWave then nextWave=startWave end
                        else
                            local uuid=getSlotUuid(slot)
                            if not uuid or not units or countOwnedByUuid(units,uuid)<target then due=true end
                        end
                    end
                end
                app.NextPlacementWave=nextWave
                if due then
                    app.AutoPlayState="PLACING"
                    if upgrade and upgrade.Running then upgrade:Stop() end
                    if lastPhase~="PLACE" then log("WAVE",wave,"phase PLACE") end
                    lastPhase="PLACE"
                    local ok,err=xpcall(function() app:Run(wave) end,debug.traceback)
                    if not ok then app.Running=false;warn("[AAAutoPlay] Placement error; retrying:",err) end
                    if not autoPlayCancelled then task.wait(0.5) end
                else
                    app.AutoPlayState="UPGRADING_OR_WAITING"
                    if lastPhase~="UPGRADE" then
                        log("WAVE",wave,"phase UPGRADE",nextWave and ("next slot unlock "..nextWave) or "all unlocked")
                    end
                    lastPhase="UPGRADE"
                    if cfg.Mode=="LIVE" and upgrade and upgrade.Config.Enabled then
                        if not upgrade.Running then
                            upgrade.Config.Mode="LIVE"
                            upgrade:Start()
                        end
                        statusText("Wave "..wave.." | all due units placed | AUTO UPGRADE"..(nextWave and (" | next placement Wave "..nextWave) or ""))
                    else
                        statusText("Wave "..wave.." | all due units placed | waiting"..(nextWave and (" for Wave "..nextWave) or ""))
                    end
                    task.wait(1)
                end
            end
        end
        if upgrade and upgrade.Running then upgrade:Stop() end
        autoPlayRunning=false
        app.AutoPlayState="STOPPED"
        if cfg.AutoPlayEnabled==true and schedulerGeneration~=myGeneration and env.AAAutoPlace==app then
            task.defer(startAutoPlay) -- restart only after old scheduler exits
        end
    end)
end
local function stopAutoPlay()
    app.AutoPlayState="STOPPED"
    schedulerGeneration+=1
    autoPlayCancelled=true
    app:Stop()
    syncAutoBuff(false)
    local skillApp=env.AAAutoSkill
    if skillApp then skillApp:Stop() end
    local upgrade=upgradeApp()
    if upgrade then upgrade:Stop() end
end

app.ControllerStop=stopAutoPlay

-- Native compact UI: independent from remote UI libraries.
local buildWindUI=requireModule("UI.MainWindow")({
    app=app,
    cfg=cfg,
    env=env,
    player=player,
    upgradeApp=upgradeApp,
    startAutoPlay=startAutoPlay,
    stopAutoPlay=stopAutoPlay,
    applyMapPathPercent=applyMapPathPercent,
    mapPathPercents=mapPathPercents,
    mapPlacementSides=mapPlacementSides,
    mapPlacementAnchors=mapPlacementAnchors,
    statusText=statusText,
    log=log,
    SCRIPT_VERSION=SCRIPT_VERSION,
    saved=saved,
    isAutoPlayRunning=function() return autoPlayRunning end,
    syncAutoBuff=syncAutoBuff,
})
local uiOk,uiErr=pcall(buildWindUI)
if not uiOk then warn("[AAAutoPlay] WindUI failed:",uiErr) end
log("Auto Play loaded; version",SCRIPT_VERSION,"mode",cfg.Mode,"slots",table.concat(cfg.Slots,","))
if cfg.ShowRoadPreview then task.defer(function() if env.AAAutoPlace==app then app:RefreshRoadPreview() end end) end
if cfg.ShowSlowPreview then task.defer(function() if env.AAAutoPlace==app then app:RefreshSlowPreview() end end) end
-- Auto-save watcher: tracks all persisted settings, per-stage path positions,
-- and embedded upgrade settings. Debounced to avoid writing every slider step.
local function settingsFingerprint()
    local data={}
    for _,key in ipairs(persistKeys) do data[key]=cfg[key] end
    data.MapPathPercents=mapPathPercents
    data.MapPlacementSides=mapPlacementSides
    data.MapPlacementAnchors=mapPlacementAnchors
    local upgrade=env.AAAutoUpgrade
    if upgrade and upgrade.Config then
        local uc=upgrade.Config
        data.Upgrade={
            Enabled=uc.Enabled,Slots=uc.Slots,TargetLevel=uc.TargetLevel,
            Priority=uc.Priority,CostDiscounts=uc.CostDiscounts,
            ReserveMoney=uc.ReserveMoney,
            AllowLowerPriorityWhenUnaffordable=uc.AllowLowerPriorityWhenUnaffordable,
        }
    end
    return HttpService:JSONEncode(data)
end
local originalFingerprint=settingsFingerprint()
task.spawn(function()
    local lastObserved=originalFingerprint
    local lastSaved=originalFingerprint
    local changedAt=nil
    while env.AAAutoPlace==app do
        local ok,fingerprint=pcall(settingsFingerprint)
        if ok then
            if fingerprint~=lastObserved then
                lastObserved=fingerprint
                changedAt=os.clock()
            end
            if changedAt and fingerprint~=lastSaved and os.clock()-changedAt>=1.5 then
                if app:SaveSettings() then
                    lastSaved=fingerprint
                    changedAt=nil
                    log("SETTINGS AUTO SAVED")
                else
                    changedAt=os.clock() -- retry later without spamming each tick
                end
            end
            if fingerprint==lastSaved then changedAt=nil end
        end
        task.wait(0.5)
    end
end)
if (cfg.AutoPlayEnabled==true or override.AutoStart==true) and cfg.Mode=="LIVE" then
    task.defer(function()
        app.AutoPlayState="WAITING_FOR_MAP"
        while env.AAAutoPlace==app and not app.Cancelled and (cfg.AutoPlayEnabled==true or override.AutoStart==true) do
            local map=WS:FindFirstChild("_MAP_CONFIG")
            local bases=WS:FindFirstChild("_BASES")
            local units=WS:FindFirstChild("_UNITS")
            local road=WS:FindFirstChild("_road",true)
            local endpoints=RS:FindFirstChild("endpoints")
            local client=endpoints and endpoints:FindFirstChild("client_to_server")
            local spawn=client and client:FindFirstChild("spawn_unit")
            if road and bases and units and spawn and spawn:IsA("RemoteFunction") and map then
                log("Auto Start: map ready; starting Sequential LIVE")
                startAutoPlay()
                return
            end
            task.wait(1)
        end
        warn("[AAAutoPlay] Auto Start skipped: map not ready within readiness checks")
    end)
end
if cfg.Mode~="LIVE" and cfg.AutoPreviewOnLoad then
    task.defer(function()
        local ok,err=xpcall(function() app:Run() end,debug.traceback)
        if not ok then app.Running=false;warn("[AAAutoPlace] Auto preview error:",err) end
    end)
end
