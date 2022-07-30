repeat
    wait()
until game:IsLoaded()
wait(5)
if game.PlaceId == 4996049426 or game.PlaceId == 7785334488 then
    _G.AutoStarPass = true
    _G.AutoEvo = true
  
    local EX = {
        [1] = "VoteGameMode",
        [2] = "Extreme"
    }

    local FW = {
        [1] = "SpeedChange",
        [2] = true
    }

    local POS1 = {
        [1] = "Summon",
        [2] = {
            ["Rotation"] = 0,
            ["cframe"] = CFrame.new(Vector3.new(-22.2338924, 147.89859, -146.197418), Vector3.new(-0, -0, -1)),
            ["Unit"] = "EXP IV"
        }
    }

    local POS2 = {
        [1] = "Summon",
        [2] = {
            ["Rotation"] = 0,
            ["cframe"] = CFrame.new(Vector3.new(-19.7601013, 147.89859, -146.010712), Vector3.new(-0, -0, -1)),
            ["Unit"] = "EXP IV"
        }
    }

    local POS3 = {
        [1] = "Summon",
        [2] = {
            ["Rotation"] = 0,
            ["cframe"] = CFrame.new(Vector3.new(7.69565487, 147.898544, -103.106163), Vector3.new(-0, -0, -1)),
            ["Unit"] = "EXP IV"
        }
    }

    local POS4 = {
        [1] = "Summon",
        [2] = {
            ["Rotation"] = 0,
            ["cframe"] = CFrame.new(Vector3.new(36.6010399, 147.898544, -103.24054), Vector3.new(-0, -0, -1)),
            ["Unit"] = "EXP IV"
        }
    }

    local POS5 = {
        [1] = "Summon",
        [2] = {
            ["Rotation"] = 0,
            ["cframe"] = CFrame.new(Vector3.new(-14.2545605, 147.898499, -87.3711166), Vector3.new(-0, -0, -1)),
            ["Unit"] = "EXP IV"
        }
    }

    local POS6 = {
        [1] = "Summon",
        [2] = {
            ["Rotation"] = 0,
            ["cframe"] = CFrame.new(Vector3.new(4.87790585, 147.898544, -90.290741), Vector3.new(-0, -0, -1)),
            ["Unit"] = "EXP IV"
        }
    }

    local POS7 = {
        [1] = "Summon",
        [2] = {
            ["Rotation"] = 0,
            ["cframe"] = CFrame.new(Vector3.new(-14.3309078, 147.898499, -68.2787628), Vector3.new(-0, -0, -1)),
            ["Unit"] = "EXP IV"
        }
    }

    local POS8 = {
        [1] = "Summon",
        [2] = {
            ["Rotation"] = 0,
            ["cframe"] = CFrame.new(Vector3.new(39.8213234, 147.898544, -88.4201508), Vector3.new(-0, -0, -1)),
            ["Unit"] = "EXP IV"
        }
    }

    local vim = game:GetService("VirtualInputManager")

    function click(x, y, button)
        spawn(function()
            button -= 1
            vim:SendMouseButtonEvent(x, y, button, true, game, 0)
            vim:SendMouseButtonEvent(x, y, button, false, game, 0)
        end)
    end

    local gs = game:GetService("ReplicatedStorage").Remotes.Input
    local UserInputService = game:GetService("UserInputService")
    local RunService = game:GetService("RunService")

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

    local EXP4 = { [1] = "UpgradeUnit" ,[2] = "EXP III" ,[3] = 2 }
    local EXP3 = { [1] = "UpgradeUnit" ,[2] = "EXP II"  ,[3] = 2 }
    local EXP2 = { [1] = "UpgradeUnit" ,[2] = "EXP I"   ,[3] = 2 }
    
    local start = {
    [1] = "Start"
    }

    local inf = {
        [1] = "InfLevel",
        [2] = "-1.7",
        [3] = false
    }

    Initialize()

    function EvoEXP()
        spawn(function()
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
            local i = 1
            while _G.AutoStarPass == true do
                RunService:Set3dRenderingEnabled(false)
                gs:FireServer(unpack(EX))
                wait(1)
                gs:FireServer(unpack(FW))
                wait(1)
                gs:FireServer(unpack(POS1))
                wait(1)
                gs:FireServer(unpack(POS2))
                wait(1)
                gs:FireServer(unpack(POS3))
                wait(1)
                gs:FireServer(unpack(POS4))
                wait(1)
                gs:FireServer(unpack(POS5))
                wait(1)
                gs:FireServer(unpack(POS6))
                wait(1)
                gs:FireServer(unpack(POS7))
                wait(1)
                gs:FireServer(unpack(POS8))
                wait(1)
                i = i + 1 
                if i > 9 then break end
            end
        end)
    end

    function AutoReplay()
        spawn(function()
            while _G.AutoStarPass == true do
                click(750, 550, 1)
                wait(1)
                click(1870, 1030, 1)
                wait(1)
            end
        end)
    end

    function AutoJoin()
        spawn(function()
            while _G.AutoStarPass == true do
                if game.PlaceId == 4996049426 then
                    game:GetService("Players").LocalPlayer.Character.HumanoidRootPart.CFrame = game:GetService("Workspace").Queue.Infinite.InfiniteMode.CFrame 
                end
                if game.PlaceId == 7785334488 then
                    game:GetService("Players").LocalPlayer.Character.HumanoidRootPart.CFrame = game:GetService("Workspace").Queue.Joinables.InfiniteMode.CFrame
                end
                wait(2)
                gs:FireServer(unpack(inf))
                wait(1)
                gs:FireServer(unpack(start))
                wait(15)
            end
        end)
    end

    EvoEXP()
    AutoJoin()
    PlaceUnit()
    AutoReplay()
    syn.queue_on_teleport("loadstring(game:HttpGet('https://raw.githubusercontent.com/sayoui001/RobloxLuaScript/main/ASTD/AutoFarmStarpass.lua'))()")
end
