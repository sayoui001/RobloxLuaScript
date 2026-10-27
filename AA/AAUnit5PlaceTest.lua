-- Anime Adventures: Unit 5 controlled placement test
-- Run in the match, point your mouse at the desired center, then press TEST UNIT 5.
-- One successful placement maximum. This makes actual in-game placement requests.
repeat task.wait() until game:IsLoaded()
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local player = Players.LocalPlayer
local mouse = player:GetMouse()
local env = (type(getgenv) == "function" and getgenv()) or _G
if env.AAUnit5Test and type(env.AAUnit5Test.Destroy)=="function" then
    pcall(function() env.AAUnit5Test:Destroy() end)
end

local app = {running=false, stopped=false}
env.AAUnit5Test = app
local gui = Instance.new("ScreenGui")
gui.Name = "AAUnit5TestUI"
gui.ResetOnSpawn = false
gui.Parent = player:WaitForChild("PlayerGui")
local frame = Instance.new("Frame")
frame.Size = UDim2.fromOffset(260, 108)
frame.Position = UDim2.new(0, 24, 0.52, 0)
frame.BackgroundColor3 = Color3.fromRGB(31,35,42)
frame.Parent=gui
local function makeButton(text,y)
    local b = Instance.new("TextButton")
    b.Text=text;b.TextColor3=Color3.new(1,1,1);b.TextSize=14
    b.Font=Enum.Font.Gotham
    b.Size=UDim2.fromOffset(244,30)
    b.Position=UDim2.fromOffset(8,y)
    b.BackgroundColor3=Color3.fromRGB(66,80,99)
    b.Parent=frame
    return b
end
local test=makeButton("TEST UNIT 5 (mouse center)",8)
local stop=makeButton("STOP / CLOSE",44)
local status=Instance.new("TextLabel")
status.BackgroundTransparency=1
status.Size=UDim2.fromOffset(250,20)
status.Position=UDim2.fromOffset(5,82)
status.TextColor3=Color3.fromRGB(222,222,222)
status.TextSize=12
status.Text="Ready - one placement max"
status.Parent=frame

local function say(msg)
    print("[AAUnit5Test] "..msg)
    if status.Parent then status.Text=msg end
end
local UNIT_BLACKLIST = {
    elyssia_jellyfish = true, -- summoned companion; not a directly placed unit
    elyssia_eel = true, -- summoned companion; not a directly placed unit
}
local function ownedSnapshot(folder)
    local owned={}
    for _,u in ipairs(folder:GetChildren()) do
        if UNIT_BLACKLIST[u.Name:lower()] then continue end
        local st=u:FindFirstChild("_stats")
        local owner=st and st:FindFirstChild("player")
        if owner and owner.Value==player then owned[u]=true end
    end
    return owned
end
local function newlyPlaced(folder,before)
    for u in pairs(ownedSnapshot(folder)) do
        if not before[u] then return u end
    end
    return nil
end
local function traceGround(center,dx,dz)
    local params=RaycastParams.new()
    params.FilterType=Enum.RaycastFilterType.Exclude
    local ignored={}
    if player.Character then table.insert(ignored,player.Character) end
    params.FilterDescendantsInstances=ignored
    local target=center+Vector3.new(dx,0,dz)
    local hit=Workspace:Raycast(target+Vector3.new(0,35,0),Vector3.new(0,-90,0),params)
    if not hit or hit.Normal.Y<0.85 then return nil end
    -- Restrict to near the intended surface elevation
    if math.abs(hit.Position.Y-center.Y)>8 then return nil end
    return hit.Position
end
local offsets={{0,0},{3,0},{-3,0},{0,3},{0,-3},{3,3},{-3,3},{3,-3}}
function app:Run()
    if self.running then return end
    self.running=true
    self.stopped=false
    local folder=Workspace:FindFirstChild("_UNITS")
    local slot=player.PlayerGui:FindFirstChild("spawn_units")
    slot=slot and slot:FindFirstChild("5",true)
    local uuid=slot and slot:GetAttribute("_equipped_frame_unit_uuid")
    local ep=RS:FindFirstChild("endpoints")
    ep=ep and ep:FindFirstChild("client_to_server")
    local remote=ep and ep:FindFirstChild("spawn_unit")
    if not folder or type(uuid)~="string" or not remote or not remote:IsA("RemoteFunction") then
        say("Missing _UNITS, slot 5 UUID, or spawn_unit")
        self.running=false;return
    end
    local hit=mouse.Hit
    local center=hit and hit.Position
    if not center then say("Mouse has no world hit");self.running=false;return end
    local before=ownedSnapshot(folder)
    local count=0
    for _,offset in ipairs(offsets) do
        if self.stopped then break end
        local pos=traceGround(center,offset[1],offset[2])
        if pos then
            count+=1
            say("Trying "..count.."/8 at "..tostring(pos))
            -- Existing AA script examples use spawn_unit(uuid, CFrame).
            local ok,res=pcall(function()
                return remote:InvokeServer(uuid,CFrame.new(pos))
            end)
            if not ok then
                warn("[AAUnit5Test] Server call error: ",res)
            end
            local deadline=os.clock()+1.5
            repeat
                if self.stopped then break end
                local spawned=newlyPlaced(folder,before)
                if spawned then
                    say("SUCCESS: "..spawned.Name)
                    self.running=false
                    return
                end
                task.wait(0.1)
            until os.clock()>=deadline
        end
    end
    say(self.stopped and "Stopped" or ("No confirmed placement; tried "..count.." points"))
    self.running=false
end
function app:Destroy()
    self.stopped=true
    if gui.Parent then gui:Destroy() end
end
test.MouseButton1Click:Connect(function()
    task.spawn(function() app:Run() end)
end)
stop.MouseButton1Click:Connect(function() app:Destroy() end)
say("Ready: point mouse, click TEST UNIT 5")
