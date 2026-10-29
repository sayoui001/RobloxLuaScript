-- AA Auto Skill Slot 3 | v0.1.0-test.2
-- Experimental: read-only by default. Explicitly set Enabled=true to attempt casts.
repeat task.wait() until game:IsLoaded()
local Players=game:GetService("Players")
local RS=game:GetService("ReplicatedStorage")
local WS=game:GetService("Workspace")
local player=Players.LocalPlayer
local env=(type(getgenv)=="function" and getgenv()) or _G
if env.AAAutoSkillTest and env.AAAutoSkillTest.Stop then env.AAAutoSkillTest:Stop() end
local app={
    Version="0.1.0-test.2",
    Slot=3,
    Enabled=false,
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
env.AAAutoSkillTest=app
local function stat(folder,name)
    local value=folder and folder:FindFirstChild(name)
    return value and value:IsA("ValueBase") and value.Value or nil
end
local function slotUuid()
    local gui=player:FindFirstChild("PlayerGui")
    local frame=gui and gui:FindFirstChild("spawn_units")
    local slot=frame and frame:FindFirstChild(tostring(app.Slot),true)
    return slot and slot:GetAttribute("_equipped_frame_unit_uuid")
end
local function myUnits()
    local result={}
    local folder=WS:FindFirstChild("_UNITS")
    local uuid=slotUuid()
    if not folder or not uuid then return result end
    for _,unit in ipairs(folder:GetChildren()) do
        local stats=unit:FindFirstChild("_stats")
        if stat(stats,"player")==player and tostring(stat(stats,"uuid"))==tostring(uuid) then
            table.insert(result,{Model=unit,Stats=stats,Skill=stat(stats,"active_attack"),
                Cooldown=tonumber(stat(stats,"active_attack_cooldown")),
                LastCast=tonumber(stat(stats,"last_active_cast")),
                Queued=stat(stats,"active_queued_or_using")==true})
        end
    end
    return result
end
function app:Inspect()
    local units=myUnits()
    print("[AAAutoSkill] Version",self.Version,"Slot",self.Slot,"Owned",#units,"Mode",self.Enabled and "LIVE" or "PREVIEW")
    for _,unit in ipairs(units) do
        print("[AAAutoSkill] UNIT",unit.Model.Name,"Skill",tostring(unit.Skill),"Cooldown",tostring(unit.Cooldown),"LastCast",tostring(unit.LastCast),"Queued",unit.Queued)
    end
    self.Status=#units>0 and ("Detected "..#units.." Slot 3 unit(s)") or "Waiting for equipped Slot 3 unit"
    return units
end
function app:Step()
    local units=myUnits()
    if #units==0 then self.Status="Waiting for Slot 3 unit";return end
    local remote=RS:FindFirstChild("endpoints")
    remote=remote and remote:FindFirstChild("client_to_server")
    remote=remote and remote:FindFirstChild("use_active_attack")
    if not remote or not remote:IsA("RemoteFunction") then self.Status="Skill remote unavailable";return end
    for _,u in ipairs(units) do
        if self.Stopped then return end
        if type(u.Skill)~="string" or u.Skill=="" then
            self.Status="Slot 3 has no active skill"
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
                -- Slot 3 only. Remote signature still experimental; observe result.
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
        while not self.Stopped and env.AAAutoSkillTest==self do
            local ok,err=pcall(function()self:Step()end)
            if not ok then self.Status="Error: "..tostring(err);warn("[AAAutoSkill]",err) end
            task.wait(math.max(0.25,tonumber(self.ScanInterval) or 0.5))
        end
        self.Running=false
    end)
end
function app:Stop()self.Stopped=true;self.Running=false;self.Status="Stopped"end
print("[AAAutoSkill] Loaded",app.Version,"Slot 3 PREVIEW ONLY. Inspect with getgenv().AAAutoSkillTest:Inspect()")
