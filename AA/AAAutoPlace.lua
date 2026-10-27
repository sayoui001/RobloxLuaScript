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
    Mode="PREVIEW", -- explicit "LIVE" required
    CenterMode="PATH_MIDPOINT", -- PATH_MIDPOINT (default), MOUSE, PLAYER, POSITION
    CenterPosition=nil,
    PathPercent=50, -- 0=start of road, 100=end; defaults to halfway
    Radius=12, GridStep=3, UnitSpacing=3,
    MaxAttemptsPerSlot=40, MaxTotalAttempts=120,
    VerifyTimeout=2, RetryDelay=0.45, ScanHeight=35,
    MaxHeightDifference=8, MinNormalY=0.85,
    Slots={0,0,0,0,1,0}, -- target total per slot
    UnitPriority={1,2,3,4,5,6}, -- lower number places first
    MaxTotalPlaced=12,
    CountExistingUnits=true, LateVerifyTimeout=3,
    ShowPreview=true, AutoPreviewOnLoad=true, MaxPreviewMarkers=100,
    UILibrary="RayfieldGen2",
    Blacklist={elyssia_jellyfish=true,elyssia_eel=true},
}
-- Executor-local JSON settings. Never persist LIVE mode or a map-specific Vector3.
local HttpService=game:GetService("HttpService")
local settingsPath="AAAutoPlaceSettings.json"
local persistKeys={"CenterMode","PathPercent","Radius","GridStep","UnitSpacing","ShowPreview","Slots","UnitPriority","MaxAttemptsPerSlot","MaxTotalAttempts","VerifyTimeout","RetryDelay","CountExistingUnits"}
local function readSettings()
    if type(readfile)~="function" then return {} end
    local ok,data=pcall(function() return HttpService:JSONDecode(readfile(settingsPath)) end)
    if not ok or type(data)~="table" then return {} end
    local safe={}
    for _,key in ipairs(persistKeys) do
        if key=="UnitPriority" then
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
cfg.Mode=override.Mode=="LIVE" and "LIVE" or "PREVIEW"
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
        if key=="UnitPriority" then
            data.UnitPriority={}
            for i=1,6 do data.UnitPriority[i]=math.clamp(math.floor(tonumber(cfg.UnitPriority[i]) or i),1,6) end
        elseif key=="Slots" then
            data.Slots={}
            for i=1,6 do data.Slots[i]=math.clamp(math.floor(tonumber(cfg.Slots[i]) or 0),0,10) end
        else data[key]=cfg[key] end
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
local function pathMidpoint()
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
    local percent=math.clamp(tonumber(cfg.PathPercent) or 50,0,100)
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
function app:SetPreview(enabled)
    cfg.ShowPreview=enabled and true or false
    if not cfg.ShowPreview then self:ClearPreview()
    elseif not self.Running then self:RefreshPreview() end
end
function app:RefreshPreview()
    local center=centerPosition()
    if not center then statusText("Preview: center unavailable");return 0 end
    local count=self:ShowPreview(center,offsets())
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
end
function app:Run()
    if self.Running then return end
    self.Running=true
    self.Cancelled=false
    self.Placed={}
    local result={placed=0,attempted=0,slots={},mode=cfg.Mode,uncertain=false}
    self.LastResult=result
    local center=centerPosition()
    if not center then statusText("No center found for "..tostring(cfg.CenterMode));self.Running=false;return end
    local offsetsList=offsets()
    local previewCount=self:ShowPreview(center,offsetsList)
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
                log("Slot target",slotNumber,"target",want,"existing",slotResult.existing,"needed",required)
                for _,o in ipairs(offsetsList) do
                    if self.Cancelled or slotResult.placed>=required or slotResult.attempted>=perSlot
                        or result.placed>=maxTotal or result.attempted>=maxAttempts then break end
                    local pos=findGround(center,o)
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
local function buildRayfield()
    local loader=loadstring(game:HttpGet("https://sirius.menu/gen2"))
    local library=loader()
    local window=library:CreateWindow({name="AA AutoPlace",subtitle="Phase 2 | Center Out",theme="cobalt"})
    app.RayfieldWindow=window
    local main=window:CreateTab({name="Placement"})
    main:CreateToggle({name="Show Markers",value=cfg.ShowPreview,flag="AA_ShowMarkers",callback=function(v) app:SetPreview(v) end})
    main:CreateDropdown({name="Center",options={"PATH_MIDPOINT","MOUSE","PLAYER","POSITION"},value=cfg.CenterMode,flag="AA_Center",callback=function(v) cfg.CenterMode=v;if cfg.ShowPreview then app:RefreshPreview() end end})
    main:CreateSlider({name="Path Position (%)",range={0,100},increment=5,value=cfg.PathPercent,suffix="%",flag="AA_PathPercent",callback=function(v) cfg.PathPercent=v;if cfg.ShowPreview then app:RefreshPreview() end end})
    main:CreateSlider({name="Radius",range={6,40},increment=1,value=cfg.Radius,suffix=" studs",flag="AA_Radius",callback=function(v)cfg.Radius=v end})
    main:CreateSlider({name="Grid Step",range={2,8},increment=1,value=cfg.GridStep,suffix=" studs",flag="AA_Grid",callback=function(v)cfg.GridStep=v end})
    main:CreateButton({name="Refresh Preview",callback=function()app:RefreshPreview() end})
    main:CreateButton({name="Debug Road (Console)",callback=function()app:InspectRoad() end})
    main:CreateButton({name="Start ("..cfg.Mode..")",callback=startRun})
    main:CreateButton({name="Stop",callback=function()app:Stop() end})
    local units=window:CreateTab({name="Units"})
    for i=1,6 do
        local slot=i
        units:CreateSlider({name="Slot "..slot.." Count",range={0,10},increment=1,value=cfg.Slots[slot] or 0,flag="AA_Slot"..slot,callback=function(v)cfg.Slots[slot]=v end})
        units:CreateSlider({name="Slot "..slot.." Priority (1 first)",range={1,6},increment=1,value=cfg.UnitPriority[slot] or slot,flag="AA_Prio"..slot,callback=function(v)cfg.UnitPriority[slot]=v end})
    end
    local settings=window:CreateTab({name="Settings"})
    settings:CreateButton({name="Save Settings",callback=function()
        app:SaveSettings()
    end})
    settings:CreateButton({name="Clear Saved Settings (reload to reset)",callback=function()
        app:ClearSavedSettings()
    end})
    log("Rayfield Gen2 UI ready; saved settings loaded (if present)")
end
local uiOk,uiErr=pcall(buildRayfield)
if not uiOk then warn("[AAAutoPlace] Rayfield Gen2 unavailable, fallback UI:",uiErr) end
if not uiOk then
local gui=Instance.new("ScreenGui")
gui.Name="AAAutoPlaceUI";gui.ResetOnSpawn=false
gui.Parent=player:WaitForChild("PlayerGui")
app.Gui=gui
local frame=Instance.new("Frame")
frame.Size=UDim2.fromOffset(290,132)
frame.Position=UDim2.new(0,24,0.5,-66)
frame.BackgroundColor3=Color3.fromRGB(31,35,42)
frame.Parent=gui
local function btn(label,y)
    local b=Instance.new("TextButton")
    b.Size=UDim2.fromOffset(274,31)
    b.Position=UDim2.fromOffset(8,y)
    b.BackgroundColor3=Color3.fromRGB(65,82,100)
    b.TextColor3=Color3.new(1,1,1)
    b.Font=Enum.Font.Gotham
    b.TextSize=13
    b.Text=label;b.Parent=frame
    return b
end
local start=btn("START ("..cfg.Mode..") | Slots 1-6",8)
local stop=btn("STOP",46)
local status=Instance.new("TextLabel")
status.Size=UDim2.fromOffset(275,40)
status.Position=UDim2.fromOffset(7,87)
status.BackgroundTransparency=1
status.TextColor3=Color3.new(1,1,1)
status.TextSize=12
status.TextWrapped=true
status.Text="Center: "..cfg.CenterMode.." | Slot counts from config"
status.Parent=frame
app.StatusLabel=status
table.insert(app.Connections,start.MouseButton1Click:Connect(startRun))
table.insert(app.Connections,stop.MouseButton1Click:Connect(function() app:Stop() end))
end -- fallback UI only
log("Phase1 loaded; mode",cfg.Mode,"slots",table.concat(cfg.Slots,","))
if cfg.Mode~="LIVE" and cfg.AutoPreviewOnLoad then
    task.defer(function()
        local ok,err=xpcall(function() app:Run() end,debug.traceback)
        if not ok then app.Running=false;warn("[AAAutoPlace] Auto preview error:",err) end
    end)
end
