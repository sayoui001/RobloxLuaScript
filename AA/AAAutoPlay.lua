-- AA AutoPlace Phase 1 | single-file, slots 1-6, bounded real placement
-- Default PREVIEW: only LIVE mode sends spawn_unit requests.
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
    Radius=12, GridStep=3, UnitSpacing=3,
    MaxAttemptsPerSlot=40, MaxTotalAttempts=120,
    VerifyTimeout=2, RetryDelay=0.45, ScanHeight=35,
    MaxHeightDifference=8, MinNormalY=0.85,
    Slots={0,0,0,0,1,0}, -- target total per slot
    UnitPriority={1,2,3,4,5,6}, -- lower number places first
    UnitTypes={"Damage","Damage","Damage","Damage","Damage","Damage"},
    MaxTotalPlaced=12,
    CountExistingUnits=true, LateVerifyTimeout=3,
    ShowPreview=true, AutoPreviewOnLoad=true, MaxPreviewMarkers=100,
    UILibrary="RayfieldGen2",
    Blacklist={elyssia_jellyfish=true,elyssia_eel=true},
}
-- Executor-local JSON settings. Never persist LIVE mode or a map-specific Vector3.
local HttpService=game:GetService("HttpService")
local settingsPath="AAAutoPlaceSettings.json"
local persistKeys={"CenterMode","PathPercent","Radius","GridStep","UnitSpacing","ShowPreview","Slots","UnitPriority","UnitTypes","MaxAttemptsPerSlot","MaxTotalAttempts","VerifyTimeout","RetryDelay","CountExistingUnits"}
local function readSettings()
    if type(readfile)~="function" then return {} end
    local ok,data=pcall(function() return HttpService:JSONDecode(readfile(settingsPath)) end)
    if not ok or type(data)~="table" then return {} end
    local safe={}
    for _,key in ipairs(persistKeys) do
        if key=="UnitTypes" then
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
local saved=readSettings()
local override=type(env.AAAutoPlaceConfig)=="table" and env.AAAutoPlaceConfig or {}
local cfg={}
for k,v in pairs(defaults) do
    if override[k]~=nil then cfg[k]=override[k]
    elseif saved[k]~=nil then cfg[k]=saved[k]
    else cfg[k]=v end
end
cfg.Mode=override.Mode=="PREVIEW" and "PREVIEW" or "LIVE"
local app={Running=false,Cancelled=false,Config=cfg,LastResult=nil,Placed={},Connections={},PreviewFolder=nil}
env.AAAutoPlace=app
local function log(...) print("[AAAutoPlace]",...) end
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
        elseif key=="UnitPriority" then
            data.UnitPriority={}
            for i=1,6 do data.UnitPriority[i]=math.clamp(math.floor(tonumber(cfg.UnitPriority[i]) or i),1,6) end
        elseif key=="Slots" then
            data.Slots={}
            for i=1,6 do data.Slots[i]=math.clamp(math.floor(tonumber(cfg.Slots[i]) or 0),0,10) end
        else data[key]=cfg[key] end
    end
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
local function statusText(msg) log(msg);if app.StatusLabel and app.StatusLabel.Parent then app.StatusLabel.Text=msg end end
local function getSlotUuid(n)
    local ui=player:FindFirstChild("PlayerGui")
    local group=ui and ui:FindFirstChild("spawn_units")
    local slot=group and group:FindFirstChild(tostring(n),true)
    return slot and slot:GetAttribute("_equipped_frame_unit_uuid") or nil
end
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
                    if distance<best and distance<=12 then closest,best=unit,distance end
                end
            end
        end
    end
    return closest
end
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
local function pathMidpoint(percentOverride)
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
    local nodes=collect(road,false)
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
            return nil,"multiple nested road groups; inspect before selecting"
        else
            nodes=collect(road,true)
            if #nodes>=2 then log("ROAD NESTED NODES",#nodes) end
        end
    end
    if #nodes<2 then return nil,"not enough numbered road parts (including nested)" end
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
local function centerPosition()
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
local function unitPlacementCandidates(kind,existing,required,mainCenter,offsetsList)
    local list={}
    if kind=="Slow" then
        for index=existing,existing+required-1 do
            local percent=math.min(100,index*10)
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
        local percents={base,base-5,base+5,base-10,base+10}
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
local function findGround(center,offset)
    local params=RaycastParams.new()
    params.FilterType=Enum.RaycastFilterType.Exclude
    local ignore={}
    if player.Character then table.insert(ignore,player.Character) end
    params.FilterDescendantsInstances=ignore
    local point=center+Vector3.new(offset.dx,0,offset.dz)
    local ray=WS:Raycast(point+Vector3.new(0,cfg.ScanHeight,0),Vector3.new(0,-(cfg.ScanHeight*2+20),0),params)
    if not ray or ray.Normal.Y<cfg.MinNormalY then return nil end
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
                for i=0,count-1 do table.insert(percents,i*10) end
            else
                local base=math.clamp(tonumber(cfg.PathPercent) or 50,0,100)
                percents={base-10,base-5,base,base+5,base+10}
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
    self:Stop()
    for _,conn in ipairs(self.Connections) do conn:Disconnect() end
    if self.Gui then self.Gui:Destroy() end
    if self.RayfieldWindow then pcall(function() self.RayfieldWindow:Unload() end) end
    if self.WindUIWindow then pcall(function() self.WindUIWindow:Destroy() end) end
end
function app:Run()
    if self.Running then return end
    self.Running=true
    self.Cancelled=false
    self.Placed={}
    local result={placed=0,attempted=0,slots={},mode=cfg.Mode,uncertain=false,completed=false}
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
    local maxAttempts=math.clamp(math.floor(tonumber(cfg.MaxTotalAttempts) or 120),1,300)
    local perSlot=math.clamp(math.floor(tonumber(cfg.MaxAttemptsPerSlot) or 40),1,100)
    local timeout=math.clamp(tonumber(cfg.VerifyTimeout) or 2,0.5,8)
    local placementOrder={1,2,3,4,5,6}
    table.sort(placementOrder,function(a,b)
        local pa=math.clamp(math.floor(tonumber(cfg.UnitPriority[a]) or a),1,6)
        local pb=math.clamp(math.floor(tonumber(cfg.UnitPriority[b]) or b),1,6)
        if pa==pb then return a<b end
        return pa<pb
    end)
    log("Placement order",table.concat(placementOrder,","))
    for _,slotNumber in ipairs(placementOrder) do
        if self.Cancelled or result.uncertain or result.resourcePause or result.placed>=maxTotal or result.attempted>=maxAttempts then break end
        local want=math.clamp(math.floor(tonumber(cfg.Slots[slotNumber]) or 0),0,10)
        local slotResult={requested=want,placed=0,attempted=0,existing=0}
        result.slots[slotNumber]=slotResult
        if want>0 then
            local uuid=getSlotUuid(slotNumber)
            if type(uuid)~="string" or uuid=="" then
                warn("[AAAutoPlace] Slot",slotNumber,"has no equipped UUID")
            else
                slotResult.existing=cfg.CountExistingUnits and countOwnedByUuid(folder,uuid) or 0
                local required=math.max(0,want-slotResult.existing)
                local kind=cfg.UnitTypes[slotNumber] or "Damage"
                local candidates=unitPlacementCandidates(kind,slotResult.existing,required,center,offsetsList)
                if not candidates then
                    warn("[AAAutoPlay] No valid path anchors for",kind,"slot",slotNumber)
                    result.uncertain=true
                    break
                end
                log("Slot target",slotNumber,"type",kind,"target",want,"existing",slotResult.existing,"needed",required)
                for _,candidate in ipairs(candidates) do
                    if self.Cancelled or slotResult.placed>=required or slotResult.attempted>=perSlot
                        or result.placed>=maxTotal or result.attempted>=maxAttempts then break end
                    local pos
                    if candidate.Ordinal==0 or candidate.Ordinal==slotResult.placed+1 then
                        pos=findGround(candidate.Center,candidate.Offset)
                    end
                    if pos and farEnough(pos,self.Placed) then
                        local before=ownedSnapshot(folder)
                        slotResult.attempted+=1;result.attempted+=1
                        statusText("Slot "..slotNumber.." attempt "..slotResult.attempted)
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
                        if not spawned and not self.Cancelled and ok and reply~=false then
                            local extra=math.clamp(tonumber(cfg.LateVerifyTimeout) or 3,0,10)
                            local lateDeadline=os.clock()+extra
                            repeat
                                spawned=matchingNewUnit(folder,before,uuid,pos)
                                if spawned or self.Cancelled then break end
                                task.wait(0.1)
                            until os.clock()>=lateDeadline
                            if not spawned and not self.Cancelled then
                                result.uncertain=true
                                warn("[AAAutoPlace] UNCERTAIN: server returned without confirmed spawn; retry suspended for safety",slotNumber)
                            end
                        end
                        if spawned then
                            slotResult.placed+=1;result.placed+=1
                            table.insert(self.Placed,pos)
                            log("CONFIRMED",slotNumber,spawned.Name,pos)
                        else
                            log("NOT CONFIRMED",slotNumber,pos,"reply",tostring(reply))
                        end
                        if result.uncertain or self.Cancelled then break end
                        if not self.Cancelled then task.wait(math.max(0.15,cfg.RetryDelay)) end
                    end
                end
            end
        end
    end
    result.completed=not self.Cancelled and not result.uncertain
    for slot=1,6 do
        local target=math.clamp(math.floor(tonumber(cfg.Slots[slot]) or 0),0,10)
        local entry=result.slots[slot]
        if target>0 and (not entry or entry.existing+entry.placed<target) then result.completed=false end
    end
    self.Running=false
    local outcome = result.uncertain and "PAUSED (uncertain)" or (result.resourcePause and "PAUSED (resource)" or (self.Cancelled and "STOPPED" or "Done"))
    statusText(outcome.." "..result.placed.." placed / "..result.attempted.." attempts")
end
local function startRun()
    task.spawn(function()
        local ok,err=xpcall(function() app:Run() end,debug.traceback)
        if not ok then app.Running=false;warn("[AAAutoPlace] Fatal:",err);statusText("ERROR - see console") end
    end)
end

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
local app={Config=cfg,LastPlan={},Running=false,Stopped=false,Uncertain=false,Requests=0}
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
    if self.Uncertain then return false,"Previous request uncertain; reload or investigate" end
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
    if not selected then return false,"No affordable, priced, eligible unit" end
    local unit=selected.Unit
    local stats=unit:FindFirstChild("_stats")
    local owner=getStat(stats,"player")
    local oldLevel=tonumber(getStat(stats,"upgrade"))
    if owner~=player or unit.Parent~=W:FindFirstChild("_UNITS") or oldLevel~=selected.Level then
        return false,"Unit ownership or level changed"
    end
    if self.Requests>=math.max(1,tonumber(cfg.MaxUpgradesPerRun) or 30) then
        return false,"Per-run upgrade limit reached"
    end
    self.Requests+=1
    log("UPGRADE REQUEST",unit.Name,"slot",selected.Slot,"old level",oldLevel,"expected cost",selected.Cost)
    -- Source references pass the placed Model itself, not its inventory UUID.
    local ok,reply=pcall(function() return remote:InvokeServer(unit) end)
    if not ok then warn("[AAAutoUpgrade] Request error",reply) end
    local deadline=os.clock()+math.clamp(tonumber(cfg.VerifyTimeout) or 2,0.5,8)
    repeat
        local observed=tonumber(getStat(stats,"upgrade"))
        if observed and observed>oldLevel then
            log("UPGRADE VERIFIED",unit.Name,oldLevel,"->",observed)
            return true,"Verified"
        end
        if self.Stopped then break end
        task.wait(0.1)
    until os.clock()>=deadline
    self.Uncertain=true
    self:Stop()
    warn("[AAAutoUpgrade] UPGRADE UNCERTAIN; stopped to prevent duplicates",unit.Name,oldLevel,"reply",tostring(reply))
    return false,"Upgrade not confirmed; stopped"
end
function app:Start()
    if self.Running then return end
    self.Running=true;self.Stopped=false;self.Uncertain=false;self.Requests=0
    local live=cfg.Mode=="LIVE"
    log("Scheduler started",live and "LIVE" or "PREVIEW")
    task.spawn(function()
        while self.Running and not self.Stopped do
            if live then
                local ok,reason=self:UpgradeOnce()
                if not ok and reason~="No affordable, priced, eligible unit" then
                    log("Scheduler pause",reason)
                    self:Stop()
                    break
                end
            else
                self:Preview()
            end
            task.wait(math.max(0.5,tonumber(live and cfg.RequestDelay or cfg.ScanInterval) or 1))
        end
        self.Running=false
    end)
end
function app:Stop() self.Stopped=true;self.Running=false;log("Stopped") end
function app:Destroy() self:Stop() end
log("U2 loaded: PREVIEW default; set Config.Mode='LIVE' to allow verified upgrades")

end

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
local autoPlayRunning=false
local function startAutoPlay()
    if autoPlayRunning or app.Running then return end
    autoPlayRunning=true
    task.spawn(function()
        local upgrade=upgradeApp()
        if upgrade then upgrade:Stop() end
        local ok,err=xpcall(function() app:Run() end,debug.traceback)
        if not ok then app.Running=false;warn("[AAAutoPlay] Placement failed:",err) end
        local result=app.LastResult
        if ok and result and result.completed and cfg.Mode=="LIVE" and not app.Cancelled
            and upgrade and upgrade.Config.Enabled then
            upgrade.Config.Mode="LIVE"
            log("SEQUENTIAL: placement targets met; starting upgrade")
            upgrade:Start()
        else
            log("SEQUENTIAL: upgrade not started; placement incomplete, stopped, or PREVIEW")
        end
        autoPlayRunning=false
    end)
end
local function stopAutoPlay()
    app:Stop()
    local upgrade=upgradeApp()
    if upgrade then upgrade:Stop() end
end

-- Native compact UI: independent from remote UI libraries.
local function buildWindUI()
    local WindUI=loadstring(game:HttpGet("https://github.com/Footagesus/WindUI/releases/download/1.6.66/main.lua"))()
    local window=WindUI:CreateWindow({
        Title="AA Auto Play",Icon="gamepad-2",Folder="AAAutoPlay",
        Size=UDim2.fromOffset(585,470),Theme="Dark",
        HideSearchBar=true,Resizable=true,ToggleKey=Enum.KeyCode.RightShift,
    })
    app.WindUIWindow=window
    local dashboard=window:Tab({Title="Dashboard",Icon="layout-dashboard"})
    dashboard:Paragraph({Title="Sequential / LIVE",Desc="Place all units first, then begin Auto Upgrade."})
    dashboard:Button({Title="START AUTO PLAY",Icon="play",Callback=startAutoPlay})
    dashboard:Button({Title="STOP ALL",Icon="square",Callback=stopAutoPlay})
    local previewToggle
    previewToggle=dashboard:Toggle({Title="Show Placement Preview",Value=cfg.ShowPreview,Callback=function(v)app:SetPreview(v)end})
    dashboard:Button({Title="Refresh Preview",Callback=function()app:RefreshPreview()end})
    dashboard:Button({Title="Preview Upgrade Queue",Callback=function()local u=upgradeApp();if u then u:Preview()end end})
    local unitTab=window:Tab({Title="Units",Icon="users"})
    unitTab:Paragraph({Title="Per-slot configuration",Desc="Select a slot from the dropdown below. Changes affect the selected slot only."})
    local selected=1
    local changing=false
    local typeControl,countControl,priorityControl,enabledControl,targetControl
    local function syncControls()
        changing=true
        local upgrade=upgradeApp()
        typeControl:Select(cfg.UnitTypes[selected] or "Damage")
        countControl:Set(cfg.Slots[selected] or 0)
        priorityControl:Set(cfg.UnitPriority[selected] or selected)
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
    local placement=window:Tab({Title="Placement",Icon="map-pin"})
    placement:Dropdown({Title="Center Mode",Values={"PATH_MIDPOINT","MOUSE","PLAYER","POSITION"},Value=cfg.CenterMode,Callback=function(v)cfg.CenterMode=v end})
    placement:Slider({Title="Main Path Position (%)",Step=5,Value={Min=0,Max=100,Default=cfg.PathPercent},Callback=function(v)cfg.PathPercent=v end})
    placement:Slider({Title="Radius (studs)",Step=1,Value={Min=1,Max=45,Default=cfg.Radius},Callback=function(v)cfg.Radius=v end})
    placement:Slider({Title="Grid Step",Step=1,Value={Min=1,Max=12,Default=cfg.GridStep},Callback=function(v)cfg.GridStep=v end})
    placement:Button({Title="Refresh Map Preview",Callback=function()app:RefreshPreview()end})
    placement:Button({Title="Inspect Road (Console)",Callback=function()app:InspectRoad()end})
    local settings=window:Tab({Title="Settings",Icon="settings"})
    settings:Toggle({Title="Enable Auto Upgrade",Value=u and u.Config.Enabled==true or false,Callback=function(v)local up=upgradeApp();if up then up.Config.Enabled=v end end})
    settings:Paragraph({Title="Settings file",Desc="AAAutoPlaceSettings.json | Reset by deleting file manually. Upgrade limit: 99."})
    settings:Button({Title="SAVE SETTINGS",Icon="save",Callback=function()
        local ok=app:SaveSettings()
        WindUI:Notify({Title=ok and "Saved" or "Save Failed",Content=ok and "Auto Play settings saved" or "Check console",Duration=3})
    end})
    log("WindUI loaded: Dashboard / Units / Placement / Settings")
end
local uiOk,uiErr=pcall(buildWindUI)
if not uiOk then warn("[AAAutoPlay] WindUI failed:",uiErr) end
log("Auto Play loaded; mode",cfg.Mode,"slots",table.concat(cfg.Slots,","))
if override.AutoStart==true and cfg.Mode=="LIVE" then
    task.defer(function()
        for attempt=1,30 do
            if app.Cancelled then return end
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
