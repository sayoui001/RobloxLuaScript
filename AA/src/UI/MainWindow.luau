-- UI module: original WindUI callbacks preserved.
return function(deps)
local app=deps.app
local cfg=deps.cfg
local env=deps.env
local player=deps.player
local upgradeApp=deps.upgradeApp
local startAutoPlay=deps.startAutoPlay
local stopAutoPlay=deps.stopAutoPlay
local applyMapPathPercent=deps.applyMapPathPercent
local mapPathPercents=deps.mapPathPercents
local mapPlacementSides=deps.mapPlacementSides
local mapPlacementAnchors=deps.mapPlacementAnchors
local statusText=deps.statusText
local log=deps.log
local SCRIPT_VERSION=deps.SCRIPT_VERSION
local saved=deps.saved
local isAutoPlayRunning=deps.isAutoPlayRunning
local syncAutoBuff=deps.syncAutoBuff
local function buildWindUI()
    local WindUI=loadstring(game:HttpGet("https://github.com/Footagesus/WindUI/releases/download/1.6.66/main.lua"))()
    local window=WindUI:CreateWindow({
        Title="AA Auto Play v"..SCRIPT_VERSION,Icon="gamepad-2",Folder="AAAutoPlay",
        Size=UDim2.fromOffset(585,470),Theme="Dark",
        HideSearchBar=true,Resizable=true,ToggleKey=Enum.KeyCode.RightShift,
        OpenButton={Title="Open AA Auto Play",Enabled=true,Draggable=true,OnlyMobile=false,Scale=0.65},
    })
    app.WindUIWindow=window
    local dashboard=window:Tab({Title="Dashboard",Icon="layout-dashboard"})
    dashboard:Paragraph({Title="Sequential / LIVE",Desc="Place all units first, then begin Auto Upgrade."})
    app.StatusParagraph=dashboard:Paragraph({Title="Auto Play Status",Desc=app.CurrentStatus or "Idle - ready to start"})
    app.UpgradeParagraph=dashboard:Paragraph({Title="Auto Upgrade",Desc="Idle | Sequential mode"})
    app.WaveParagraph=dashboard:Paragraph({Title="Wave Scheduler",Desc="Waiting for Wave data"})
    app.SkillParagraph=dashboard:Paragraph({Title="Auto Skill (Selected Slots)",Desc="Idle"})
    task.spawn(function()
        local last=""
        while app.WindUIWindow==window and env.AAAutoPlace==app do
            local upgrade=upgradeApp()
            local sk=env.AAAutoSkill
            if sk then pcall(function() app.SkillParagraph:SetDesc((sk.Enabled and "LIVE | " or "PREVIEW | ")..tostring(sk.Status).." | Casts "..tostring(sk.Verified).."/"..tostring(sk.Requests)) end) end
            pcall(function() app.WaveParagraph:SetDesc("Wave "..tostring(app.CurrentWave or "?").." | Next Placement "..tostring(app.NextPlacementWave or "-")) end)
            local details=upgrade and (tostring(upgrade.Status or "Idle").." | Verified "..tostring(upgrade.Verified or 0).." | Requests "..tostring(upgrade.Requests or 0).."/"..tostring(upgrade.Config.MaxUpgradesPerRun)) or "Unavailable"
            if details~=last then
                last=details
                pcall(function() app.UpgradeParagraph:SetDesc(details) end)
            end
            task.wait(0.5)
        end
    end)
    dashboard:Toggle({Title="Auto Play",Value=cfg.AutoPlayEnabled==true,Callback=function(v)
        cfg.AutoPlayEnabled=v==true
        if cfg.AutoPlayEnabled then startAutoPlay() else stopAutoPlay() end
        app:SaveSettings()
    end})
    local previewToggle
    previewToggle=dashboard:Toggle({Title="Show Placement Preview",Value=cfg.ShowPreview,Callback=function(v)app:SetPreview(v)end})
    dashboard:Button({Title="Refresh Preview",Callback=function()app:RefreshPreview()end})
    dashboard:Button({Title="Preview Upgrade Queue",Callback=function()local u=upgradeApp();if u then u:Preview()end end})
    local unitTab=window:Tab({Title="Units",Icon="users"})
    unitTab:Paragraph({Title="Per-slot configuration",Desc="Select a slot from the dropdown below. Changes affect the selected slot only."})
    local selected=1
    local changing=false
    local typeControl,countControl,priorityControl,enabledControl,targetControl,waveControl,skillControl
    local function syncControls()
        changing=true
        local upgrade=upgradeApp()
        typeControl:Select(cfg.UnitTypes[selected] or "Damage")
        countControl:Set(cfg.Slots[selected] or 0)
        priorityControl:Set(cfg.UnitPriority[selected] or selected)
        waveControl:Set(cfg.StartWave[selected] or 1)
        if skillControl then skillControl:Set(cfg.AutoSkillSlots[selected]==true) end
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
    waveControl=unitTab:Slider({Title="Start Placement at Wave",Step=1,Value={Min=1,Max=100,Default=cfg.StartWave[1] or 1},Callback=function(v)
        if not changing then cfg.StartWave[selected]=math.clamp(math.floor(v),1,100) end
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
    skillControl=unitTab:Toggle({Title="Auto Skill for this Slot",Value=cfg.AutoSkillSlots[1]==true,Callback=function(v)
        if not changing then
            cfg.AutoSkillSlots[selected]=v
            local sk=env.AAAutoSkill
            if sk then sk.Enabled=isAutoPlayRunning() and cfg.Mode=="LIVE" and table.find(cfg.AutoSkillSlots,true)~=nil end
        end
    end})
    local placement=window:Tab({Title="Placement",Icon="map-pin"})
    placement:Dropdown({Title="Center Mode",Values={"PATH_MIDPOINT","MOUSE","PLAYER","POSITION"},Value=cfg.CenterMode,Callback=function(v)cfg.CenterMode=v end})
    local pathSlider
    local sideControl
    sideControl=placement:Dropdown({Title="Placement Side - This Stage",Values={"LEFT","CENTER","RIGHT"},Value=cfg.PlacementSide,Callback=function(v)
        if v=="LEFT" or v=="CENTER" or v=="RIGHT" then
            cfg.PlacementSide=v
            if cfg.CurrentMapKey then mapPlacementSides[cfg.CurrentMapKey]=v end
            app:RefreshPreview()
        end
    end})
    local mapLabel=placement:Paragraph({Title="Current Stage",Desc=cfg.CurrentMapKey or "Waiting for map data"})
    placement:Paragraph({Title="Manual Placement Area",Desc="Set a verified buildable location with mouse. Saved separately per stage; overrides decorative road anchoring for all unit types."})
    placement:Button({Title="Use Mouse Position as Placement Center",Callback=function()
        local key=applyMapPathPercent()
        local mouse=player:GetMouse()
        local hit=mouse and mouse.Target
        if not key or not hit or not mouse.Hit then
            statusText("Manual placement: point mouse at buildable ground on a loaded stage")
            return
        end
        local point=mouse.Hit.Position
        mapPlacementAnchors[key]={point.X,point.Y,point.Z}
        app:SaveSettings()
        app:RefreshPreview()
        statusText("Manual placement center saved for this stage")
    end})
    placement:Button({Title="Clear Manual Placement Center",Callback=function()
        local key=applyMapPathPercent()
        if key then mapPlacementAnchors[key]=nil;app:SaveSettings() end
        app:RefreshPreview()
        statusText("Using automatic road-based placement again")
    end})
    pathSlider=placement:Slider({Title="Main Path Position (%) - This Stage",Step=5,Value={Min=0,Max=100,Default=cfg.PathPercent},Callback=function(v)
        cfg.PathPercent=math.clamp(tonumber(v) or 50,0,100)
        if cfg.CurrentMapKey then mapPathPercents[cfg.CurrentMapKey]=cfg.PathPercent end
    end})
    task.spawn(function()
        local shownKey=cfg.CurrentMapKey
        while app.WindUIWindow==window and env.AAAutoPlace==app do
            local key=applyMapPathPercent()
            if key and key~=shownKey then
                shownKey=key
                pcall(function() pathSlider:Set(cfg.PathPercent) end)
                pcall(function() sideControl:Select(cfg.PlacementSide) end)
                pcall(function() mapLabel:SetDesc(key) end)
                log("MAP PROFILE",key,"Main Path",cfg.PathPercent.."%")
            end
            task.wait(3)
        end
    end)
    placement:Slider({Title="Radius (studs)",Step=1,Value={Min=1,Max=45,Default=cfg.Radius},Callback=function(v)cfg.Radius=v end})
    placement:Slider({Title="Grid Step",Step=1,Value={Min=1,Max=12,Default=cfg.GridStep},Callback=function(v)cfg.GridStep=v end})
    placement:Button({Title="Refresh Map Preview",Callback=function()app:RefreshPreview()end})
    placement:Button({Title="Inspect Road (Console)",Callback=function()app:InspectRoad()end})
    placement:Toggle({Title="Road Preview",Value=cfg.ShowRoadPreview==true,Callback=function(enabled)
        cfg.ShowRoadPreview=enabled==true
        app:RefreshRoadPreview()
    end})
    placement:Toggle({Title="Slow Placement Preview",Value=cfg.ShowSlowPreview==true,Callback=function(enabled)
        cfg.ShowSlowPreview=enabled==true
        app:RefreshSlowPreview()
    end})
    placement:Button({Title="Refresh Slow Preview",Callback=function()app:RefreshSlowPreview()end})
    placement:Slider({Title="Road Half Width (studs)",Step=0.5,Value={Min=0.5,Max=6,Default=cfg.RoadHalfWidth},Callback=function(v)cfg.RoadHalfWidth=v;if cfg.ShowRoadPreview then app:RefreshRoadPreview()end end})
    local settings=window:Tab({Title="Settings",Icon="settings"})
    settings:Toggle({Title="Enable Auto Upgrade",Value=u and u.Config.Enabled==true or false,Callback=function(v)local up=upgradeApp();if up then up.Config.Enabled=v end end})

    local buffTab=window:Tab({Title="Auto Buff",Icon="zap"})
    buffTab:Paragraph({Title="V3 Rotation",Desc="Four units of one type are required; uses maximum cooldown / 4 + 0.15s."})
    for _,kind in ipairs({"erwin","wendy","leafa"}) do
        local currentKind=kind
        buffTab:Toggle({Title="Enable "..currentKind.." Buff",Value=cfg.AutoBuffEnabled[currentKind]==true,Callback=function(value)
            cfg.AutoBuffEnabled[currentKind]=value==true
            syncAutoBuff(isAutoPlayRunning())
        end})
    end
    settings:Paragraph({Title="Auto Save",Desc="Changes save automatically after 1.5 seconds to AAAutoPlaceSettings.json. SAVE SETTINGS is also available."})
    settings:Button({Title="SAVE SETTINGS",Icon="save",Callback=function()
        local ok=app:SaveSettings()
        WindUI:Notify({Title=ok and "Saved" or "Save Failed",Content=ok and "Auto Play settings saved" or "Check console",Duration=3})
    end})
    dashboard:Select()
    log("WindUI loaded: Dashboard selected / Units / Placement / Settings")
end
return buildWindUI
end
