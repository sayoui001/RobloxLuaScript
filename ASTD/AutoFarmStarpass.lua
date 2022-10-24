repeat
    wait()
until game:IsLoaded()
wait(3)
if game.PlaceId == 4996049426 or game.PlaceId == 7785334488 then

    local gs = game:GetService("ReplicatedStorage").Remotes.Input
    local UserInputService = game:GetService("UserInputService")
    local RunService = game:GetService("RunService")

    function EvoEXP()
        spawn(function()
            local EXP4 = { [1] = "UpgradeUnit" ,[2] = "EXP III" ,[3] = 2 }
            local EXP3 = { [1] = "UpgradeUnit" ,[2] = "EXP II"  ,[3] = 2 }
            local EXP2 = { [1] = "UpgradeUnit" ,[2] = "EXP I"   ,[3] = 2 }
            while _G.AutoEvo == true do
                gs:FireServer(unpack(EXP4))
                wait(0.25)
                gs:FireServer(unpack(EXP3))
                wait(0.25)
                gs:FireServer(unpack(EXP4))
                wait(0.25)
                gs:FireServer(unpack(EXP2))
                wait(0.25)
                if not _G.AutoEvo then break end
            end
        end)
    end

    function PlaceUnit()
        spawn(function()
            local EX = {
                [1] = "VoteGameMode",
                [2] = "Extreme"
            }
        
            local FW = {
                [1] = "SpeedChange",
                [2] = true
            }
        
            local pGenos = {
                [1] = "Summon",
                [2] = {
                    ["Rotation"] = 0,
                    ["cframe"] = CFrame.new(Vector3.new(-412.356, 596.409, 24.767), Vector3.new(-0, -0, -1)),
                    ["Unit"] = "Genos [Overdrive]"
                }
            }
            local i = 1
            while _G.AutoStarPass == true do
                RunService:Set3dRenderingEnabled(false)
                gs:FireServer(unpack(EX))
                wait(1)
                gs:FireServer(unpack(FW))
                wait(1)
                gs:FireServer(unpack(pGenos))
                wait(1)
                i = i + 1 
                if i > 9 then break end
            end
        end)
    end

    function UpgradeUnit()
        spawn(function()
            local uGenos = {
                [1] = "Upgrade",
                [2] = workspace.Unit:FindFirstChild("Genos [Overdrive]")
            }
            while _G.AutoStarPass == true do
                if game:GetService("Workspace").Unit["Genos [Overdrive]"].UpgradeTag.Value == 3 then
                    break
                end                
                wait(3)
                game:GetService("ReplicatedStorage").Remotes.Server:InvokeServer(unpack(uGenos))
            end
        end)
    end

    function SellUnit()
        spawn(function()
            local sGenos = {
                [1] = "Sell",
                [2] = workspace.Unit:FindFirstChild("Genos [Overdrive]")
            }
            while _G.AutoStarPass == true do
                wait(2)
                local cwave = game:GetService("Players").LocalPlayer.PlayerGui.HUD.Wave.Text
                local owave = tonumber(string.match(cwave, '%S+$'))
                if owave == 18 then
                    wait(10)
                    gs:FireServer(unpack(sGenos))
                    break
                end
            end
        end)
    end
    
    function AutoReplay()
        spawn(function()
            local function click(a)
                game:GetService("VirtualInputManager"):SendMouseButtonEvent(a.AbsolutePosition.X+a.AbsoluteSize.X/2,a.AbsolutePosition.Y+50,0,true,a,1)
                game:GetService("VirtualInputManager"):SendMouseButtonEvent(a.AbsolutePosition.X+a.AbsoluteSize.X/2,a.AbsolutePosition.Y+50,0,false,a,1)
            end
            while _G.AutoStarPass == true do
                wait(2)
                for _, v in pairs(game:GetService("Players").LocalPlayer.PlayerGui:GetChildren()) do
                    if v.Name == "MissionEndNavigateDialog" then
                        click(game:GetService("Players").LocalPlayer.PlayerGui.MissionEndNavigateDialog.TextFrame.Replay)
                    end
                end
            end
        end)
    end

    function AutoJoin()
        spawn(function()
            local start = {
            [1] = "InfiniteModeStart"
            }

            local inf = {
                [1] = "InfiniteModeInfLevel",
                [2] = "-1.7",
                [3] = false
            }
            while _G.AutoStarPass == true do
                if game.PlaceId == 4996049426 then
                    game:GetService("Players").LocalPlayer.Character.HumanoidRootPart.CFrame = game:GetService("Workspace").Queue.Infinite.InfiniteMode.CFrame 
                end
                if game.PlaceId == 7785334488 then
                    game:GetService("Players").LocalPlayer.Character.HumanoidRootPart.CFrame = game:GetService("Workspace").Queue.Joinables.InfiniteMode.CFrame
                end
                wait(1)
                gs:FireServer(unpack(inf))
                wait(1)
                gs:FireServer(unpack(start))
                wait(15)
            end
        end)
    end

    if _G.AutoStarPass == true then
        for _, v in pairs(game:GetService("Workspace"):GetChildren()) do
            if v.Name == "Queue" then
                EvoEXP()
                AutoJoin()
                break
            end
            if v.Name == "Placeable" then
                PlaceUnit()
                wait(15)
                UpgradeUnit()
                SellUnit()
                AutoReplay()
                game:GetService("Players").LocalPlayer.OnTeleport:Connect(function(State)
                    if State == Enum.TeleportState.Started then
                        local url = _G.WebhookUrl
                        local scripttime = game.Workspace.DistributedGameTime
                        local seconds = scripttime
                        local tempo = string.format("%.0f Seconds",seconds)
                        local tier = game:GetService("Players").LocalPlayer.PlayerGui.TowerPassRewards.Main.Header.Wrapper.Tier.Wrapper.Container.TierNumber.Text
                        local wave = game:GetService("Players").LocalPlayer.PlayerGui.HUD.Wave.Text
                        local waves = string.match(wave, '%S+$')
                        local data = {
                            ["content"] = "",
                            ["embeds"] = {
                                {
                                    ["title"] = "**STAR PASS FARM NOTIFIER**",
                                    ["description"] = "**Username : **||"..game.Players.LocalPlayer.Name.."||",
                                    ["thumbnail"] = {
                                        ["url"] = "https://tr.rbxcdn.com/56f0555ff8fe6322c0e687128bdd8ddc/150/150/Image/Png"},
                                    ["type"] = "rich",
                                    ["color"] = tonumber(0x7269da),
                                    ["fields"] = {
                                        {
                                            ["name"] = "**Time Elapsed**",
                                            ["value"] = tempo ,
                                            ["inline"] = true
                                        },
                                        {
                                            ["name"] = "**Wave**",
                                            ["value"] = waves ,
                                            ["inline"] = true
                                        },
                                        {
                                            ["name"] = "**Tier**",
                                            ["value"] = tier ,
                                            ["inline"] = true
                                        }
                                    }
                                }
                            }
                        }
                        local newdata = game:GetService("HttpService"):JSONEncode(data)
                        local headers = {
                        ["content-type"] = "application/json"
                        }
                        request = http_request or request or HttpPost or syn.request
                        local Webhook = {Url = url, Body = newdata, Method = "POST", Headers = headers}
                        request(Webhook)
                    end
                end)
                break
            end
        end
    end

    local WindowFocusReleasedFunction = function()
        RunService:Set3dRenderingEnabled(false)
        setfpscap(15)
        return
    end

    local WindowFocusedFunction = function()
        RunService:Set3dRenderingEnabled(true)
        setfpscap(360)
        return
    end

    local Initialize = function()
        UserInputService.WindowFocusReleased:Connect(WindowFocusReleasedFunction)
        UserInputService.WindowFocused:Connect(WindowFocusedFunction)
        return
    end
    Initialize()
end
