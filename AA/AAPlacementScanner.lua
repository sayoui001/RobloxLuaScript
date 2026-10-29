-- AA Placement Scanner v0.1.0-test.3 (standalone, preview only)
-- No spawn_unit/InvokeServer calls. Does NOT modify AAAutoPlay.
repeat task.wait() until game:IsLoaded()
local Players=game:GetService("Players")
local WS=game:GetService("Workspace")
local player=Players.LocalPlayer
local env=(type(getgenv)=="function" and getgenv()) or _G
if env.AAPlacementScanner and env.AAPlacementScanner.Destroy then
    env.AAPlacementScanner:Destroy()
end

local Scanner={
    Version="0.1.0-test.3",
    Radius=18,
    Step=3,
    Spacing=3,
    FootprintRadius=2.5,
    FootprintSamples=8,
    HeightTolerance=1.2,
    ObstacleHeight=5,
    MaxSlopeDegrees=30,
    ScanHeight=50,
    ScanDepth=140,
    UseMouse=true,
    ShowRejected=true,
    StrictMode=false, -- diagnostic mode: only missing ground rejects; others are informational
    Markers={},
    Results={},
}
env.AAPlacementScanner=Scanner

local folder=Instance.new("Folder")
folder.Name="AAPlacementScanner_Preview"
folder.Parent=WS
Scanner.Folder=folder

local function getPosition()
    if Scanner.Center then return Scanner.Center end
    if Scanner.UseMouse then
        local mouse=player:GetMouse()
        if mouse and mouse.Hit then return mouse.Hit.Position end
    end
    local char=player.Character
    local hrp=char and char:FindFirstChild("HumanoidRootPart")
    return hrp and hrp.Position
end

local function isRoad(part)
    if not part then return false end
    local item=part
    while item and item~=WS do
        local n=item.Name:lower()
        if n=="_road" or n=="road" or n=="roads" or n=="path" then return true end
        item=item.Parent
    end
    return false
end

local function unitPositions()
    local points={}
    local units=WS:FindFirstChild("_UNITS")
    if units then
        for _,model in ipairs(units:GetChildren()) do
            if model:IsA("Model") then
                local ok,p=pcall(function()return model:GetPivot().Position end)
                if ok then table.insert(points,p) end
            end
        end
    end
    return points
end

local function marker(p,accepted,reason)
    local m=Instance.new("Part")
    m.Name=accepted and "Candidate_OK" or ("Candidate_"..tostring(reason))
    m.Anchored=true
    m.CanCollide=false
    m.CanTouch=false
    m.CanQuery=false
    m.Size=Vector3.new(0.8,0.18,0.8)
    m.Position=p+Vector3.new(0,0.25,0)
    m.Material=Enum.Material.Neon
    m.Color=accepted and Color3.fromRGB(40,215,105) or (reason=="footprint" and Color3.fromRGB(255,170,40) or reason=="obstacle" and Color3.fromRGB(210,70,255) or Color3.fromRGB(255,80,80))
    m.Transparency=0.25
    m.Parent=folder
end

function Scanner:Clear()
    folder:ClearAllChildren()
    self.Results={}
end

function Scanner:Scan()
    self:Clear()
    local center=getPosition()
    if not center then warn("[AAPlacementScanner] No center. Move mouse onto the map or set Center.");return nil end
    local params=RaycastParams.new()
    params.FilterType=Enum.RaycastFilterType.Exclude
    local exclude={folder}
    if player.Character then table.insert(exclude,player.Character) end
    params.FilterDescendantsInstances=exclude
    params.IgnoreWater=true
    local units=unitPositions()
    local counts={ok=0,road=0,steep=0,occupied=0,unreachable=0,footprint=0,obstacle=0}
    local footprint=math.clamp(tonumber(self.FootprintRadius) or 2.5,0,8)
    local sampleCount=math.clamp(math.floor(tonumber(self.FootprintSamples) or 8),4,16)
    local tolerance=math.clamp(tonumber(self.HeightTolerance) or 1.2,0.1,6)
    local obstacleHeight=math.clamp(tonumber(self.ObstacleHeight) or 5,1,15)
    local overlap=OverlapParams.new()
    overlap.FilterType=Enum.RaycastFilterType.Exclude
    overlap.FilterDescendantsInstances=exclude
    overlap.MaxParts=60
    local radius=math.clamp(tonumber(self.Radius) or 18,3,60)
    local step=math.clamp(tonumber(self.Step) or 3,1,12)
    local spacing=math.clamp(tonumber(self.Spacing) or 3,0,12)
    local maxCos=math.cos(math.rad(math.clamp(tonumber(self.MaxSlopeDegrees) or 30,0,89)))
    for dx=-radius,radius,step do
        for dz=-radius,radius,step do
            if dx*dx+dz*dz<=radius*radius then
                local origin=center+Vector3.new(dx,self.ScanHeight,dz)
                local hit=WS:Raycast(origin,Vector3.new(0,-self.ScanDepth,0),params)
                local point=hit and hit.Position or Vector3.new(origin.X,center.Y,origin.Z)
                local reason
                if not hit then reason="unreachable"
                elseif isRoad(hit.Instance) then reason="road"
                elseif hit.Normal.Y<maxCos then reason="steep"
                else
                    for _,pos in ipairs(units) do
                        local delta=Vector3.new(point.X-pos.X,0,point.Z-pos.Z)
                        if delta.Magnitude<spacing then reason="occupied";break end
                    end
                end
                if not reason and footprint>0 then
                    for i=1,sampleCount do
                        local theta=2*math.pi*i/sampleCount
                        local offset=Vector3.new(math.cos(theta)*footprint,0,math.sin(theta)*footprint)
                        local sideHit=WS:Raycast(point+offset+Vector3.new(0,3,0),Vector3.new(0,-7,0),params)
                        if not sideHit or isRoad(sideHit.Instance) or sideHit.Normal.Y<maxCos or math.abs(sideHit.Position.Y-point.Y)>tolerance then
                            reason="footprint";break
                        end
                    end
                end
                if not reason and footprint>0 then
                    local blockers=WS:GetPartBoundsInBox(CFrame.new(point+Vector3.new(0,obstacleHeight/2+0.2,0)),Vector3.new(footprint*2,obstacleHeight,footprint*2),overlap)
                    for _,part in ipairs(blockers) do
                        if part.CanCollide and not isRoad(part) then
                            local unitsFolder=WS:FindFirstChild("_UNITS")
                            if (not unitsFolder or not part:IsDescendantOf(unitsFolder)) and part.Position.Y+part.Size.Y/2>point.Y+0.35 then
                                reason="obstacle";break
                            end
                        end
                    end
                end
                local diagnosticReason=reason
                if not self.StrictMode and hit then reason="ok" end
                if not reason then reason="ok" end
                counts[reason]+=1
                table.insert(self.Results,{Position=point,Reason=reason,Diagnostic=diagnosticReason,Surface=hit and hit.Instance:GetFullName() or nil})
                if reason=="ok" or self.ShowRejected then marker(point,reason=="ok",reason) end
            end
        end
    end
    print(string.format("[AAPlacementScanner] v%s center=%s total=%d OK=%d road=%d occupied=%d steep=%d noGround=%d footprint=%d obstacle=%d",
        self.Version,tostring(center),#self.Results,counts.ok,counts.road,counts.occupied,counts.steep,counts.unreachable,counts.footprint,counts.obstacle))
    print("[AAPlacementScanner] Mode:",self.StrictMode and "STRICT" or "GROUND-ONLY","GREEN=ground detected; NOT server-confirmed")
    return counts
end

function Scanner:Destroy()
    if self.Folder then self.Folder:Destroy() end
    if env.AAPlacementScanner==self then env.AAPlacementScanner=nil end
end

print("[AAPlacementScanner] Loaded v"..Scanner.Version)
print("[AAPlacementScanner] Hover mouse over a location and run: getgenv().AAPlacementScanner:Scan()")
print("[AAPlacementScanner] Change Radius / Step / Center on getgenv().AAPlacementScanner; :Clear() or :Destroy()")
