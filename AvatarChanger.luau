--[[
    Avatar Changer + Unlock All
    Standalone script for Blade Ball

    Features:
    - Avatar Changer: Copy any player's full appearance
    - Headless / Korblox toggles
    - Name Spoofer: Fake username + display name everywhere (including CoreGui/Tab/ESC)
    - Unlock All: All swords + explosions unlocked in shop, equippable
    - Customizable UI toggle keybind

    All client-side — only you see the changes.
    Requires an executor with CoreGui + hookfunction access.
]]

------------------------------------------------------------------------
-- SERVICES
------------------------------------------------------------------------
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CoreGui = game:GetService("CoreGui")
local TextChatService = game:GetService("TextChatService")
local InsertService = game:GetService("InsertService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")

-- Cleanup previous instance
if _G._AvatarChangerCleanup then
    pcall(_G._AvatarChangerCleanup)
end

------------------------------------------------------------------------
-- GLOBALS / EXECUTOR COMPAT
------------------------------------------------------------------------
local hookfunction = hookfunction or hookfunc or replaceclosure or detour_function
local getgenv = getgenv or function() return _G end
local env = getgenv()

------------------------------------------------------------------------
-- CONFIG
------------------------------------------------------------------------
local Config = {
    -- Avatar
    avatar_enabled = false,
    avatar_target = "",
    headless_enabled = false,
    korblox_enabled = false,

    -- Name Spoofer
    spoofer_enabled = false,
    spoof_username = "",
    spoof_displayname = "",
    spoof_avatar_user = "",

    -- Unlock All
    unlock_all_enabled = false,
    equipped_sword = nil,
    equipped_explosion = nil,

    -- UI
    toggle_key = Enum.KeyCode.RightShift,
}

------------------------------------------------------------------------
-- STATE
------------------------------------------------------------------------
local State = {
    connections = {},
    spoofer_connections = {},
    headless_conn = nil,
    korblox_conn = nil,

    -- Avatar
    avatar_applying = false,
    avatar_applied_id = nil,
    avatar_original_desc = nil,
    avatar_cache = {},
    avatar_original_parts = nil,
    avatar_respawn_token = 0,
    avatar_attempt_id = 0,

    -- Unlock All
    unlock_active = false,
    item_info = nil,
    inventory_shared = nil,
    inventory_client = nil,
    original_funcs = {},
    virtual_items_cache = {},
    shop_spoofed = false,
    equipped = { Sword = nil, Explosion = nil },
    equip_callbacks = { Sword = {}, Explosion = {} },
    inv_change_callbacks = { Sword = {}, Explosion = {} },
    merged_cache = { Sword = nil, Explosion = nil },
    merged_ref = { Sword = nil, Explosion = nil },
    owned_cache = { Sword = nil, Explosion = nil },
    keys_cache = { Sword = nil, Explosion = nil },
    static_fakes = { Sword = {}, Explosion = {}, _built = {} },
}

local function addConn(conn)
    table.insert(State.connections, conn)
end

local function cleanupAll()
    for _, c in ipairs(State.connections) do pcall(function() c:Disconnect() end) end
    State.connections = {}
    for _, c in ipairs(State.spoofer_connections) do pcall(function() c:Disconnect() end) end
    State.spoofer_connections = {}
    if State.headless_conn then pcall(function() State.headless_conn:Disconnect() end); State.headless_conn = nil end
    if State.korblox_conn then pcall(function() State.korblox_conn:Disconnect() end); State.korblox_conn = nil end

    -- Restore hooked inventory functions
    if State.inventory_shared and State.original_funcs then
        for k, v in pairs(State.original_funcs) do
            pcall(function() State.inventory_shared[k] = v end)
        end
    end
end

_G._AvatarChangerCleanup = cleanupAll

------------------------------------------------------------------------
-- UTILITY
------------------------------------------------------------------------
local function resolveUserId(input)
    if not input or input == "" then return nil end
    local num = tonumber(input)
    if num then return num end
    local ok, id = pcall(function() return Players:GetUserIdFromNameAsync(input) end)
    return ok and id or nil
end

local function escapePattern(s)
    return s:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%1")
end

local function replaceStr(str, find, rep)
    return str:gsub(escapePattern(find), rep)
end

------------------------------------------------------------------------
-- HEADLESS
------------------------------------------------------------------------
local function applyHeadless(char)
    local head = char:FindFirstChild("Head")
    if not head then return end
    head.Transparency = 1
    local d = head:FindFirstChildOfClass("Decal")
    if d then d:Destroy() end
end

local function removeHeadless(char)
    local head = char:FindFirstChild("Head")
    if head then head.Transparency = 0 end
end

local function setHeadless(on)
    Config.headless_enabled = on
    if State.headless_conn then State.headless_conn:Disconnect(); State.headless_conn = nil end
    local char = localPlayer.Character
    if on then
        if char then applyHeadless(char) end
        State.headless_conn = localPlayer.CharacterAdded:Connect(function(c) task.wait(0.1); if Config.headless_enabled then applyHeadless(c) end end)
    else
        if char then removeHeadless(char) end
    end
end

------------------------------------------------------------------------
-- KORBLOX
------------------------------------------------------------------------
local function applyKorblox(char)
    local rl = char:FindFirstChild("RightLeg") or char:FindFirstChild("Right Leg")
    if not rl then return end
    for _, c in ipairs(rl:GetChildren()) do
        if c:IsA("SpecialMesh") or c:IsA("Mesh") then c:Destroy() end
    end
    local m = Instance.new("SpecialMesh")
    m.MeshId = "rbxassetid://101851696"
    m.TextureId = "rbxassetid://115727863"
    m.Scale = Vector3.new(1, 1, 1)
    m.Parent = rl
end

local function removeKorblox(char)
    local rl = char:FindFirstChild("RightLeg") or char:FindFirstChild("Right Leg")
    if not rl then return end
    for _, c in ipairs(rl:GetChildren()) do
        if c:IsA("SpecialMesh") and c.MeshId == "rbxassetid://101851696" then c:Destroy() end
    end
end

local function setKorblox(on)
    Config.korblox_enabled = on
    if State.korblox_conn then State.korblox_conn:Disconnect(); State.korblox_conn = nil end
    local char = localPlayer.Character
    if on then
        if char then applyKorblox(char) end
        State.korblox_conn = localPlayer.CharacterAdded:Connect(function(c) task.wait(0.1); if Config.korblox_enabled then applyKorblox(c) end end)
    else
        if char then removeKorblox(char) end
    end
end

------------------------------------------------------------------------
-- AVATAR CHANGER
------------------------------------------------------------------------
local Avatar = {}

Avatar.saveOriginal = function()
    if State.avatar_original_desc then return end
    task.spawn(function()
        for i = 1, 5 do
            local ok, desc = pcall(Players.GetHumanoidDescriptionFromUserIdAsync, Players, localPlayer.UserId)
            if ok and desc then State.avatar_original_desc = desc; break end
            task.wait(0.3 * i)
        end
    end)
end

Avatar.getDesc = function(uid)
    if State.avatar_cache[uid] then return State.avatar_cache[uid] end
    for i = 1, 5 do
        local ok, desc = pcall(Players.GetHumanoidDescriptionFromUserIdAsync, Players, uid)
        if ok and desc then State.avatar_cache[uid] = desc; return desc end
        if i < 5 then task.wait(0.2 * i) end
    end
    return nil
end

Avatar.findBodyPart = function(char, name)
    if not name or name == "" then return nil end
    local p = char:FindFirstChild(name)
    if p and p:IsA("BasePart") then return p end
    local map = {
        ["Left Arm"]={"LeftUpperArm","LeftLowerArm","LeftHand"},
        ["Right Arm"]={"RightUpperArm","RightLowerArm","RightHand"},
        ["Left Leg"]={"LeftUpperLeg","LeftLowerLeg","LeftFoot"},
        ["Right Leg"]={"RightUpperLeg","RightLowerLeg","RightFoot"},
        ["Torso"]={"UpperTorso","LowerTorso"},
    }
    for _, n in ipairs(map[name] or {}) do
        local x = char:FindFirstChild(n)
        if x and x:IsA("BasePart") then return x end
    end
    return nil
end

Avatar.stripJoints = function(acc)
    for _, d in ipairs(acc:GetDescendants()) do
        if d:IsA("Weld") or d:IsA("Motor6D") or d:IsA("WeldConstraint") then d:Destroy() end
    end
end

Avatar.attachAccessory = function(parent, hum, acc)
    if not parent or not acc then return false end
    local clone = acc:Clone()
    Avatar.stripJoints(clone)
    local handle = clone:FindFirstChild("Handle")
    if not handle or not handle:IsA("BasePart") then clone:Destroy(); return false end
    handle.Anchored = false; handle.CanCollide = false; handle.Massless = true

    local origH = acc:FindFirstChild("Handle")
    local origW = origH and origH:FindFirstChild("AccessoryWeld")
    local c0, c1, target = CFrame.new(), CFrame.new(), nil

    if origW and origW:IsA("Weld") and origW.Part1 then
        target = Avatar.findBodyPart(parent, origW.Part1.Name)
        c0, c1 = origW.C0, origW.C1
    end
    if not target then
        local att = handle:FindFirstChildOfClass("Attachment")
        if att then
            for _, d in ipairs(parent:GetDescendants()) do
                if d:IsA("Attachment") and d.Name == att.Name and not d:IsDescendantOf(clone) then
                    target = d.Parent; c0 = att.CFrame; c1 = d.CFrame; break
                end
            end
        end
    end
    if not target then
        local at = clone.AccessoryType
        if at == Enum.AccessoryType.Hair or at == Enum.AccessoryType.Hat or at == Enum.AccessoryType.Face then
            target = parent:FindFirstChild("Head")
        end
        target = target or parent:FindFirstChild("Head") or parent:FindFirstChild("UpperTorso") or parent:FindFirstChild("Torso")
    end
    if target and target:IsA("BasePart") then
        local w = Instance.new("Weld"); w.Name = "AccessoryWeld"
        w.Part0 = handle; w.Part1 = target; w.C0 = c0; w.C1 = c1; w.Parent = handle
        clone.Parent = parent; return true
    end
    if hum then if pcall(function() hum:AddAccessory(clone) end) and clone.Parent == parent then return true end end
    clone:Destroy(); return false
end

Avatar.removeAccessories = function(char)
    for _, c in ipairs(char:GetChildren()) do
        if c:IsA("Accessory") or c:IsA("Hat") then c:Destroy() end
    end
end

Avatar.collectAccessories = function(model, desc)
    local accs, seen = {}, {}
    local function add(a) if not a or seen[a] then return end; seen[a]=true; table.insert(accs, a) end
    if model then
        for _, c in ipairs(model:GetChildren()) do if c:IsA("Accessory") or c:IsA("Hat") then add(c) end end
        if #accs == 0 then
            local h = model:FindFirstChildOfClass("Humanoid")
            if h then pcall(function() for _, a in ipairs(h:GetAccessories()) do add(a) end end) end
        end
    end
    if desc and #accs == 0 then
        for _, prop in ipairs({"HatAccessory","HairAccessory","FaceAccessory","NeckAccessory","ShouldersAccessory","FrontAccessory","BackAccessory","WaistAccessory"}) do
            local v = desc[prop]
            if v and v ~= "" then
                for m in tostring(v):gmatch("%d+") do
                    local id = tonumber(m)
                    if id and id > 0 then
                        pcall(function()
                            for _, obj in ipairs(InsertService:GetObjects("rbxassetid://"..id)) do
                                local ia = obj:IsA("Accessory") and obj or obj:FindFirstChildOfClass("Accessory")
                                if not ia then for _, d in ipairs(obj:GetDescendants()) do if d:IsA("Accessory") then ia=d; break end end end
                                if ia then add(ia) end
                            end
                        end)
                    end
                end
            end
        end
    end
    return accs
end

Avatar.transferAccFromTemp = function(parent, acc)
    if not parent or not acc then return false end
    local h = acc:FindFirstChild("Handle")
    if not h or not h:IsA("BasePart") then return false end
    h.Anchored = false; h.CanCollide = false; h.Massless = true
    local w = h:FindFirstChild("AccessoryWeld")
    if not w then for _, c in ipairs(h:GetChildren()) do if c:IsA("Weld") or c:IsA("WeldConstraint") then w=c; break end end end
    if w and w.Part1 then
        local t = Avatar.findBodyPart(parent, w.Part1.Name)
        if t then w.Part1 = t; acc.Parent = parent; return true end
    end
    return Avatar.attachAccessory(parent, nil, acc)
end

Avatar.applyAccessories = function(char, hum, temp, desc)
    Avatar.removeAccessories(char)
    local n = 0
    if temp then
        for _, c in ipairs(temp:GetChildren()) do
            if (c:IsA("Accessory") or c:IsA("Hat")) and Avatar.transferAccFromTemp(char, c) then n += 1 end
        end
        if n == 0 then
            local h = temp:FindFirstChildOfClass("Humanoid")
            if h then pcall(function() for _, a in ipairs(h:GetAccessories()) do if Avatar.transferAccFromTemp(char, a) then n+=1 end end end) end
        end
    end
    if n == 0 then
        for _, a in ipairs(Avatar.collectAccessories(nil, desc)) do
            if Avatar.attachAccessory(char, hum, a) then n += 1 end
        end
    end
    return n
end

Avatar.applyBodyScales = function(hum, desc)
    if not hum or not desc then return end
    for _, info in ipairs({
        {"BodyHeightScale",desc.HeightScale,false}, {"BodyWidthScale",desc.WidthScale,false},
        {"BodyDepthScale",desc.DepthScale,false}, {"HeadScale",desc.HeadScale,false},
        {"BodyTypeScale",desc.BodyTypeScale,true}, {"ProportionScale",desc.ProportionScale,true},
    }) do
        local name, val, allowZero = info[1], info[2], info[3]
        if typeof(val)=="number" and (val>0 or (allowZero and val>=0)) then
            local e = hum:FindFirstChild(name)
            if not e and hum.RigType == Enum.HumanoidRigType.R15 then
                e = Instance.new("NumberValue"); e.Name = name; e.Parent = hum
            end
            if e and e:IsA("NumberValue") then e.Value = val end
        end
    end
end

Avatar.applySpecial = function(char, desc)
    if not char or not desc then return end
    if desc.Head and (desc.Head == 15093053680 or desc.Head == 134082513) then pcall(applyHeadless, char) end
    if desc.RightLeg and desc.RightLeg == 139607718 then
        pcall(function()
            if char:FindFirstChild("RightLeg") or char:FindFirstChild("Right Leg") then applyKorblox(char); return end
            for _, n in ipairs({"RightUpperLeg","RightLowerLeg","RightFoot"}) do local p=char:FindFirstChild(n); if p then p.Transparency=1 end end
            local rul = char:FindFirstChild("RightUpperLeg")
            if rul and not rul:FindFirstChild("KorbloxLeg") then
                local pt = Instance.new("Part"); pt.Name="KorbloxLeg"; pt.CanCollide=false; pt.Massless=true; pt.Size=Vector3.new(1,2,1)
                local sm = Instance.new("SpecialMesh"); sm.MeshId="rbxassetid://101851696"; sm.TextureId="rbxassetid://115727863"; sm.Scale=Vector3.new(1,1,1); sm.Parent=pt
                local w = Instance.new("Weld"); w.Part0=rul; w.Part1=pt; w.C0=CFrame.new(0,-0.5,0); w.Parent=pt; pt.Parent=rul
            end
        end)
    end
end

Avatar.transferBodyMeshes = function(temp, char, hum)
    if not temp or not char then return end
    local th = temp:FindFirstChildOfClass("Humanoid")
    if th and th.RigType ~= Enum.HumanoidRigType.R15 then
        for _, c in ipairs(temp:GetChildren()) do
            if c:IsA("CharacterMesh") then
                pcall(function()
                    for _, c2 in ipairs(char:GetChildren()) do if c2:IsA("CharacterMesh") and c2.BodyPart==c.BodyPart then c2:Destroy() end end
                    c:Clone().Parent = char
                end)
            end
        end
        return
    end
    for _, pn in ipairs({"Head","UpperTorso","LowerTorso","LeftUpperArm","LeftLowerArm","LeftHand","RightUpperArm","RightLowerArm","RightHand","LeftUpperLeg","LeftLowerLeg","LeftFoot","RightUpperLeg","RightLowerLeg","RightFoot"}) do
        local src, dst = temp:FindFirstChild(pn), char:FindFirstChild(pn)
        if src and dst and src:IsA("BasePart") and dst:IsA("BasePart") then
            if src:IsA("MeshPart") and dst:IsA("MeshPart") then
                local ok = false; pcall(function() dst:ApplyMesh(src); ok=true end)
                if not ok then pcall(function() dst.MeshId = src.MeshId end) end
                pcall(function() dst.TextureID = src.TextureID end)
                pcall(function()
                    local sa = dst:FindFirstChildOfClass("SurfaceAppearance"); if sa then sa:Destroy() end
                    local sa2 = src:FindFirstChildOfClass("SurfaceAppearance"); if sa2 then sa2:Clone().Parent = dst end
                end)
            end
            dst = char:FindFirstChild(pn)
            if dst and dst:IsA("BasePart") then
                pcall(function() dst.Size = src.Size end)
                pcall(function()
                    for _, c in ipairs(src:GetChildren()) do
                        if c:IsA("Attachment") then local e = dst:FindFirstChild(c.Name); if e and e:IsA("Attachment") then e.CFrame = c.CFrame end end
                    end
                end)
            end
        end
    end
    pcall(function()
        for _, d in ipairs(temp:GetDescendants()) do
            if d:IsA("Motor6D") and d.Parent then
                local t = char:FindFirstChild(d.Parent.Name); t = t and t:FindFirstChild(d.Name)
                if t and t:IsA("Motor6D") then t.C0 = d.C0; t.C1 = d.C1 end
            end
        end
    end)
    if hum and th then pcall(function() hum.HipHeight = th.HipHeight end) end
end

Avatar.createTemp = function(desc, rigType)
    rigType = rigType or Enum.HumanoidRigType.R15
    local function try(rt)
        local ok, m = pcall(Players.CreateHumanoidModelFromDescriptionAsync, Players, desc, rt, Enum.AssetTypeVerification.Always)
        if not ok or not m then ok, m = pcall(Players.CreateHumanoidModelFromDescriptionAsync, Players, desc, rt) end
        if not ok or not m then return nil end
        m.Name = "_AvatarPreview"; m.Parent = ReplicatedStorage
        pcall(function() RunService.Heartbeat:Wait() end)
        return m
    end
    for i = 1, 3 do local m = try(rigType); if m then return m end; task.wait(0.35*i) end
    return try(rigType == Enum.HumanoidRigType.R15 and Enum.HumanoidRigType.R6 or Enum.HumanoidRigType.R15)
end

Avatar.clean = function(char)
    local tools = {}
    for _, c in ipairs(char:GetChildren()) do if c:IsA("Tool") or c:IsA("HopperBin") then table.insert(tools, c); c.Parent = nil end end
    local bp = char.Parent and char.Parent:FindFirstChild("Backpack")
    if bp then for _, c in ipairs(bp:GetChildren()) do if c:IsA("Tool") or c:IsA("HopperBin") then table.insert(tools, c) end end end
    local scripts = {}
    for _, d in ipairs(char:GetDescendants()) do if d:IsA("BaseScript") then scripts[d]=true; if d.Parent then scripts[d.Parent]=true end end end
    for _, c in ipairs(char:GetChildren()) do
        if not scripts[c] and (c:IsA("Accessory") or c:IsA("Hat") or c:IsA("BodyColors") or c:IsA("CharacterMesh") or c:IsA("Shirt") or c:IsA("Pants") or c:IsA("ShirtGraphic")) then
            c:Destroy()
        end
    end
    for _, t in ipairs(tools) do if t and t.Parent == nil then t.Parent = bp or char end end
end

Avatar.transferAppearance = function(temp, char, hum, desc)
    if not temp or not char or not hum then return false end
    pcall(function() if hum.ApplyDescriptionClientServer then hum:ApplyDescriptionClientServer(desc) else hum:ApplyDescription(desc) end end)
    Avatar.applyBodyScales(hum, desc)
    pcall(function() RunService.Heartbeat:Wait() end)
    Avatar.transferBodyMeshes(temp, char, hum)
    for _, cn in ipairs({"Shirt","Pants","ShirtGraphic"}) do
        local s = temp:FindFirstChildOfClass(cn); if s then local d = char:FindFirstChildOfClass(cn); if d then d:Destroy() end; s:Clone().Parent = char end
    end
    local sc = temp:FindFirstChildOfClass("BodyColors"); local dc = char:FindFirstChildOfClass("BodyColors")
    if not dc then dc = Instance.new("BodyColors"); dc.Parent = char end
    if sc then dc.HeadColor3=sc.HeadColor3; dc.TorsoColor3=sc.TorsoColor3; dc.LeftArmColor3=sc.LeftArmColor3; dc.RightArmColor3=sc.RightArmColor3; dc.LeftLegColor3=sc.LeftLegColor3; dc.RightLegColor3=sc.RightLegColor3 end
    if desc then dc.HeadColor3=desc.HeadColor; dc.TorsoColor3=desc.TorsoColor; dc.LeftArmColor3=desc.LeftArmColor; dc.RightArmColor3=desc.RightArmColor; dc.LeftLegColor3=desc.LeftLegColor; dc.RightLegColor3=desc.RightLegColor end
    local sh, dh = temp:FindFirstChild("Head"), char:FindFirstChild("Head")
    if sh and dh then
        local f = sh:FindFirstChild("face") or sh:FindFirstChildOfClass("Decal")
        if f then local f2 = dh:FindFirstChild("face") or dh:FindFirstChildOfClass("Decal"); if f2 then f2:Destroy() end; local cl = f:Clone(); cl.Name="face"; cl.Parent=dh end
    end
    Avatar.applySpecial(char, desc)
    Avatar.applyAccessories(char, hum, temp, desc)
    return true
end

Avatar.revert = function(char)
    if not char then return end
    pcall(removeHeadless, char); pcall(removeKorblox, char)
    pcall(function()
        for _, n in ipairs({"RightUpperLeg","RightLowerLeg","RightFoot"}) do local p=char:FindFirstChild(n); if p then p.Transparency=0 end end
        local rul=char:FindFirstChild("RightUpperLeg"); local kl=rul and rul:FindFirstChild("KorbloxLeg"); if kl then kl:Destroy() end
    end)
end

Avatar.applyDesc = function(desc, uid, isRevert)
    if State.avatar_applying then return end
    State.avatar_applying = true
    task.spawn(function()
        pcall(function()
            local char = localPlayer.Character or localPlayer.CharacterAdded:Wait()
            if not isRevert and not Config.avatar_enabled then State.avatar_applying = false; return end
            if not char then State.avatar_applying = false; return end
            local hum = char:FindFirstChildOfClass("Humanoid") or char:WaitForChild("Humanoid", 5)
            if not hum then State.avatar_applying = false; return end
            if not isRevert then Avatar.revert(char) end
            Avatar.clean(char)
            if not isRevert and not Config.avatar_enabled then State.avatar_applying = false; return end
            local temp = Avatar.createTemp(desc, hum.RigType)
            local ok = false
            if temp then ok = Avatar.transferAppearance(temp, char, hum, desc); temp:Destroy() end
            if not ok then
                pcall(function() if hum.ApplyDescriptionClientServer then hum:ApplyDescriptionClientServer(desc) else hum:ApplyDescription(desc) end end)
                Avatar.applyBodyScales(hum, desc); Avatar.applySpecial(char, desc)
                local bc = char:FindFirstChildOfClass("BodyColors"); if not bc then bc=Instance.new("BodyColors"); bc.Parent=char end
                bc.HeadColor3=desc.HeadColor; bc.TorsoColor3=desc.TorsoColor; bc.LeftArmColor3=desc.LeftArmColor; bc.RightArmColor3=desc.RightArmColor; bc.LeftLegColor3=desc.LeftLegColor; bc.RightLegColor3=desc.RightLegColor
                Avatar.applyAccessories(char, hum, nil, desc)
            end
        end)
        State.avatar_applying = false
    end)
end

Avatar.apply = function(target)
    if State.avatar_applying then return end
    State.avatar_attempt_id += 1; local aid = State.avatar_attempt_id
    task.spawn(function()
        if not Config.avatar_enabled or Config.avatar_target ~= target or State.avatar_attempt_id ~= aid then return end
        local uid = resolveUserId(target); if not uid then return end
        if State.avatar_applied_id == uid then return end
        local desc = Avatar.getDesc(uid); if not desc then return end
        if not Config.avatar_enabled or Config.avatar_target ~= target or State.avatar_attempt_id ~= aid then return end
        State.avatar_applied_id = uid
        Avatar.applyDesc(desc, uid)
    end)
end

Avatar.restore = function()
    if not State.avatar_original_desc then return end
    State.avatar_applied_id = nil; State.avatar_applying = false
    local char = localPlayer.Character
    if char then Avatar.revert(char) end
    Avatar.applyDesc(State.avatar_original_desc, localPlayer.UserId, true)
end

Avatar.reapplyOnSpawn = function(char)
    if not (Config.avatar_enabled and Config.avatar_target ~= "") then return end
    if not char then return end
    State.avatar_respawn_token += 1; local tk = State.avatar_respawn_token
    task.spawn(function()
        char:WaitForChild("Humanoid", 10); char:WaitForChild("HumanoidRootPart", 10)
        local loaded = false; pcall(function() loaded = localPlayer:HasAppearanceLoaded() end)
        if not loaded then
            local done = false
            local cn = localPlayer.CharacterAppearanceLoaded:Connect(function() done=true end)
            local t=0; while not done and t<6 do task.wait(0.1); t+=0.1; pcall(function() if localPlayer:HasAppearanceLoaded() then done=true end end) end
            if cn then cn:Disconnect() end
        end
        if State.avatar_respawn_token ~= tk or not Config.avatar_enabled then return end
        State.avatar_applying = false; State.avatar_applied_id = nil
        Avatar.apply(Config.avatar_target)
    end)
end

------------------------------------------------------------------------
-- NAME SPOOFER (PlayerGui + Workspace + CoreGui)
------------------------------------------------------------------------
local Spoofer = {}

Spoofer.getAvatarUid = function()
    local n = Config.spoof_avatar_user
    if not n or n == "" then return localPlayer.UserId end
    return resolveUserId(n) or localPlayer.UserId
end

Spoofer.hookText = function(label)
    if not label:IsA("TextLabel") and not label:IsA("TextButton") then return end
    local function upd()
        if not Config.spoofer_enabled then return end
        local t = label.Text; if typeof(t) ~= "string" or t == "" then return end
        local changed = false
        if Config.spoof_displayname ~= "" and string.find(t, localPlayer.DisplayName, 1, true) then
            changed = true; t = replaceStr(t, localPlayer.DisplayName, Config.spoof_displayname)
        end
        if Config.spoof_username ~= "" and string.find(t, localPlayer.Name, 1, true) then
            changed = true; t = replaceStr(t, localPlayer.Name, Config.spoof_username)
        end
        if changed then label.Text = t end
    end
    upd()
    table.insert(State.spoofer_connections, label:GetPropertyChangedSignal("Text"):Connect(upd))
end

Spoofer.hookImage = function(label)
    if not label:IsA("ImageLabel") and not label:IsA("ImageButton") then return end
    local function upd()
        if not Config.spoofer_enabled then return end
        local img = label.Image; if typeof(img) ~= "string" or img == "" then return end
        local myId = tostring(localPlayer.UserId)
        if string.find(img, myId, 1, true) then
            local sid = Spoofer.getAvatarUid()
            if sid ~= localPlayer.UserId then label.Image = string.gsub(img, myId, tostring(sid)) end
        end
    end
    upd()
    table.insert(State.spoofer_connections, label:GetPropertyChangedSignal("Image"):Connect(upd))
end

Spoofer.hookInst = function(inst)
    if inst:IsA("TextLabel") or inst:IsA("TextButton") then Spoofer.hookText(inst)
    elseif inst:IsA("ImageLabel") or inst:IsA("ImageButton") then Spoofer.hookImage(inst) end
end

Spoofer.hookContainer = function(container)
    for _, d in ipairs(container:GetDescendants()) do pcall(Spoofer.hookInst, d) end
    table.insert(State.spoofer_connections, container.DescendantAdded:Connect(function(d) pcall(Spoofer.hookInst, d) end))
end

Spoofer.hookChat = function()
    if not TextChatService then return end
    TextChatService.OnIncomingMessage = function(msg)
        local props = Instance.new("TextChatMessageProperties")
        if Config.spoofer_enabled and msg.TextSource and msg.TextSource.UserId == localPlayer.UserId then
            local p = msg.PrefixText
            if Config.spoof_displayname ~= "" then p = replaceStr(p, localPlayer.DisplayName, Config.spoof_displayname) end
            if Config.spoof_username ~= "" then p = replaceStr(p, localPlayer.Name, Config.spoof_username) end
            props.PrefixText = p
        end
        return props
    end
end

Spoofer.init = function()
    for _, c in ipairs(State.spoofer_connections) do pcall(function() c:Disconnect() end) end
    State.spoofer_connections = {}
    Spoofer.hookContainer(playerGui)
    Spoofer.hookContainer(workspace)
    pcall(function() Spoofer.hookContainer(CoreGui) end)
    Spoofer.hookChat()
end

------------------------------------------------------------------------
-- UNLOCK ALL SWORDS + EXPLOSIONS
------------------------------------------------------------------------
local Unlocker = {}

Unlocker.loadModules = function()
    if State.item_info and State.inventory_shared then return true end

    local ok1, itemInfo = pcall(function() return require(ReplicatedStorage.Shared.ItemInfo) end)
    if not ok1 or typeof(itemInfo) ~= "table" then return false end
    State.item_info = itemInfo

    local ok2, inv = pcall(function() return require(ReplicatedStorage.Shared.Inventory) end)
    if not ok2 or typeof(inv) ~= "table" then return false end

    local ok3, shared = pcall(function() return require(ReplicatedStorage.Shared.Inventory.Shared) end)
    if not ok3 or typeof(shared) ~= "table" then shared = inv.Shared end
    if typeof(shared) ~= "table" then return false end
    State.inventory_shared = shared

    local ok4, client = pcall(function() return inv.Client end)
    if ok4 and typeof(client) == "table" then State.inventory_client = client end

    return true
end

Unlocker.fakeItem = function(itemType, name)
    return { Id = name, Name = name }
end

Unlocker.getOwnedSet = function(itemType)
    if State.owned_cache[itemType] then return State.owned_cache[itemType] end
    local set = {}
    local orig = State.original_funcs.Get or State.inventory_shared.Get
    local items = orig(State.inventory_shared, nil, itemType)
    if typeof(items) == "table" then
        for _, item in pairs(items) do
            if typeof(item) == "table" and item.Name then set[item.Name] = true end
        end
    end
    State.owned_cache[itemType] = set
    return set
end

Unlocker.isOwned = function(itemType, name)
    if not name then return false end
    return Unlocker.getOwnedSet(itemType)[name] == true
end

Unlocker.getKeys = function(itemType)
    if State.keys_cache[itemType] then return State.keys_cache[itemType] end
    local keys = {}
    local catalog = State.item_info[itemType]
    if catalog then
        for k in pairs(catalog) do
            local ok, key = pcall(function()
                return State.inventory_shared:ItemToKey(itemType, Unlocker.fakeItem(itemType, k), {"Id"})
            end)
            if ok and key then keys[k] = key end
        end
    end
    State.keys_cache[itemType] = keys
    return keys
end

Unlocker.ensureStaticFakes = function(itemType)
    if State.static_fakes._built[itemType] then return end
    for k, key in pairs(Unlocker.getKeys(itemType)) do
        State.static_fakes[itemType][key] = Unlocker.fakeItem(itemType, k)
    end
    State.static_fakes._built[itemType] = true
end

Unlocker.hookInventory = function()
    local shared = State.inventory_shared
    local client = State.inventory_client
    local itemInfo = State.item_info
    if not shared or not itemInfo then return false end

    -- Save originals
    State.original_funcs = {
        Get = shared.Get,
        GetItem = shared.GetItem,
        GetEquipped = shared.GetEquipped,
        OnEquip = shared.OnEquip,
        OnInventoryChange = shared.OnInventoryChange,
        FindItemsWithKey = shared.FindItemsWithKey,
    }
    local orig = State.original_funcs

    -- Hook shared.Get — inject all items as owned
    shared.Get = function(self, player, itemType)
        local result = orig.Get(self, player, itemType)
        if not State.unlock_active or player ~= nil or (itemType ~= "Sword" and itemType ~= "Explosion") then
            return result
        end
        -- Check cache
        if State.merged_cache[itemType] and State.merged_ref[itemType] == result then
            return State.merged_cache[itemType]
        end
        local real = typeof(result) == "table" and result or {}
        local merged = table.clone(real)
        local existing = {}
        for _, item in pairs(real) do
            if typeof(item) == "table" and item.Name then existing[item.Name] = true end
        end
        Unlocker.ensureStaticFakes(itemType)
        for key, fakeItem in pairs(State.static_fakes[itemType]) do
            if not existing[fakeItem.Name] then
                merged[key] = fakeItem
            end
        end
        State.merged_cache[itemType] = merged
        State.merged_ref[itemType] = result
        return merged
    end

    -- Hook shared.GetItem — return fake item for anything in catalog
    shared.GetItem = function(self, player, itemType, itemName)
        local result = orig.GetItem(self, player, itemType, itemName)
        if result or not State.unlock_active or player ~= nil or (itemType ~= "Sword" and itemType ~= "Explosion") then
            return result
        end
        local catalog = itemInfo[itemType]
        if not catalog then return result end
        if catalog[itemName] then
            local fake = Unlocker.fakeItem(itemType, itemName)
            if itemType == "Sword" then
                local info = catalog[itemName]
                if info and info.HasFinisher then fake.Finisher = true end
                if info and info.AccessoryToggleable then fake.Accessory = true end
                if fake.Kills == nil then fake.Kills = 0 end
            end
            return fake
        end
        -- Try string-to-item conversion
        local ok, conv = pcall(function() return shared:StringToItem(itemType, itemName) end)
        if ok and typeof(conv) == "table" and conv.Name and catalog[conv.Name] then
            if conv.Id == nil then conv.Id = conv.Name end
            return conv
        end
        return result
    end

    -- Hook shared.GetEquipped — return our spoofed equipped item
    shared.GetEquipped = function(self, player, itemType)
        if State.unlock_active and player == nil and (itemType == "Sword" or itemType == "Explosion") then
            local equipped = State.equipped[itemType]
            if equipped then
                return equipped
            end
        end
        return orig.GetEquipped(self, player, itemType)
    end

    -- Hook shared.OnEquip
    shared.OnEquip = function(self, player, itemType, callback)
        if player == nil and (itemType == "Sword" or itemType == "Explosion") then
            table.insert(State.equip_callbacks[itemType], callback)
        end
        return orig.OnEquip(self, player, itemType, callback)
    end

    -- Hook shared.OnInventoryChange
    shared.OnInventoryChange = function(self, player, itemType, callback)
        if player == nil and (itemType == "Sword" or itemType == "Explosion") then
            table.insert(State.inv_change_callbacks[itemType], callback)
            return orig.OnInventoryChange(self, player, itemType, function(...)
                State.merged_cache[itemType] = nil
                State.merged_ref[itemType] = nil
                State.owned_cache[itemType] = nil
                return callback(...)
            end)
        end
        return orig.OnInventoryChange(self, player, itemType, callback)
    end

    -- Hook FindItemsWithKey
    if typeof(orig.FindItemsWithKey) == "function" then
        shared.FindItemsWithKey = function(self, player, itemType, key)
            local result = orig.FindItemsWithKey(self, player, itemType, key)
            if not State.unlock_active or player ~= nil or (itemType ~= "Sword" and itemType ~= "Explosion") then
                return result
            end
            if typeof(result) == "table" and #result > 0 then return result end
            local catalog = itemInfo[itemType]
            local itemName = key
            if not (catalog and catalog[key]) then
                if client and typeof(client.KeyToItem) == "function" then
                    local ok, conv = pcall(function() return client:KeyToItem(key) end)
                    if ok and typeof(conv) == "table" and conv.Name then itemName = conv.Name end
                end
            end
            if itemName and catalog and catalog[itemName] and not Unlocker.isOwned(itemType, itemName) then
                return { itemName }
            end
            return result
        end
    end

    -- Hook client Equip/Unequip
    if client then
        local origEquip = client.Equip
        local origUnequip = client.Unequip

        if origEquip then
            client.Equip = function(self, itemId, ...)
                if State.unlock_active then
                    local name = itemId
                    if typeof(itemId) == "table" then name = itemId.Id or itemId.Name or itemId.ItemId end
                    if typeof(name) == "string" then
                        if itemInfo.Sword[name] then
                            Unlocker.equipSword(name); return true
                        elseif itemInfo.Explosion[name] then
                            Unlocker.equipExplosion(name); return true
                        end
                    end
                end
                return origEquip(self, itemId, ...)
            end
        end

        if origUnequip then
            client.Unequip = function(self, itemType, ...)
                if State.unlock_active and (itemType == "Sword" or itemType == "Explosion") then
                    State.equipped[itemType] = nil
                    Unlocker.fireEquipChange(itemType)
                    return true
                end
                return origUnequip(self, itemType, ...)
            end
        end
    end

    -- Hook GetAttribute for sword display
    if hookfunction then
        pcall(function()
            local origGetAttr = game.GetAttribute
            local hooked = hookfunction(game.GetAttribute, function(self, attr)
                if State.unlock_active and (attr == "CurrentlyEquippedSword" or attr == "ShowSwordAccessory") then
                    if attr == "CurrentlyEquippedSword" and State.equipped.Sword then
                        return State.equipped.Sword
                    end
                end
                return origGetAttr(self, attr)
            end)
        end)
    end

    return true
end

Unlocker.fireEquipChange = function(itemType)
    for _, cb in ipairs(State.equip_callbacks[itemType] or {}) do
        task.spawn(cb, State.equipped[itemType])
    end
end

Unlocker.equipSword = function(name)
    if not State.item_info or not State.item_info.Sword[name] then return end
    State.equipped.Sword = name
    env.equipped_sword = name
    env.sword_name = name
    Unlocker.fireEquipChange("Sword")
    -- Destroy old sword model and trigger rebuild
    local char = localPlayer.Character
    if char then
        for _, c in ipairs(char:GetChildren()) do
            if c:IsA("Model") and State.item_info.Sword[c.Name] then c:Destroy() end
        end
    end
end

Unlocker.equipExplosion = function(name)
    if not State.item_info or not State.item_info.Explosion[name] then return end
    State.equipped.Explosion = name
    env.equipped_explosion = name
    env.explosion_name = name
    Unlocker.fireEquipChange("Explosion")
end

Unlocker.refreshShop = function()
    -- Find the shop controller and force refresh virtual items
    pcall(function()
        local controllers = ReplicatedStorage:FindFirstChild("Controllers")
        if not controllers then return end
        local shopCtrl = controllers:FindFirstChild("ShopController", true)
        if not shopCtrl then return end
        local mod = require(shopCtrl)
        if typeof(mod) == "table" and mod._virtualItems then
            for itemType, items in pairs(mod._virtualItems) do
                if itemType == "Sword" or itemType == "Explosion" then
                    for key, vItem in pairs(items) do
                        if typeof(vItem) == "table" then
                            -- Force OwnsItem to true
                            if typeof(vItem.OwnsItem) == "table" and typeof(vItem.OwnsItem.Set) == "function" then
                                pcall(vItem.OwnsItem.Set, vItem.OwnsItem, true)
                            end
                            -- Force ForceHide to false (show the item)
                            if typeof(vItem.ForceHide) == "table" and typeof(vItem.ForceHide.Set) == "function" then
                                pcall(vItem.ForceHide.Set, vItem.ForceHide, false)
                            end
                            -- Set section to Owned
                            if typeof(vItem.Section) == "table" and typeof(vItem.Section.Set) == "function" then
                                local equippedName = State.equipped[itemType]
                                local name = vItem.Name or key
                                local section = (equippedName and (name == equippedName or vItem.Id == equippedName)) and "Equipped" or "Owned"
                                pcall(vItem.Section.Set, vItem.Section, section)
                            end
                            vItem.NonPurchaseable = true
                        end
                    end
                end
            end
        end
    end)
end

Unlocker.enable = function()
    if not Unlocker.loadModules() then
        warn("[Unlock All] Failed to load game modules")
        return false
    end
    if not next(State.original_funcs) then
        if not Unlocker.hookInventory() then
            warn("[Unlock All] Failed to hook inventory")
            return false
        end
    end
    State.unlock_active = true
    Config.unlock_all_enabled = true
    -- Clear caches so hooks pick up
    State.merged_cache = { Sword = nil, Explosion = nil }
    State.merged_ref = { Sword = nil, Explosion = nil }
    State.owned_cache = { Sword = nil, Explosion = nil }
    State.shop_spoofed = false
    -- Refresh shop after short delay
    task.delay(0.5, function()
        Unlocker.refreshShop()
        State.shop_spoofed = true
    end)
    return true
end

Unlocker.disable = function()
    State.unlock_active = false
    Config.unlock_all_enabled = false
    State.merged_cache = { Sword = nil, Explosion = nil }
    State.merged_ref = { Sword = nil, Explosion = nil }
    -- Shop will revert on next open since hooks check unlock_active
end

------------------------------------------------------------------------
-- UI
------------------------------------------------------------------------
local function createUI()
    local old = CoreGui:FindFirstChild("AvatarChangerGui")
    if old then old:Destroy() end
    old = playerGui:FindFirstChild("AvatarChangerGui")
    if old then old:Destroy() end

    local gui = Instance.new("ScreenGui")
    gui.Name = "AvatarChangerGui"
    gui.ResetOnSpawn = false
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.DisplayOrder = 999
    pcall(function() gui.Parent = CoreGui end)
    if not gui.Parent then gui.Parent = playerGui end

    -- Theme
    local C = {
        bg        = Color3.fromRGB(18, 18, 26),
        card      = Color3.fromRGB(28, 28, 40),
        header    = Color3.fromRGB(22, 22, 32),
        accent    = Color3.fromRGB(130, 90, 255),
        accent2   = Color3.fromRGB(90, 200, 140),
        input     = Color3.fromRGB(35, 35, 50),
        text      = Color3.fromRGB(225, 225, 235),
        dim       = Color3.fromRGB(120, 120, 145),
        on        = Color3.fromRGB(90, 210, 130),
        off       = Color3.fromRGB(65, 65, 85),
        danger    = Color3.fromRGB(220, 70, 70),
        border    = Color3.fromRGB(50, 50, 70),
    }

    local tweenInfo = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

    -- Main
    local main = Instance.new("Frame")
    main.Size = UDim2.new(0, 320, 0, 500)
    main.Position = UDim2.new(1, -340, 0.5, -250)
    main.BackgroundColor3 = C.bg
    main.BorderSizePixel = 0
    main.Active = true
    main.Draggable = true
    main.Parent = gui
    Instance.new("UICorner", main).CornerRadius = UDim.new(0, 12)
    local mainStroke = Instance.new("UIStroke", main)
    mainStroke.Color = C.border; mainStroke.Thickness = 1

    -- Shadow
    local shadow = Instance.new("ImageLabel")
    shadow.Size = UDim2.new(1, 30, 1, 30)
    shadow.Position = UDim2.new(0, -15, 0, -15)
    shadow.BackgroundTransparency = 1
    shadow.Image = "rbxassetid://5554236805"
    shadow.ImageColor3 = Color3.fromRGB(0, 0, 0)
    shadow.ImageTransparency = 0.6
    shadow.ScaleType = Enum.ScaleType.Slice
    shadow.SliceCenter = Rect.new(23, 23, 277, 277)
    shadow.ZIndex = -1
    shadow.Parent = main

    -- Header
    local header = Instance.new("Frame")
    header.Size = UDim2.new(1, 0, 0, 44)
    header.BackgroundColor3 = C.header
    header.BorderSizePixel = 0
    header.Parent = main
    local hc = Instance.new("UICorner", header); hc.CornerRadius = UDim.new(0, 12)
    local hfill = Instance.new("Frame", header); hfill.Size = UDim2.new(1, 0, 0, 14); hfill.Position = UDim2.new(0, 0, 1, -14); hfill.BackgroundColor3 = C.header; hfill.BorderSizePixel = 0

    -- Accent bar under header
    local accentBar = Instance.new("Frame", main)
    accentBar.Size = UDim2.new(1, -24, 0, 2)
    accentBar.Position = UDim2.new(0, 12, 0, 44)
    accentBar.BackgroundColor3 = C.accent
    accentBar.BorderSizePixel = 0
    Instance.new("UICorner", accentBar).CornerRadius = UDim.new(0, 1)

    local title = Instance.new("TextLabel", header)
    title.Size = UDim2.new(1, -80, 1, 0); title.Position = UDim2.new(0, 16, 0, 0)
    title.BackgroundTransparency = 1; title.Text = "⚡ Avatar Changer"
    title.TextColor3 = C.text; title.TextSize = 15; title.Font = Enum.Font.GothamBold
    title.TextXAlignment = Enum.TextXAlignment.Left

    -- Minimize
    local minBtn = Instance.new("TextButton", header)
    minBtn.Size = UDim2.new(0, 28, 0, 28); minBtn.Position = UDim2.new(1, -68, 0, 8)
    minBtn.BackgroundColor3 = C.input; minBtn.Text = "—"; minBtn.TextColor3 = C.dim
    minBtn.TextSize = 14; minBtn.Font = Enum.Font.GothamBold; minBtn.BorderSizePixel = 0
    Instance.new("UICorner", minBtn).CornerRadius = UDim.new(0, 6)

    -- Close
    local closeBtn = Instance.new("TextButton", header)
    closeBtn.Size = UDim2.new(0, 28, 0, 28); closeBtn.Position = UDim2.new(1, -36, 0, 8)
    closeBtn.BackgroundColor3 = C.danger; closeBtn.BackgroundTransparency = 0.7
    closeBtn.Text = "✕"; closeBtn.TextColor3 = C.dim
    closeBtn.TextSize = 12; closeBtn.Font = Enum.Font.GothamBold; closeBtn.BorderSizePixel = 0
    Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 6)

    closeBtn.MouseButton1Click:Connect(function() main.Visible = false end)
    minBtn.MouseButton1Click:Connect(function() main.Visible = false end)

    -- Scroll
    local scroll = Instance.new("ScrollingFrame", main)
    scroll.Size = UDim2.new(1, -16, 1, -56); scroll.Position = UDim2.new(0, 8, 0, 52)
    scroll.BackgroundTransparency = 1; scroll.BorderSizePixel = 0
    scroll.ScrollBarThickness = 3; scroll.ScrollBarImageColor3 = C.accent
    scroll.CanvasSize = UDim2.new(0, 0, 0, 0); scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    local lay = Instance.new("UIListLayout", scroll); lay.Padding = UDim.new(0, 4); lay.SortOrder = Enum.SortOrder.LayoutOrder

    local order = 0
    local function nextOrd() order += 1; return order end

    local function mkSection(text)
        local f = Instance.new("Frame", scroll)
        f.Size = UDim2.new(1, 0, 0, 28); f.BackgroundTransparency = 1; f.LayoutOrder = nextOrd()
        local l = Instance.new("TextLabel", f)
        l.Size = UDim2.new(1, -8, 1, 0); l.Position = UDim2.new(0, 8, 0, 0)
        l.BackgroundTransparency = 1; l.Text = text; l.TextColor3 = C.accent
        l.TextSize = 11; l.Font = Enum.Font.GothamBold; l.TextXAlignment = Enum.TextXAlignment.Left
        l.TextTransparency = 0.15
    end

    local function mkToggle(text, default, cb)
        local f = Instance.new("Frame", scroll)
        f.Size = UDim2.new(1, -4, 0, 34); f.BackgroundColor3 = C.card; f.BorderSizePixel = 0; f.LayoutOrder = nextOrd()
        Instance.new("UICorner", f).CornerRadius = UDim.new(0, 8)
        local l = Instance.new("TextLabel", f)
        l.Size = UDim2.new(1, -56, 1, 0); l.Position = UDim2.new(0, 12, 0, 0)
        l.BackgroundTransparency = 1; l.Text = text; l.TextColor3 = C.text
        l.TextSize = 12; l.Font = Enum.Font.Gotham; l.TextXAlignment = Enum.TextXAlignment.Left

        local bg = Instance.new("Frame", f)
        bg.Size = UDim2.new(0, 38, 0, 20); bg.Position = UDim2.new(1, -46, 0.5, -10)
        bg.BackgroundColor3 = default and C.on or C.off; bg.BorderSizePixel = 0
        Instance.new("UICorner", bg).CornerRadius = UDim.new(1, 0)

        local dot = Instance.new("Frame", bg)
        dot.Size = UDim2.new(0, 14, 0, 14)
        dot.Position = default and UDim2.new(1, -16, 0.5, -7) or UDim2.new(0, 2, 0.5, -7)
        dot.BackgroundColor3 = Color3.new(1, 1, 1); dot.BorderSizePixel = 0
        Instance.new("UICorner", dot).CornerRadius = UDim.new(1, 0)

        local state = default
        local btn = Instance.new("TextButton", f)
        btn.Size = UDim2.new(1, 0, 1, 0); btn.BackgroundTransparency = 1; btn.Text = ""
        btn.MouseButton1Click:Connect(function()
            state = not state
            TweenService:Create(bg, tweenInfo, {BackgroundColor3 = state and C.on or C.off}):Play()
            TweenService:Create(dot, tweenInfo, {Position = state and UDim2.new(1, -16, 0.5, -7) or UDim2.new(0, 2, 0.5, -7)}):Play()
            cb(state)
        end)
        return function(v) state=v; bg.BackgroundColor3 = v and C.on or C.off; dot.Position = v and UDim2.new(1,-16,0.5,-7) or UDim2.new(0,2,0.5,-7) end
    end

    local function mkInput(placeholder, default, cb)
        local f = Instance.new("Frame", scroll)
        f.Size = UDim2.new(1, -4, 0, 32); f.BackgroundColor3 = C.input; f.BorderSizePixel = 0; f.LayoutOrder = nextOrd()
        Instance.new("UICorner", f).CornerRadius = UDim.new(0, 8)
        local box = Instance.new("TextBox", f)
        box.Size = UDim2.new(1, -16, 1, 0); box.Position = UDim2.new(0, 8, 0, 0)
        box.BackgroundTransparency = 1; box.PlaceholderText = placeholder; box.PlaceholderColor3 = C.dim
        box.Text = default or ""; box.TextColor3 = C.text; box.TextSize = 12; box.Font = Enum.Font.Gotham
        box.TextXAlignment = Enum.TextXAlignment.Left; box.ClearTextOnFocus = false
        box.FocusLost:Connect(function() cb(box.Text) end)
        return box
    end

    local function mkButton(text, color, cb)
        local btn = Instance.new("TextButton", scroll)
        btn.Size = UDim2.new(1, -4, 0, 30); btn.BackgroundColor3 = color or C.accent
        btn.BorderSizePixel = 0; btn.Text = text; btn.TextColor3 = Color3.new(1, 1, 1)
        btn.TextSize = 12; btn.Font = Enum.Font.GothamBold; btn.LayoutOrder = nextOrd()
        Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 8)
        btn.MouseButton1Click:Connect(cb)
        return btn
    end

    local function mkSpacer(h)
        local f = Instance.new("Frame", scroll)
        f.Size = UDim2.new(1, 0, 0, h or 4); f.BackgroundTransparency = 1; f.LayoutOrder = nextOrd()
    end

    ---- SECTIONS ----

    -- Avatar Changer
    mkSection("AVATAR CHANGER")
    local avatarInput = mkInput("Username or UserId to copy...", "", function(t) Config.avatar_target = t; Config.spoof_avatar_user = t end)
    mkToggle("Enable Avatar Changer", false, function(on)
        Config.avatar_enabled = on
        if on then Avatar.saveOriginal(); if Config.avatar_target ~= "" then Avatar.apply(Config.avatar_target) end
        else Avatar.restore() end
    end)
    mkButton("🔄  Restore Original", Color3.fromRGB(70, 70, 95), function()
        Config.avatar_enabled = false; Avatar.restore()
    end)

    mkSpacer(6)

    -- Quick Toggles
    mkSection("QUICK TOGGLES")
    mkToggle("Headless", false, setHeadless)
    mkToggle("Korblox Leg", false, setKorblox)

    mkSpacer(6)

    -- Name Spoofer
    mkSection("NAME SPOOFER")
    mkToggle("Enable Name Spoofer", false, function(on)
        Config.spoofer_enabled = on
        if on then Spoofer.init() end
    end)
    mkInput("Spoofed Username", "", function(t) Config.spoof_username = t end)
    mkInput("Spoofed Display Name", "", function(t) Config.spoof_displayname = t end)
    mkInput("Avatar Thumbnail User", "", function(t) Config.spoof_avatar_user = t end)

    mkSpacer(6)

    -- Unlock All
    mkSection("UNLOCK ALL")
    local unlockStatus = Instance.new("TextLabel", scroll)
    unlockStatus.Size = UDim2.new(1, -4, 0, 20); unlockStatus.BackgroundTransparency = 1
    unlockStatus.Text = "  Status: Off"; unlockStatus.TextColor3 = C.dim
    unlockStatus.TextSize = 11; unlockStatus.Font = Enum.Font.Gotham
    unlockStatus.TextXAlignment = Enum.TextXAlignment.Left; unlockStatus.LayoutOrder = nextOrd()

    mkToggle("Unlock All Swords + Explosions", false, function(on)
        if on then
            unlockStatus.Text = "  Status: Loading..."
            task.spawn(function()
                local ok = Unlocker.enable()
                unlockStatus.Text = ok and "  Status: Active ✓" or "  Status: Failed ✗"
                unlockStatus.TextColor3 = ok and C.accent2 or C.danger
            end)
        else
            Unlocker.disable()
            unlockStatus.Text = "  Status: Off"
            unlockStatus.TextColor3 = C.dim
        end
    end)

    local note = Instance.new("TextLabel", scroll)
    note.Size = UDim2.new(1, -4, 0, 32); note.BackgroundTransparency = 1
    note.Text = "  Open the sword/explosion shop after enabling.\n  Click any item to equip it."
    note.TextColor3 = C.dim; note.TextSize = 10; note.Font = Enum.Font.Gotham
    note.TextXAlignment = Enum.TextXAlignment.Left; note.TextWrapped = true; note.LayoutOrder = nextOrd()

    mkSpacer(6)

    -- Keybind
    mkSection("SETTINGS")

    local keybindFrame = Instance.new("Frame", scroll)
    keybindFrame.Size = UDim2.new(1, -4, 0, 34); keybindFrame.BackgroundColor3 = C.card; keybindFrame.BorderSizePixel = 0; keybindFrame.LayoutOrder = nextOrd()
    Instance.new("UICorner", keybindFrame).CornerRadius = UDim.new(0, 8)

    local kLabel = Instance.new("TextLabel", keybindFrame)
    kLabel.Size = UDim2.new(0.5, 0, 1, 0); kLabel.Position = UDim2.new(0, 12, 0, 0)
    kLabel.BackgroundTransparency = 1; kLabel.Text = "Toggle Key"; kLabel.TextColor3 = C.text
    kLabel.TextSize = 12; kLabel.Font = Enum.Font.Gotham; kLabel.TextXAlignment = Enum.TextXAlignment.Left

    local kBtn = Instance.new("TextButton", keybindFrame)
    kBtn.Size = UDim2.new(0.4, 0, 0, 22); kBtn.Position = UDim2.new(0.55, 0, 0.5, -11)
    kBtn.BackgroundColor3 = C.input; kBtn.BorderSizePixel = 0
    kBtn.Text = Config.toggle_key.Name; kBtn.TextColor3 = C.accent
    kBtn.TextSize = 11; kBtn.Font = Enum.Font.GothamBold
    Instance.new("UICorner", kBtn).CornerRadius = UDim.new(0, 6)

    local listening = false
    kBtn.MouseButton1Click:Connect(function()
        if listening then return end
        listening = true
        kBtn.Text = "..."
        kBtn.TextColor3 = C.on
        local conn
        conn = UserInputService.InputBegan:Connect(function(input, gpe)
            if input.UserInputType == Enum.UserInputType.Keyboard then
                Config.toggle_key = input.KeyCode
                kBtn.Text = input.KeyCode.Name
                kBtn.TextColor3 = C.accent
                listening = false
                conn:Disconnect()
            end
        end)
    end)

    -- Keybind listener
    UserInputService.InputBegan:Connect(function(input, gpe)
        if gpe then return end
        if input.KeyCode == Config.toggle_key then
            main.Visible = not main.Visible
        end
    end)

    -- Respawn hook
    addConn(localPlayer.CharacterAdded:Connect(function(char) Avatar.reapplyOnSpawn(char) end))

    -- Continuous shop refresh while unlock is active
    task.spawn(function()
        while gui.Parent do
            if State.unlock_active then
                pcall(Unlocker.refreshShop)
            end
            task.wait(2)
        end
    end)

    return gui
end

------------------------------------------------------------------------
-- INIT
------------------------------------------------------------------------
Avatar.saveOriginal()
local gui = createUI()

print("[Avatar Changer] Loaded! Press " .. Config.toggle_key.Name .. " to toggle UI.")
print("[Avatar Changer] Change the keybind in Settings section.")
