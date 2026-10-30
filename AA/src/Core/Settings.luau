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
