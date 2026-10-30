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
