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
