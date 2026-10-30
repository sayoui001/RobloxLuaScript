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
