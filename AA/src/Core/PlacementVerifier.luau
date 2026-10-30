-- Placement ownership, UUID counting and spawn confirmation; unchanged behavior.
return function(cfg, player)
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
                    if distance<best and distance<=40 then closest,best=unit,distance end
                end
            end
        end
    end
    return closest
end
return {ownedSnapshot=ownedSnapshot,countOwnedByUuid=countOwnedByUuid,existingPositions=existingPositions,matchingNewUnit=matchingNewUnit}
end
