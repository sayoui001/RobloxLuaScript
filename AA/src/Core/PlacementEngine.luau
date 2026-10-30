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
