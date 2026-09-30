--[[
    Avatar Changer + Unlock All
    Standalone script for Blade Ball

    Features:
    - Avatar Changer: Copy any player's full appearance
    - Headless / Korblox toggles
    - Name Spoofer: Fake username + display name everywhere (including CoreGui/Tab/ESC)
    - Unlock All: All swords + explosions unlocked in shop, equippable, deleteable
    - Customizable UI toggle keybind
    - Config persistence (saves/loads between executions)

    All client-side — only you see the changes.
    Requires an executor with CoreGui + hookfunction access.
]]

------------------------------------------------------------------------
-- GLOBALS / EXECUTOR COMPAT
------------------------------------------------------------------------
local hookfunction = hookfunction or hookfunc or replaceclosure or detour_function
local getgenv = getgenv or function() return _G end
local env = getgenv()
local writefile = writefile or function() end
local readfile = readfile or function() return nil end
local isfile = isfile or function() return false end
local newcclosure = newcclosure or function(f) return f end
local cloneref = cloneref or function(o) return o end
local getrawmetatable = getrawmetatable or getmetatable
local setreadonly = setreadonly or function() end
local getconnections = getconnections or get_signal_cons or nil
local getupvalues = getupvalues or getupvals or debug and debug.getupvalues or nil
local setupvalue = setupvalue or setupval or debug and debug.setupvalue or nil
local getupvalue = getupvalue or getupval or debug and debug.getupvalue or nil
local islclosure = islclosure or isourclosure or is_l_closure or isluaclosure or nil
local getinfo = getinfo or debug and debug.getinfo or nil
local setthreadidentity = setthreadidentity or setidentity or setthreadcontext or nil
local getthreadidentity = getthreadidentity or getidentity or getthreadcontext or nil

------------------------------------------------------------------------
-- SERVICES (cloneref where supported to reduce anti-cheat surface)
------------------------------------------------------------------------
local function safeClone(svc)
    local ok, result = pcall(cloneref, svc)
    return ok and result or svc
end
local Players = safeClone(game:GetService("Players"))
local RunService = safeClone(game:GetService("RunService"))
local ReplicatedStorage = safeClone(game:GetService("ReplicatedStorage"))
local CoreGui = safeClone(game:GetService("CoreGui"))
local TextChatService = safeClone(game:GetService("TextChatService"))
local InsertService = safeClone(game:GetService("InsertService"))
local UserInputService = safeClone(game:GetService("UserInputService"))
local TweenService = safeClone(game:GetService("TweenService"))
local HttpService = safeClone(game:GetService("HttpService"))

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")

-- Cleanup previous instance
if _G._AvatarChangerCleanup then
    pcall(_G._AvatarChangerCleanup)
end

------------------------------------------------------------------------
-- CONFIG PERSISTENCE
------------------------------------------------------------------------
local CONFIG_FILE = "AvatarChanger_Config.json"

local function saveConfig(cfg)
    pcall(function()
        local data = {
            avatar_target = cfg.avatar_target or "",
            avatar_enabled = cfg.avatar_enabled or false,
            headless_enabled = cfg.headless_enabled or false,
            korblox_enabled = cfg.korblox_enabled or false,
            spoofer_enabled = cfg.spoofer_enabled or false,
            spoof_username = cfg.spoof_username or "",
            spoof_displayname = cfg.spoof_displayname or "",
            spoof_avatar_user = cfg.spoof_avatar_user or "",
            unlock_all_enabled = cfg.unlock_all_enabled or false,
            emote_enabled = cfg.emote_enabled or false,
            equipped_sword = cfg.equipped_sword,
            equipped_explosion = cfg.equipped_explosion,
            toggle_key = cfg.toggle_key and cfg.toggle_key.Name or "RightShift",
        }
        writefile(CONFIG_FILE, HttpService:JSONEncode(data))
    end)
end

local function loadConfig()
    local ok, data = pcall(function()
        if not isfile(CONFIG_FILE) then return nil end
        return HttpService:JSONDecode(readfile(CONFIG_FILE))
    end)
    if ok and typeof(data) == "table" then return data end
    return nil
end

------------------------------------------------------------------------
-- CONFIG
------------------------------------------------------------------------
local saved = loadConfig()

local Config = {
    avatar_enabled = saved and saved.avatar_enabled or false,
    avatar_target = saved and saved.avatar_target or "",
    headless_enabled = saved and saved.headless_enabled or false,
    korblox_enabled = saved and saved.korblox_enabled or false,
    spoofer_enabled = saved and saved.spoofer_enabled or false,
    spoof_username = saved and saved.spoof_username or "",
    spoof_displayname = saved and saved.spoof_displayname or "",
    spoof_avatar_user = saved and saved.spoof_avatar_user or "",
    unlock_all_enabled = saved and saved.unlock_all_enabled or false,
    equipped_sword = saved and saved.equipped_sword or nil,
    equipped_explosion = saved and saved.equipped_explosion or nil,
    emote_enabled = saved and saved.emote_enabled or false,
    toggle_key = Enum.KeyCode.RightShift,
}

if saved and saved.toggle_key then
    pcall(function() Config.toggle_key = Enum.KeyCode[saved.toggle_key] end)
end

local function persistConfig()
    task.defer(saveConfig, Config)
end

------------------------------------------------------------------------
-- STATE
------------------------------------------------------------------------
local State = {
    connections = {},
    spoofer_connections = {},

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
    shop_controller = nil,
    shop_spoofed = false,
    refresh_running = false,
    refresh_dirty = false,
    equipped_skins = { Sword = nil, Explosion = nil },
    equip_callbacks = { Sword = {}, Explosion = {} },
    inv_change_callbacks = { Sword = {}, Explosion = {} },
    merged_cache = { Sword = nil, Explosion = nil },
    merged_ref = { Sword = nil, Explosion = nil },
    owned_cache = { Sword = nil, Explosion = nil },
    keys_cache = { Sword = nil, Explosion = nil },
    static_fakes = { Sword = {}, Explosion = {}, _built = {} },
    hidden_items = { Sword = {}, Explosion = {} },
    fake_slots = { Sword = {}, Explosion = {} },
    last_equipped_slot = { Sword = nil, Explosion = nil },
    hooked_buttons = {},
    buy_button_conns = {},
    swords_module = nil,
    swords_controller = nil,
    sword_info_handler = nil,
    replicated_instances = nil,
    sword_char_conns = {},
    sword_attr_conns = {},
    sword_busy = false,
    parry_func = nil,
    parry_orig_conn = nil,
    parry_client_conn = nil,
    parry_our_conn = nil,
    slash_name = "SlashEffect",

    -- Emotes
    emote_enabled = false,
    emote_installed = false,
    emote_storage = {},
    emote_shared_module = nil,
    emote_trove_module = nil,
    emote_trove = nil,
    emote_current = nil,
    emote_raw_get = nil,
    emote_real_owned = nil,
    emote_merged = nil,
    emote_merged_ref = nil,
    emote_static_fakes = nil,
    emote_virtual = {},
    emote_favorites = {},
    emote_wheel_controller = nil,
    emote_controller = nil,
    emote_ec_play = nil,
    emote_connections = {},
    emote_hooked_holders = nil,
    emote_loop = nil,
    emote_move_conn = nil,
    emote_last_play = nil,
    emote_last_play_t = 0,
    emote_boot_id = 0,
    emote_basic = {
        Emote1 = true, Emote2 = true, Emote3 = true, Emote4 = true,
        Emote5 = true, Emote6 = true, Emote7 = true,
    },
    emote_fav_statables = {},
    emote_our_container = nil,
    emote_statable = nil,
    emote_inventory_obj = nil,
    inventory_controller = nil,
    avatar_guard_conn = nil,
}

local function addConn(conn)
    table.insert(State.connections, conn)
end

local function cleanupAll()
    for _, c in ipairs(State.connections) do pcall(function() c:Disconnect() end) end
    State.connections = {}
    for _, c in ipairs(State.spoofer_connections) do pcall(function() c:Disconnect() end) end
    State.spoofer_connections = {}
    if State.inventory_shared and State.original_funcs then
        for k, v in pairs(State.original_funcs) do
            pcall(function() State.inventory_shared[k] = v end)
        end
    end
    -- Re-enable original parry handler
    if State.parry_our_conn then pcall(function() State.parry_our_conn:Disconnect() end); State.parry_our_conn = nil end
    if State.parry_orig_conn then pcall(function() State.parry_orig_conn:Enable() end); State.parry_orig_conn = nil end
    if State.parry_client_conn then pcall(function() State.parry_client_conn:Enable() end); State.parry_client_conn = nil end
    State.parry_func = nil
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
    Config.headless_enabled = on; persistConfig()
    local char = localPlayer.Character
    if on then
        if char then applyHeadless(char) end
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
    Config.korblox_enabled = on; persistConfig()
    local char = localPlayer.Character
    if on then
        if char then applyKorblox(char) end
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

Avatar.stopAccessoryGuard = function()
    if State.avatar_guard_conn then
        pcall(function() State.avatar_guard_conn:Disconnect() end)
        State.avatar_guard_conn = nil
    end
end

Avatar.startAccessoryGuard = function(char, allowedAccessories)
    Avatar.stopAccessoryGuard()
    local allowed = {}
    for _, acc in ipairs(allowedAccessories) do allowed[acc] = true end
    State.avatar_guard_conn = char.ChildAdded:Connect(function(child)
        if not Config.avatar_enabled then return end
        if (child:IsA("Accessory") or child:IsA("Hat")) and not allowed[child] then
            task.defer(function()
                if child.Parent == char and not allowed[child] then
                    child:Destroy()
                end
            end)
        end
    end)
    addConn(State.avatar_guard_conn)
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
            if not isRevert then Avatar.revert(char); Avatar.stopAccessoryGuard() end
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
            -- Guard against game re-adding original accessories
            if not isRevert then
                local applied = {}
                for _, c in ipairs(char:GetChildren()) do
                    if c:IsA("Accessory") or c:IsA("Hat") then applied[c] = true end
                end
                Avatar.startAccessoryGuard(char, applied)
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
    Avatar.stopAccessoryGuard()
    local char = localPlayer.Character
    if char then Avatar.revert(char) end
    Avatar.applyDesc(State.avatar_original_desc, localPlayer.UserId, true)
end

Avatar.reapplyOnSpawn = function(char)
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
        if State.avatar_respawn_token ~= tk then return end
        -- Reapply avatar if enabled
        if Config.avatar_enabled and Config.avatar_target ~= "" then
            State.avatar_applying = false; State.avatar_applied_id = nil
            Avatar.apply(Config.avatar_target)
        end
        -- Reapply headless/korblox
        if Config.headless_enabled then task.delay(0.2, function() if Config.headless_enabled then applyHeadless(char) end end) end
        if Config.korblox_enabled then task.delay(0.2, function() if Config.korblox_enabled then applyKorblox(char) end end) end
    end)
end

------------------------------------------------------------------------
-- NAME SPOOFER (PlayerGui + Workspace + CoreGui)
------------------------------------------------------------------------
local Spoofer = {}
Spoofer._applying = false
Spoofer._tracked = {} -- weak table: label -> { original = string }
setmetatable(Spoofer._tracked, { __mode = "k" })

Spoofer.getAvatarUid = function()
    local n = Config.spoof_avatar_user
    if not n or n == "" then return localPlayer.UserId end
    return resolveUserId(n) or localPlayer.UserId
end

Spoofer.applySpoof = function(text)
    if typeof(text) ~= "string" or text == "" then return text, false end
    local t = text; local changed = false
    if Config.spoof_displayname ~= "" and string.find(t, localPlayer.DisplayName, 1, true) then
        changed = true; t = replaceStr(t, localPlayer.DisplayName, Config.spoof_displayname)
    end
    if Config.spoof_username ~= "" and string.find(t, localPlayer.Name, 1, true) then
        changed = true; t = replaceStr(t, localPlayer.Name, Config.spoof_username)
    end
    return t, changed
end

Spoofer.hookText = function(label)
    if not label:IsA("TextLabel") and not label:IsA("TextButton") then return end
    if Spoofer._tracked[label] then return end
    Spoofer._tracked[label] = { original = label.Text, type = "text" }

    local function upd()
        if Spoofer._applying then return end
        local t = label.Text; if typeof(t) ~= "string" then return end
        -- If the game set new text, update original
        Spoofer._tracked[label].original = t
        if not Config.spoofer_enabled or t == "" then return end
        local spoofed, changed = Spoofer.applySpoof(t)
        if changed then
            Spoofer._applying = true
            label.Text = spoofed
            Spoofer._applying = false
        end
    end
    upd()
    table.insert(State.spoofer_connections, label:GetPropertyChangedSignal("Text"):Connect(upd))
end

Spoofer.hookImage = function(label)
    if not label:IsA("ImageLabel") and not label:IsA("ImageButton") then return end
    if Spoofer._tracked[label] then return end
    Spoofer._tracked[label] = { original = label.Image, type = "image" }

    local function upd()
        if Spoofer._applying then return end
        local img = label.Image; if typeof(img) ~= "string" or img == "" then return end
        Spoofer._tracked[label].original = img
        if not Config.spoofer_enabled then return end
        local myId = tostring(localPlayer.UserId)
        if string.find(img, myId, 1, true) then
            local sid = Spoofer.getAvatarUid()
            if sid ~= localPlayer.UserId then
                Spoofer._applying = true
                label.Image = string.gsub(img, myId, tostring(sid))
                Spoofer._applying = false
            end
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

Spoofer.revertAll = function()
    Spoofer._applying = true
    for label, info in pairs(Spoofer._tracked) do
        pcall(function()
            if info.type == "text" and (label:IsA("TextLabel") or label:IsA("TextButton")) then
                label.Text = info.original
            elseif info.type == "image" and (label:IsA("ImageLabel") or label:IsA("ImageButton")) then
                label.Image = info.original
            end
        end)
    end
    Spoofer._applying = false
end

Spoofer.reapplyAll = function()
    Spoofer._applying = true
    for label, info in pairs(Spoofer._tracked) do
        pcall(function()
            if info.type == "text" and (label:IsA("TextLabel") or label:IsA("TextButton")) then
                local spoofed, changed = Spoofer.applySpoof(info.original)
                label.Text = changed and spoofed or info.original
            elseif info.type == "image" and (label:IsA("ImageLabel") or label:IsA("ImageButton")) then
                local img = info.original
                local myId = tostring(localPlayer.UserId)
                if string.find(img, myId, 1, true) then
                    local sid = Spoofer.getAvatarUid()
                    if sid ~= localPlayer.UserId then
                        label.Image = string.gsub(img, myId, tostring(sid))
                    else
                        label.Image = info.original
                    end
                end
            end
        end)
    end
    Spoofer._applying = false
end

Spoofer.init = function()
    for _, c in ipairs(State.spoofer_connections) do pcall(function() c:Disconnect() end) end
    State.spoofer_connections = {}
    Spoofer._tracked = {}
    setmetatable(Spoofer._tracked, { __mode = "k" })
    Spoofer.hookContainer(playerGui)
    Spoofer.hookContainer(workspace)
    pcall(function() Spoofer.hookContainer(CoreGui) end)
    Spoofer.hookChat()
end

------------------------------------------------------------------------
-- UNLOCK ALL SWORDS + EXPLOSIONS
------------------------------------------------------------------------
local Unlocker = {}

local ITEM_TYPES = { Sword = true, Explosion = true }

Unlocker.fakeItem = function(itemType, name)
    return { Id = name, Name = name }
end

Unlocker.isReallyOwned = function(itemType, name)
    if not name then return false end
    if not State.owned_cache[itemType] then
        State.owned_cache[itemType] = {}
        local orig = State.original_funcs.Get
        if orig then
            local items = orig(State.inventory_shared, nil, itemType)
            if typeof(items) == "table" then
                for _, item in pairs(items) do
                    if typeof(item) == "table" and item.Name then
                        State.owned_cache[itemType][item.Name] = true
                    end
                end
            end
        end
    end
    return State.owned_cache[itemType][name] == true
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

Unlocker.augmentSwordItem = function(itemType, name, item)
    if itemType ~= "Sword" or typeof(item) ~= "table" then return end
    local info = State.item_info.Sword[name]
    if not info then return end
    if info.HasFinisher then item.Finisher = true end
    if info.AccessoryToggleable then item.Accessory = true end
    if item.Kills == nil then item.Kills = 0 end
end

-- Hook observable .Set/.Get on virtual item properties (OwnsItem, ForceHide, Section)
Unlocker.hookVirtualItem = function(vItem, key, itemType)
    if typeof(vItem) ~= "table" then return end
    local name = vItem.Name or key

    -- Hook OwnsItem
    if typeof(vItem.OwnsItem) == "table" and typeof(vItem.OwnsItem.Set) == "function" and not vItem.OwnsItem.__hooked then
        local origSet = vItem.OwnsItem.Set
        vItem.OwnsItem.__hooked = true
        vItem.OwnsItem.Set = function(self, val)
            if State.unlock_active and not State.hidden_items[itemType][name] then
                return origSet(self, true)
            end
            return origSet(self, val)
        end
        if typeof(vItem.OwnsItem.Get) == "function" then
            local origGet = vItem.OwnsItem.Get
            vItem.OwnsItem.Get = function(self, ...)
                if State.unlock_active and not State.hidden_items[itemType][name] then
                    return true
                end
                return origGet(self, ...)
            end
        end
    end

    -- Hook ForceHide
    if typeof(vItem.ForceHide) == "table" and typeof(vItem.ForceHide.Set) == "function" and not vItem.ForceHide.__hooked then
        local origSet = vItem.ForceHide.Set
        vItem.ForceHide.__hooked = true
        local function shouldShow()
            if not State.unlock_active then return false end
            if Unlocker.isReallyOwned(itemType, name) then return false end
            if State.hidden_items[itemType][name] then return false end
            return true
        end
        vItem.ForceHide.Set = function(self, val)
            if shouldShow() then return origSet(self, false) end
            return origSet(self, val)
        end
        if typeof(vItem.ForceHide.Get) == "function" then
            local origGet = vItem.ForceHide.Get
            vItem.ForceHide.Get = function(self, ...)
                if shouldShow() then return false end
                return origGet(self, ...)
            end
        end
    end

    -- Hook Section
    if typeof(vItem.Section) == "table" and typeof(vItem.Section.Set) == "function" and not vItem.Section.__hooked then
        local origSet = vItem.Section.Set
        vItem.Section.__hooked = true
        vItem.Section.Set = function(self, val)
            if State.unlock_active and not Unlocker.isReallyOwned(itemType, name) and not State.hidden_items[itemType][name] then
                return origSet(self, "Owned")
            end
            return origSet(self, val)
        end
    end
end

-- Apply unlock state to a single virtual item
Unlocker.applyUnlockState = function(vItem, key, itemType)
    if typeof(vItem) ~= "table" then return end
    local name = vItem.Name or key
    local isHidden = State.hidden_items[itemType][name]

    if State.unlock_active and not isHidden and not Unlocker.isReallyOwned(itemType, name) then
        vItem.NonPurchaseable = true
        if typeof(vItem.Section) == "string" then vItem.Section = "Owned" end
    end

    if State.unlock_active and vItem.__unlockApplied and not State.refresh_dirty then return end

    -- Set OwnsItem
    if typeof(vItem.OwnsItem) == "table" and typeof(vItem.OwnsItem.Set) == "function" then
        local shouldOwn = not isHidden
        pcall(function()
            if typeof(vItem.OwnsItem.Get) == "function" and vItem.OwnsItem:Get() ~= shouldOwn then
                vItem.OwnsItem:Set(shouldOwn)
            end
        end)
    end

    -- Set ForceHide
    if typeof(vItem.ForceHide) == "table" and typeof(vItem.ForceHide.Set) == "function" then
        local shouldHide = isHidden or Unlocker.isReallyOwned(itemType, name)
        if not shouldHide and not isHidden and vItem.InventoryKey == nil then
            pcall(function()
                if typeof(vItem.ForceHide.Get) == "function" and vItem.ForceHide:Get() ~= false then
                    vItem.ForceHide:Set(false)
                end
            end)
        end
    end

    -- Set Section
    if not isHidden and typeof(vItem.Section) == "table" and typeof(vItem.Section.Set) == "function" then
        local equippedName = State.equipped_skins[itemType]
        local isEquipped = equippedName and (key == equippedName or name == equippedName or vItem.Id == equippedName)
        local section = isEquipped and "Equipped" or "Owned"
        if vItem.__unlockSection ~= section then
            pcall(vItem.Section.Set, vItem.Section, section)
            vItem.__unlockSection = section
        end
    end

    if State.unlock_active and not isHidden then
        vItem.__unlockApplied = true
    end
end

-- Hook __newindex on virtual items table so new items get hooked automatically
Unlocker.hookVirtualItemsTable = function(tbl, itemType)
    local mt = getrawmetatable(tbl) or {}
    pcall(setreadonly, mt, false)
    local oldNewindex = mt.__newindex

    mt.__newindex = newcclosure(function(t, k, v)
        if typeof(v) == "table" then
            pcall(Unlocker.hookVirtualItem, v, k, itemType)
            if State.unlock_active and State.shop_spoofed then
                task.defer(function() pcall(Unlocker.applyUnlockState, v, k, itemType) end)
            end
        end
        if oldNewindex then
            return oldNewindex(t, k, v)
        end
        rawset(t, k, v)
    end)

    pcall(setmetatable, tbl, mt)
end

Unlocker.forceRefreshVirtualItems = function(onlyType)
    if State.refresh_running then return end
    State.refresh_running = true

    pcall(function()
        local shop = State.shop_controller
        if not shop or not shop._virtualItems then return end
        local n = 0
        local t = os.clock()

        for itemType, items in pairs(shop._virtualItems) do
            if ITEM_TYPES[itemType] and (not onlyType or itemType == onlyType) then
                for key, vItem in pairs(items) do
                    if typeof(vItem) == "table" then
                        pcall(Unlocker.hookVirtualItem, vItem, key, itemType)
                        if State.unlock_active then
                            pcall(Unlocker.applyUnlockState, vItem, key, itemType)
                        else
                            vItem.__unlockApplied = nil
                            vItem.__unlockSection = nil
                            pcall(function() shop:_updateItemStatus(itemType, key) end)
                        end
                        n += 1
                        if n % 8 == 0 and os.clock() - t >= 0.0012 then
                            task.wait(); t = os.clock()
                        end
                    end
                end
            end
        end

        if State.unlock_active then
            State.shop_spoofed = true
            State.refresh_dirty = false
        end
    end)

    State.refresh_running = false

    -- Mark inventory pages dirty to force re-render
    pcall(function()
        local shop = State.shop_controller
        if shop and shop._inventoryPages then
            local types = onlyType and {onlyType} or {"Sword", "Explosion"}
            for _, t in ipairs(types) do
                local page = shop._inventoryPages[t]
                if page and typeof(page.MarkDirty) == "function" then
                    page.MarkDirty(nil, true, true)
                end
            end
        end
    end)
end

Unlocker.updateShopUI = function(itemType, equippedName)
    local shop = State.shop_controller
    if not shop or not shop._virtualItems then return end
    local items = shop._virtualItems[itemType]
    if not items then return end

    local lastSlot = State.last_equipped_slot[itemType]
    if lastSlot and lastSlot ~= equippedName then
        local prev = items[lastSlot]
        if typeof(prev) == "table" and typeof(prev.Section) == "table" and typeof(prev.Section.Set) == "function" then
            pcall(prev.Section.Set, prev.Section, "Owned")
            prev.__unlockSection = "Owned"
        end
    end

    if equippedName then
        local cur = items[equippedName]
        if typeof(cur) == "table" and typeof(cur.Section) == "table" and typeof(cur.Section.Set) == "function" then
            pcall(cur.Section.Set, cur.Section, "Equipped")
            cur.__unlockSection = "Equipped"
        end
    end

    State.last_equipped_slot[itemType] = equippedName
end

Unlocker.fireEquipChange = function(itemType)
    local equipped = State.equipped_skins[itemType]
    for _, cb in ipairs(State.equip_callbacks[itemType] or {}) do
        task.spawn(cb, equipped)
    end
    for _, cb in ipairs(State.inv_change_callbacks[itemType] or {}) do
        task.spawn(cb, equipped)
    end
end

Unlocker.getSelectedItem = function()
    local shop = State.shop_controller
    if not shop then return nil, nil end
    local sel = shop._selectedItem
    if typeof(sel) ~= "table" then return nil, nil end
    return sel.name, sel.type
end

Unlocker.resolveItemFromButton = function(btn)
    if not State.item_info then return nil, nil end
    local parent = btn.Parent
    if not parent then return nil, nil end

    local function checkName(n)
        if State.item_info.Sword[n] then return n, "Sword" end
        if State.item_info.Explosion[n] then return n, "Explosion" end
        return nil, nil
    end

    local n, t = checkName(parent.Name)
    if n then return n, t end

    local cur = parent
    for _ = 1, 3 do
        if not cur then break end
        n, t = checkName(cur.Name)
        if n then return n, t end
        cur = cur.Parent
    end

    for _, child in ipairs(parent:GetChildren()) do
        local ok, isText = pcall(function() return child:IsA("TextLabel") or child:IsA("TextButton") end)
        if ok and isText then
            local ok2, text = pcall(function() return child.Text end)
            if ok2 and typeof(text) == "string" then
                n, t = checkName(text)
                if n then return n, t end
            end
        end
    end

    return nil, nil
end

Unlocker.hookBuyButton = function(btn)
    if not (btn:IsA("TextButton") or btn:IsA("ImageButton")) then return end
    if State.hooked_buttons[btn] then return end
    local ok, name = pcall(function() return btn.Name end)
    if not ok then return end
    if name:lower() ~= "buybutton" then return end

    State.hooked_buttons[btn] = true
    local conn = btn.MouseButton1Click:Connect(function()
        if not State.unlock_active then return end

        local itemName, itemType = Unlocker.getSelectedItem()
        if not itemName then
            itemName, itemType = Unlocker.resolveItemFromButton(btn)
        end
        if not itemName or not itemType then return end

        if not Unlocker.isReallyOwned(itemType, itemName) then
            if itemType == "Sword" then
                Unlocker.equipSword(itemName)
            elseif itemType == "Explosion" then
                Unlocker.equipExplosion(itemName)
            end

            pcall(function()
                local textLabel = btn:FindFirstChildWhichIsA("TextLabel", true)
                if textLabel then textLabel.Text = "Equipped" end
            end)
        end
    end)
    table.insert(State.buy_button_conns, conn)
end

Unlocker.hookShopButtons = function()
    local pg = localPlayer:FindFirstChild("PlayerGui")
    if not pg then return end

    task.spawn(function()
        for _, desc in ipairs(pg:GetDescendants()) do
            pcall(Unlocker.hookBuyButton, desc)
        end
    end)

    local conn = pg.DescendantAdded:Connect(function(desc)
        if not State.unlock_active then return end
        pcall(Unlocker.hookBuyButton, desc)
    end)
    table.insert(State.buy_button_conns, conn)
end

Unlocker.findSwordsModule = function()
    if State.swords_module then return State.swords_module end
    local ok, mod = pcall(function()
        return require(ReplicatedStorage:FindFirstChild("Shared"):FindFirstChild("ReplicatedInstances"):FindFirstChild("Swords"))
    end)
    if ok and typeof(mod) == "table" then
        State.swords_module = mod
    end
    return State.swords_module
end

Unlocker.findReplicatedInstances = function()
    if State.replicated_instances then return State.replicated_instances end
    local ok, mod = pcall(function()
        return require(ReplicatedStorage:FindFirstChild("Shared"):FindFirstChild("ReplicatedInstances"))
    end)
    if ok and typeof(mod) == "table" then
        State.replicated_instances = mod
    end
    return State.replicated_instances
end

Unlocker.fetchSwordModel = function(swordName)
    local ri = Unlocker.findReplicatedInstances()
    if not ri then return nil end
    local model
    pcall(function()
        if ri.Collections and ri.Collections.Swords and ri.Collections.Swords.Instances then
            local inst = ri.Collections.Swords.Instances[swordName]
            if inst then model = inst:Clone() end
        end
    end)
    if model then return model end
    pcall(function()
        if typeof(ri.GetInstance) == "function" then
            model = ri:GetInstance("Swords", swordName)
        end
    end)
    return model
end

Unlocker.findSwordsController = function()
    if State.swords_controller then return State.swords_controller end
    if not getconnections or not getupvalues then
        warn("[Swords] getconnections or getupvalues not available")
        return nil
    end
    local ok, remote = pcall(function()
        return ReplicatedStorage:WaitForChild("Remotes", 5) and ReplicatedStorage.Remotes:FindFirstChild("FireSwordInfo")
    end)
    if not ok or not remote then
        warn("[Swords] FireSwordInfo remote not found")
        return nil
    end
    local ok2, conns = pcall(getconnections, remote.OnClientEvent)
    if not ok2 or typeof(conns) ~= "table" then
        warn("[Swords] Failed to get connections")
        return nil
    end
    for _, conn in ipairs(conns) do
        local fn = conn.Function or conn["function"]
        if fn then
            local isLua = true
            if islclosure then
                local ok4, result = pcall(islclosure, fn)
                isLua = ok4 and result
            end
            if isLua then
                local ok3, upvals = pcall(getupvalues, fn)
                if ok3 and typeof(upvals) == "table" and #upvals == 1 and typeof(upvals[1]) == "table" then
                    State.swords_controller = upvals[1]
                    State.sword_info_handler = fn
                    warn("[Swords] Found swords_controller")
                    return upvals[1]
                end
            end
        end
    end
    warn("[Swords] Controller not found in " .. tostring(#conns) .. " connections")
    return nil
end

Unlocker.getSlashName = function(swordName)
    if not swordName or swordName == "" then return "SlashEffect" end
    local swordsMod = Unlocker.findSwordsModule()
    if swordsMod and typeof(swordsMod.GetSword) == "function" then
        local ok, info = pcall(function() return swordsMod:GetSword(swordName) end)
        if ok and info and info.SlashName then return info.SlashName end
    end
    return "SlashEffect"
end

Unlocker.setupParryIntercept = function()
    if State.parry_our_conn then return end
    if not getconnections then
        warn("[Swords] getconnections not available, can't intercept parry VFX")
        return
    end

    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    if not remotes then return end
    local parryRemote = remotes:FindFirstChild("ParrySuccessAll")
    if not parryRemote then return end

    local parryFunc = nil
    local origConn = nil

    local ok, conns = pcall(getconnections, parryRemote.OnClientEvent)
    if not ok or typeof(conns) ~= "table" then return end

    for _, conn in ipairs(conns) do
        local fn = conn.Function or conn["function"]
        if fn then
            local nameMatch = false
            if getinfo then
                local ok2, info = pcall(getinfo, fn)
                if ok2 and typeof(info) == "table" and info.name == "parrySuccessAll" then
                    nameMatch = true
                end
            else
                local isLua = true
                if islclosure then
                    local ok3, r = pcall(islclosure, fn)
                    isLua = ok3 and r
                end
                nameMatch = isLua
            end
            if nameMatch then
                parryFunc = fn
                origConn = conn
                break
            end
        end
    end

    if not parryFunc or not origConn then
        warn("[Swords] Could not find parrySuccessAll handler")
        return
    end

    pcall(function() origConn:Disable() end)
    State.parry_func = parryFunc
    State.parry_orig_conn = origConn

    local clientRemote = remotes:FindFirstChild("ParrySuccessClient")
    if clientRemote then
        local ok2, cConns = pcall(getconnections, clientRemote.Event)
        if ok2 and typeof(cConns) == "table" then
            for _, conn in ipairs(cConns) do
                local fn = conn.Function or conn["function"]
                if fn then
                    local nameMatch = false
                    if getinfo then
                        local ok3, info = pcall(getinfo, fn)
                        nameMatch = ok3 and typeof(info) == "table" and info.name == "parrySuccessAll"
                    end
                    if nameMatch then
                        pcall(function() conn:Disable() end)
                        State.parry_client_conn = conn
                        break
                    end
                end
            end
        end
    end

    State.parry_our_conn = parryRemote.OnClientEvent:Connect(function(...)
        if not State.parry_func then return end

        if not State.unlock_active or not State.equipped_skins.Sword or State.equipped_skins.Sword == "" then
            local savedId = getthreadidentity and getthreadidentity() or nil
            if setthreadidentity then pcall(setthreadidentity, 2) end
            local ret = {pcall(State.parry_func, ...)}
            if savedId and setthreadidentity then pcall(setthreadidentity, savedId) end
            if ret[1] then return unpack(ret, 2) end
            return
        end

        local args = {...}
        local argCount = select("#", ...)

        local swordName = State.equipped_skins.Sword
        local isUs = false

        if argCount >= 4 and typeof(args[4]) == "Instance" and args[4]:IsA("Player") then
            isUs = args[4] == localPlayer
        else
            local char = localPlayer.Character
            if char and typeof(args[2]) == "Instance" then
                isUs = args[2] == char or args[2].Parent == char
            end
        end

        if isUs then
            args[1] = State.slash_name
            args[3] = swordName
        end

        local savedId = getthreadidentity and getthreadidentity() or nil
        if setthreadidentity then pcall(setthreadidentity, 2) end
        local ret = {pcall(State.parry_func, unpack(args, 1, argCount))}
        if savedId and setthreadidentity then pcall(setthreadidentity, savedId) end
        if ret[1] then return unpack(ret, 2) end
    end)

    warn("[Swords] Parry VFX intercept active — slash: " .. State.slash_name)
end

Unlocker.cleanupParryIntercept = function()
    if State.parry_our_conn then
        pcall(function() State.parry_our_conn:Disconnect() end)
        State.parry_our_conn = nil
    end
    if State.parry_orig_conn then
        pcall(function() State.parry_orig_conn:Enable() end)
        State.parry_orig_conn = nil
    end
    if State.parry_client_conn then
        pcall(function() State.parry_client_conn:Enable() end)
        State.parry_client_conn = nil
    end
    State.parry_func = nil
end

-- Patch EquipSwordTo ownership check (Flyte method)
Unlocker._swordsPatched = false
Unlocker._swordState = nil

Unlocker.patchSwords = function()
    if Unlocker._swordsPatched then return end
    local sm = Unlocker.findSwordsModule()
    if not sm or not getupvalues or not setupvalue then return end
    local equipFn = rawget(sm, "EquipSwordTo")
    if not equipFn then return end
    local ups = getupvalues(equipFn)
    if not ups then return end
    local playersIdx = nil
    for idx, val in ups do
        if typeof(val) == "Instance" and val.ClassName == "Players" then
            playersIdx = idx
        elseif type(val) == "table" and type(rawget(val, "cancel")) == "function" and type(rawget(val, "begin")) == "function" then
            Unlocker._swordState = val
        end
    end
    if not playersIdx and ups[3] == false and ups[4] == true then
        setupvalue(equipFn, 3, Players)
        playersIdx = 3
    end
    if playersIdx and type(ups[playersIdx + 1]) == "boolean" then
        setupvalue(equipFn, playersIdx + 1, false)
    end
    Unlocker._swordsPatched = playersIdx ~= nil
end

Unlocker.removeSwordModels = function(char, keepName)
    if not char then return end
    for _, child in char:GetChildren() do
        if child:IsA("Model") and child.Name ~= keepName then
            local isSword = false
            pcall(function()
                isSword = ReplicatedStorage.Shared.ReplicatedInstances.Swords.GetSword:Invoke(child.Name) ~= nil
            end)
            if isSword then child:Destroy() end
        end
    end
end

-- GetBlade: find the SwordsController (blade controller) via FireSwordInfo connections (Flyte method)
Unlocker._bladeController = nil
Unlocker.getBlade = function()
    if Unlocker._bladeController then return Unlocker._bladeController end
    if not getconnections or not getupvalues then return nil end
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    local event = remotes and remotes:FindFirstChild("FireSwordInfo")
    if not event then return nil end
    for _, conn in getconnections(event.OnClientEvent) do
        local ups = conn.Function and getupvalues(conn.Function)
        if type(ups) == "table" then
            for _, v in ups do
                if type(v) == "table" and type(rawget(v, "SetSword")) == "function" then
                    Unlocker._bladeController = v
                    return v
                end
            end
        end
    end
    return nil
end

-- PatchBlade: hook SetSword so the game can't reset our sword back (Flyte method)
Unlocker._origSetSword = nil
Unlocker.patchBlade = function(blade)
    if not blade or Unlocker._origSetSword then return end
    Unlocker._origSetSword = blade.SetSword
    blade.SetSword = function(self, swordName)
        -- if unlock all is active and we have a sword selected, force our sword
        if State.unlock_active and State.equipped_skins and State.equipped_skins.Sword and State.equipped_skins.Sword ~= "" then
            swordName = State.equipped_skins.Sword
        end
        return Unlocker._origSetSword(self, swordName)
    end
end

Unlocker.unpatchBlade = function()
    if Unlocker._origSetSword and Unlocker._bladeController then
        Unlocker._bladeController.SetSword = Unlocker._origSetSword
        Unlocker._origSetSword = nil
    end
end

Unlocker.applySwordModel = function(char, swordName, forceModel)
    if not char then return false end
    State.sword_busy = true
    local ok = pcall(function()
        -- 1. Patch ownership check
        Unlocker.patchSwords()

        -- 2. Cancel current sword state machine
        if Unlocker._swordState then
            pcall(function() Unlocker._swordState.cancel(char) end)
        end

        -- 3. Equip via EquipSwordTo (now ownership-patched)
        local sm = Unlocker.findSwordsModule()
        if sm and typeof(sm.EquipSwordTo) == "function" then
            if sm:EquipSwordTo(char, swordName) == false then
                State.sword_busy = false
                return
            end
        end

        -- 4. Update slash name
        State.slash_name = Unlocker.getSlashName(swordName)

        -- 5. Remove sword accessories
        local swordAcc = char:FindFirstChild("SwordAccessories")
        if swordAcc then swordAcc:Destroy() end

        -- 6. Get blade controller, patch it, and set sword (Flyte method)
        local blade = Unlocker.getBlade()
        if blade then
            Unlocker.patchBlade(blade)
            blade:SetSword(swordName)
        end

        -- 7. Remove sword accessories again deferred (some respawn)
        task.defer(function()
            local acc = char:FindFirstChild("SwordAccessories")
            if acc then acc:Destroy() end
        end)

        -- 8. Remove old sword models deferred
        task.defer(Unlocker.removeSwordModels, char, swordName)
    end)
    State.sword_busy = false
    return ok
end

Unlocker.cleanupSwordCharConns = function()
    for _, c in ipairs(State.sword_char_conns) do
        pcall(function() c:Disconnect() end)
    end
    State.sword_char_conns = {}
    for _, c in ipairs(State.sword_attr_conns) do
        pcall(function() c:Disconnect() end)
    end
    State.sword_attr_conns = {}
end

-- Called when the game changes CurrentlyEquippedSword (e.g. FireSwordInfo fires)
Unlocker.onSwordAttributeChanged = function()
    if not State.unlock_active then return end
    if State.sword_busy then return end
    local name = State.equipped_skins.Sword
    if not name or name == "" then return end
    local char = localPlayer.Character
    if not char then return end

    -- Check if attribute already matches our sword (we set it ourselves)
    local currentAttr = localPlayer:GetAttribute("CurrentlyEquippedSword")
    if currentAttr == name then return end

    -- Game changed the attribute to something else — re-apply
    State.sword_busy = true
    pcall(function() char:SetAttribute("CurrentlyEquippedSword", name) end)
    pcall(function() localPlayer:SetAttribute("CurrentlyEquippedSword", name) end)
    local sc = State.swords_controller
    if sc then pcall(function() sc:SetSword(name) end) end

    if not char:FindFirstChild(name) then
        task.delay(0.06, function()
            if localPlayer.Character ~= char then return end
            if not State.unlock_active then return end
            State.sword_busy = false
            Unlocker.applySwordModel(char, name, true)
        end)
    else
        State.sword_busy = false
    end
end

Unlocker.monitorCharacter = function(char)
    if not char then return end
    -- Clean up old char connections but keep attr connections
    for _, c in ipairs(State.sword_char_conns) do
        pcall(function() c:Disconnect() end)
    end
    State.sword_char_conns = {}

    -- When the game removes our custom sword model, re-apply it
    table.insert(State.sword_char_conns, char.ChildRemoved:Connect(function(child)
        if State.sword_busy then return end
        if not State.unlock_active then return end
        local name = State.equipped_skins.Sword
        if not name or name == "" then return end
        if child:IsA("Model") and child.Name == name then
            if not char:FindFirstChild(name) then
                task.delay(0.06, function()
                    if localPlayer.Character ~= char then return end
                    if not State.unlock_active then return end
                    State.sword_busy = false
                    Unlocker.applySwordModel(char, name, true)
                end)
            end
        end
    end))

    -- When the game adds a different sword model, replace with ours
    table.insert(State.sword_char_conns, char.ChildAdded:Connect(function(child)
        if State.sword_busy then return end
        if not State.unlock_active then return end
        local name = State.equipped_skins.Sword
        if not name or name == "" then return end
        if child:IsA("Model") and State.item_info and State.item_info.Sword[child.Name] and child.Name ~= name then
            task.delay(0.06, function()
                if localPlayer.Character ~= char then return end
                if not State.unlock_active then return end
                State.sword_busy = false
                Unlocker.applySwordModel(char, name, true)
            end)
        end
    end))

    -- Monitor CurrentlyEquippedSword attribute on this character
    table.insert(State.sword_char_conns, char:GetAttributeChangedSignal("CurrentlyEquippedSword"):Connect(Unlocker.onSwordAttributeChanged))
end

Unlocker.setupRespawn = function()
    if State.sword_respawn_conn then
        pcall(function() State.sword_respawn_conn:Disconnect() end)
    end

    -- Monitor attribute on player (persists across respawns)
    table.insert(State.sword_attr_conns, localPlayer:GetAttributeChangedSignal("CurrentlyEquippedSword"):Connect(Unlocker.onSwordAttributeChanged))

    State.sword_respawn_conn = localPlayer.CharacterAdded:Connect(function(char)
        task.defer(function()
            if not State.unlock_active then return end
            local name = State.equipped_skins.Sword
            if not name or name == "" then return end
            Unlocker.monitorCharacter(char)
            -- Wait for character to be alive and have a sword
            local deadline = os.clock() + 8
            while os.clock() < deadline do
                if localPlayer.Character ~= char then return end
                local hum = char:FindFirstChildOfClass("Humanoid")
                local hrp = char:FindFirstChild("HumanoidRootPart")
                if hum and hum.Health > 0 and hrp then
                    local hasSword = false
                    for _, child in ipairs(char:GetChildren()) do
                        if child:IsA("Model") and State.item_info and State.item_info.Sword[child.Name] then
                            hasSword = true; break
                        end
                    end
                    local attr = char:GetAttribute("CurrentlyEquippedSword") or localPlayer:GetAttribute("CurrentlyEquippedSword")
                    if hasSword or (typeof(attr) == "string" and attr ~= "") then break end
                end
                task.wait(0.1)
            end
            if localPlayer.Character ~= char then return end
            if not State.unlock_active or State.equipped_skins.Sword ~= name then return end
            -- Apply with retries
            for i = 1, 4 do
                if localPlayer.Character ~= char then return end
                if char:FindFirstChild(name) then
                    -- Model there but VFX might not be set, force it
                    local sc = State.swords_controller
                    if sc then pcall(function() sc:SetSword(name) end) end
                    return
                end
                State.sword_busy = false
                Unlocker.applySwordModel(char, name, true)
                task.wait(0.25)
            end
        end)
    end)
    addConn(State.sword_respawn_conn)

    -- Set up monitoring on current character immediately
    if localPlayer.Character then
        task.defer(function()
            Unlocker.monitorCharacter(localPlayer.Character)
        end)
    end
end

Unlocker.equipSword = function(name)
    if not State.item_info or not State.item_info.Sword[name] then return end
    local oldName = State.equipped_skins.Sword
    env.equipped_sword = name
    env.sword_name = name
    State.equipped_skins.Sword = name
    Config.equipped_sword = name; persistConfig()

    local char = localPlayer.Character
    if char then
        State.sword_busy = true
        for _, child in ipairs(char:GetChildren()) do
            if child:IsA("Model") and (State.item_info.Sword[child.Name] or child.Name == oldName) then
                child:Destroy()
            end
        end
        State.sword_busy = false
        Unlocker.applySwordModel(char, name, true)
        Unlocker.monitorCharacter(char)
        -- Retry with increasing delays until model appears
        task.spawn(function()
            for _, delay in ipairs({0.15, 0.3, 0.5, 1.0}) do
                task.wait(delay)
                local c = localPlayer.Character
                if not c or State.equipped_skins.Sword ~= name then return end
                if c:FindFirstChild(name) then return end
                State.sword_busy = false
                Unlocker.applySwordModel(c, name, true)
            end
        end)
    end

    Unlocker.fireEquipChange("Sword")
    Unlocker.updateShopUI("Sword", name)
end

Unlocker.equipExplosion = function(name)
    if not State.item_info or not State.item_info.Explosion[name] then return end
    env.explosion_name = name
    env.equipped_explosion = name
    State.equipped_skins.Explosion = name
    Config.equipped_explosion = name; persistConfig()
    Unlocker.fireEquipChange("Explosion")
    Unlocker.updateShopUI("Explosion", name)
end

Unlocker.interceptEquip = function(...)
    if not State.unlock_active then return false end
    local args = table.pack(...)

    local function extractInfo(arg)
        if typeof(arg) == "string" then return nil, arg end
        if typeof(arg) == "table" then
            local itemType = arg.ItemType or arg.Type or arg.itemType
            local name = arg.Id or arg.Name or arg.ItemId or arg.ItemKey or arg.Key or arg.key
            return itemType, name
        end
        return nil, nil
    end

    for i = 1, args.n do
        local itemType, name = extractInfo(args[i])
        if typeof(name) ~= "string" then continue end

        if itemType then
            if itemType == "Sword" and State.item_info.Sword[name] and not Unlocker.isReallyOwned("Sword", name) then
                Unlocker.equipSword(name); return true
            end
            if itemType == "Explosion" and State.item_info.Explosion[name] and not Unlocker.isReallyOwned("Explosion", name) then
                Unlocker.equipExplosion(name); return true
            end
        end

        if State.item_info.Sword[name] and not Unlocker.isReallyOwned("Sword", name) then
            Unlocker.equipSword(name); return true
        end
        if State.item_info.Explosion[name] and not Unlocker.isReallyOwned("Explosion", name) then
            Unlocker.equipExplosion(name); return true
        end
    end
    return false
end

Unlocker.isShopVisible = function()
    local pg = localPlayer:FindFirstChild("PlayerGui")
    if not pg then return false end
    local shop = pg:FindFirstChild("Shop") or pg:FindFirstChild("ShopGui") or pg:FindFirstChild("ShopFrame")
    if not shop then
        for _, d in ipairs(pg:GetDescendants()) do
            if (d:IsA("GuiObject") or d:IsA("ScreenGui")) and d.Name:lower():match("shop") then
                shop = d; break
            end
        end
    end
    if not shop then return false end
    if shop:IsA("ScreenGui") then return shop.Enabled end
    if shop:IsA("GuiObject") then return shop.Visible end
    return false
end

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
    if ok4 and typeof(client) == "table" then
        State.inventory_client = client
    else
        local ok5, clientMod = pcall(function() return require(ReplicatedStorage.Shared.Inventory.Client) end)
        if ok5 and typeof(clientMod) == "table" then
            State.inventory_client = clientMod
        end
    end

    return true
end

Unlocker.findShopController = function()
    if State.shop_controller then return true end

    for _, desc in ipairs(ReplicatedStorage:GetDescendants()) do
        if desc:IsA("ModuleScript") and desc.Name:lower():match("shop") then
            local ok, mod = pcall(require, desc)
            if ok and typeof(mod) == "table" and mod._virtualItems then
                State.shop_controller = mod
                return true
            end
        end
    end
    return false
end

Unlocker.hookInventory = function()
    local shared = State.inventory_shared
    local client = State.inventory_client
    local itemInfo = State.item_info
    if not shared or not itemInfo then return false end

    State.original_funcs = {
        Get = shared.Get,
        GetItem = shared.GetItem,
        GetEquipped = shared.GetEquipped,
        OnEquip = shared.OnEquip,
        OnInventoryChange = shared.OnInventoryChange,
        FindItemsWithKey = shared.FindItemsWithKey,
    }
    local orig = State.original_funcs

    -- Unlock module tables for writing (may be frozen by game)
    pcall(function()
        local mt = getrawmetatable(shared)
        if mt then setreadonly(mt, false) end
    end)
    if client then
        pcall(function()
            local mt = getrawmetatable(client)
            if mt then setreadonly(mt, false) end
        end)
    end

    -- Hook shared.Get — merge all catalog items into owned items
    shared.Get = function(self, player, itemType)
        local result = orig.Get(self, player, itemType)
        if not State.unlock_active or player ~= nil or not ITEM_TYPES[itemType] then
            return result
        end
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
            if not existing[fakeItem.Name] and not State.hidden_items[itemType][fakeItem.Name] then
                merged[key] = fakeItem
            end
        end
        State.merged_cache[itemType] = merged
        State.merged_ref[itemType] = result
        return merged
    end

    -- Hook shared.GetItem — return fake for anything in catalog
    shared.GetItem = function(self, player, itemType, itemName)
        local result = orig.GetItem(self, player, itemType, itemName)
        if result or not State.unlock_active or player ~= nil or not ITEM_TYPES[itemType] then
            return result
        end
        local catalog = itemInfo[itemType]
        if not catalog then return result end
        if catalog[itemName] then
            if State.hidden_items[itemType][itemName] then return result end
            local fake = Unlocker.fakeItem(itemType, itemName)
            Unlocker.augmentSwordItem(itemType, itemName, fake)
            return fake
        end
        local ok, conv = pcall(function() return shared:StringToItem(itemType, itemName) end)
        if ok and typeof(conv) == "table" and conv.Name and catalog[conv.Name] then
            if State.hidden_items[itemType][conv.Name] then return result end
            if conv.Id == nil then conv.Id = conv.Name end
            Unlocker.augmentSwordItem(itemType, conv.Name, conv)
            return conv
        end
        return result
    end

    -- Hook shared.GetEquipped — return spoofed equipped skin
    shared.GetEquipped = function(self, player, itemType)
        if State.unlock_active and player == nil and ITEM_TYPES[itemType] then
            local equipped = State.equipped_skins[itemType]
            if equipped then return equipped end
        end
        return orig.GetEquipped(self, player, itemType)
    end

    -- Hook shared.OnEquip — track callbacks
    shared.OnEquip = function(self, player, itemType, callback)
        if player == nil and ITEM_TYPES[itemType] then
            table.insert(State.equip_callbacks[itemType], callback)
        end
        return orig.OnEquip(self, player, itemType, callback)
    end

    -- Hook shared.OnInventoryChange — track callbacks + bust cache
    shared.OnInventoryChange = function(self, player, itemType, callback)
        if player == nil and ITEM_TYPES[itemType] then
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
            if not State.unlock_active or player ~= nil or not ITEM_TYPES[itemType] then
                return result
            end
            if typeof(result) == "table" and #result > 0 then return result end
            local itemName = key
            if not (itemInfo[itemType] and itemInfo[itemType][key]) then
                if client and typeof(client.KeyToItem) == "function" then
                    local ok, conv = pcall(function() return client:KeyToItem(key) end)
                    if ok and typeof(conv) == "table" and conv.Name then itemName = conv.Name end
                end
            end
            if itemName and itemInfo[itemType] and itemInfo[itemType][itemName] and not Unlocker.isReallyOwned(itemType, itemName) and not State.hidden_items[itemType][itemName] then
                return { itemName }
            end
            return result
        end
    end

    -- Hook client.Equip / Unequip
    if client then
        local origEquip = client.Equip
        local origUnequip = client.Unequip

        if origEquip then
            client.Equip = function(self, itemId, ...)
                if Unlocker.interceptEquip(itemId) then return true end
                return origEquip(self, itemId, ...)
            end
        end

        if origUnequip then
            client.Unequip = function(self, itemType, ...)
                if State.unlock_active and (itemType == "Sword" or itemType == "Explosion") then
                    State.equipped_skins[itemType] = nil
                    Config["equipped_" .. itemType:lower()] = nil; persistConfig()
                    Unlocker.fireEquipChange(itemType)
                    Unlocker.updateShopUI(itemType, nil)
                    return true
                end
                return origUnequip(self, itemType, ...)
            end
        end
    end

    return true
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
    State.merged_cache = { Sword = nil, Explosion = nil }
    State.merged_ref = { Sword = nil, Explosion = nil }
    State.owned_cache = { Sword = nil, Explosion = nil }
    State.shop_spoofed = false
    State.refresh_dirty = true
    env.unlock_all_skins = true

    -- Don't auto-equip last sword on fresh load — let user pick fresh
    -- Sword will be applied when user selects one from the shop
    if Config.equipped_explosion and State.item_info and State.item_info.Explosion[Config.equipped_explosion] then
        State.equipped_skins.Explosion = Config.equipped_explosion
        env.equipped_explosion = Config.equipped_explosion
        env.explosion_name = Config.equipped_explosion
    end

    -- Set up equip functions on getgenv for the game to call
    env.equip_sword_skin = Unlocker.equipSword
    env.equip_explosion_skin = Unlocker.equipExplosion

    -- Find and hook shop controller
    task.spawn(function()
        for i = 1, 30 do
            if Unlocker.findShopController() then
                local shop = State.shop_controller
                -- Hook all existing virtual items
                for itemType, items in pairs(shop._virtualItems) do
                    if ITEM_TYPES[itemType] then
                        for key, vItem in pairs(items) do
                            pcall(Unlocker.hookVirtualItem, vItem, key, itemType)
                        end
                        Unlocker.hookVirtualItemsTable(items, itemType)
                    end
                end
                -- Hook _canDelete
                pcall(function()
                    if typeof(shop._canDelete) == "function" and not shop.__canDeleteHooked then
                        shop.__canDeleteHooked = true
                        local origCanDelete = shop._canDelete
                        shop._canDelete = function(self, itemType, key, ...)
                            if State.unlock_active and ITEM_TYPES[itemType] and State.inventory_client then
                                local ok2, conv = pcall(function() return State.inventory_client:KeyToItem(key) end)
                                local name = ok2 and typeof(conv) == "table" and conv.Name
                                if name and not Unlocker.isReallyOwned(itemType, name) and not State.hidden_items[itemType][name] then
                                    return true
                                end
                            end
                            return origCanDelete(self, itemType, key, ...)
                        end
                    end
                end)
                -- Force refresh
                Unlocker.forceRefreshVirtualItems()
                break
            end
            task.wait(0.5)
        end

        -- Hook shop buy buttons for equip
        Unlocker.hookShopButtons()
    end)

    -- Background: find swords_controller via getconnections for VFX/SFX
    task.spawn(function()
        for i = 1, 20 do
            if Unlocker.findSwordsController() then break end
            task.wait(0.5)
        end
        -- Once swords_controller is found, set up parry VFX interception
        if State.swords_controller then
            -- Update slash_name if a sword is already equipped
            local name = State.equipped_skins.Sword
            if name and name ~= "" then
                State.slash_name = Unlocker.getSlashName(name)
            end
            Unlocker.setupParryIntercept()
        end
    end)

    -- Periodic attribute guard (only re-applies when game overrides our attribute)
    task.spawn(function()
        while State.unlock_active do
            task.wait(1)
            if not State.unlock_active then break end
            if State.sword_busy then continue end
            local name = State.equipped_skins.Sword
            if name and name ~= "" then
                local char = localPlayer.Character
                if char then
                    local currentAttr = localPlayer:GetAttribute("CurrentlyEquippedSword")
                    if currentAttr ~= name then
                        pcall(function() char:SetAttribute("CurrentlyEquippedSword", name) end)
                        pcall(function() localPlayer:SetAttribute("CurrentlyEquippedSword", name) end)
                        local sc = State.swords_controller
                        if sc then pcall(function() sc:SetSword(name) end) end
                    end
                end
            end
        end
    end)

    -- Set up respawn monitoring for sword persistence
    Unlocker.setupRespawn()

    persistConfig()
    return true
end

Unlocker.disable = function()
    State.unlock_active = false
    Config.unlock_all_enabled = false
    env.unlock_all_skins = false
    State.merged_cache = { Sword = nil, Explosion = nil }
    State.merged_ref = { Sword = nil, Explosion = nil }
    State.shop_spoofed = false
    Unlocker.cleanupParryIntercept()
    Unlocker.cleanupSwordCharConns()
    if State.sword_respawn_conn then
        pcall(function() State.sword_respawn_conn:Disconnect() end)
        State.sword_respawn_conn = nil
    end
    for _, conn in ipairs(State.buy_button_conns) do
        pcall(function() conn:Disconnect() end)
    end
    State.buy_button_conns = {}
    State.hooked_buttons = {}
    if State.shop_controller then
        Unlocker.forceRefreshVirtualItems()
    end
    persistConfig()
end

------------------------------------------------------------------------
-- EMOTE UNLOCK
------------------------------------------------------------------------
local Emotes = {}

Emotes.loadAnimations = function()
    local misc = ReplicatedStorage:FindFirstChild("Misc")
    if not misc then return end
    local folder = misc:FindFirstChild("Emotes")
    if not folder then return end
    for _, child in ipairs(folder:GetChildren()) do
        if child:IsA("Animation") and child:GetAttribute("EmoteName") then
            State.emote_storage[child:GetAttribute("EmoteName")] = child
        end
    end
end

Emotes.getSharedModule = function()
    if State.emote_shared_module ~= nil then
        return State.emote_shared_module or nil
    end
    local shared = ReplicatedStorage:FindFirstChild("Shared")
    local mod = shared and shared:FindFirstChild("EmotesShared")
    if not mod then State.emote_shared_module = false; return nil end
    local ok, result = pcall(require, mod)
    if ok and typeof(result) == "table" and typeof(result.Play) == "function" then
        State.emote_shared_module = result
    else
        State.emote_shared_module = false
    end
    return State.emote_shared_module or nil
end

Emotes.getTroveModule = function()
    if State.emote_trove_module ~= nil then
        return State.emote_trove_module or nil
    end
    local packages = ReplicatedStorage:FindFirstChild("Packages")
    local mod = packages and packages:FindFirstChild("Trove")
    if not mod then State.emote_trove_module = false; return nil end
    local ok, result = pcall(require, mod)
    if ok and typeof(result) == "table" and typeof(result.new) == "function" then
        State.emote_trove_module = result
    else
        State.emote_trove_module = false
    end
    return State.emote_trove_module or nil
end

Emotes.stopTrack = function()
    if State.emote_trove then
        pcall(function() State.emote_trove:Destroy() end)
        State.emote_trove = nil
    end
end

Emotes.playInternal = function(emoteName)
    if typeof(emoteName) ~= "string" or emoteName == "" then return false end
    local char = localPlayer.Character
    if not char or not char.PrimaryPart then return false end
    if not char:FindFirstChildWhichIsA("Humanoid") then return false end
    local emotesShared = Emotes.getSharedModule()
    local troveModule = Emotes.getTroveModule()
    if not emotesShared or not troveModule then return false end
    Emotes.stopTrack()
    State.emote_trove = troveModule.new()
    State.emote_current = emoteName
    local ok = pcall(function()
        emotesShared:Play(char, State.emote_trove, emoteName, true, workspace:GetServerTimeNow(), nil)
    end)
    if not ok then Emotes.stopTrack(); return false end
    return true
end

Emotes.stopEmote = function()
    Emotes.stopTrack()
    State.emote_current = nil
end

Emotes.stopLocal = function()
    if State.emote_move_conn then
        pcall(function() State.emote_move_conn:Disconnect() end)
        State.emote_move_conn = nil
    end
    State.emote_last_play = nil
    Emotes.stopEmote()
    pcall(function()
        local char = localPlayer.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        local animator = hum and hum:FindFirstChildOfClass("Animator")
        if not animator then return end
        for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
            local anim = track.Animation
            if anim then
                local attr = anim:GetAttribute("EmoteName")
                if attr or State.emote_storage[anim.Name] or State.emote_storage[attr] then
                    pcall(function() track:Stop(0) end)
                end
            end
        end
    end)
end

Emotes.playLocal = function(emoteName)
    local now = os.clock()
    if emoteName == State.emote_last_play and now - State.emote_last_play_t < 0.25 then
        return
    end
    State.emote_last_play = emoteName
    State.emote_last_play_t = now
    Emotes.stopLocal()
    if not Emotes.playInternal(emoteName) then return end
    local char = localPlayer.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if hum then
        State.emote_move_conn = hum:GetPropertyChangedSignal("MoveDirection"):Connect(function()
            if hum.MoveDirection.Magnitude > 0 then
                Emotes.stopLocal()
            end
        end)
    end
end

Emotes.reallyOwned = function(name)
    if not State.emote_real_owned then
        Emotes.refreshOwned()
    end
    return State.emote_real_owned and State.emote_real_owned[name] == true
end

Emotes.refreshOwned = function()
    local owned = {}
    if State.emote_raw_get and State.inventory_shared then
        local ok, items = pcall(State.emote_raw_get, State.inventory_shared, nil, "Emote")
        if ok and typeof(items) == "table" then
            for _, item in pairs(items) do
                if typeof(item) == "table" and item.Name then
                    owned[item.Name] = true
                end
            end
        end
    end
    State.emote_real_owned = owned
end

Emotes.getStaticFakes = function()
    if State.emote_static_fakes then return State.emote_static_fakes end
    local fakes = {}
    local shared = State.inventory_shared
    local catalog = State.item_info and State.item_info.Emote
    if shared and typeof(catalog) == "table" then
        for k in pairs(catalog) do
            local ok, key = pcall(function()
                return shared:ItemToKey("Emote", { Id = k, Name = k }, {"Id"})
            end)
            if ok and key then fakes[key] = { Id = k, Name = k } end
        end
    end
    State.emote_static_fakes = fakes
    return fakes
end

Emotes.getMerged = function()
    local rawItems = State.emote_raw_get and State.emote_raw_get(State.inventory_shared, nil, "Emote") or nil
    if State.emote_merged and State.emote_merged_ref == rawItems then
        return State.emote_merged
    end
    local real = typeof(rawItems) == "table" and rawItems or {}
    local deleted = {}
    local realOwned = {}
    for _, item in pairs(real) do
        if typeof(item) == "table" and item.Name then
            realOwned[item.Name] = true
        end
    end
    State.emote_real_owned = realOwned
    local merged = {}
    local seenNames = {}
    for k, v in pairs(real) do
        if not (typeof(v) == "table" and v.Name and deleted[v.Name]) then
            merged[k] = v
            if typeof(v) == "table" and v.Name then seenNames[v.Name] = true end
        end
    end
    for k, fake in pairs(Emotes.getStaticFakes()) do
        if not realOwned[fake.Name] and not seenNames[fake.Name] and merged[k] == nil then
            merged[k] = fake
            seenNames[fake.Name] = true
        end
    end
    State.emote_merged = merged
    State.emote_merged_ref = rawItems
    return merged
end

Emotes.installHooks = function()
    if State.emote_installed then return true end
    if not State.inventory_shared or not State.item_info then return false end
    local shared = State.inventory_shared
    State.emote_raw_get = State.original_funcs.Get or shared.Get

    local prevGet = shared.Get
    shared.Get = function(self, player, itemType)
        if State.emote_enabled and player == nil and itemType == "Emote" then
            return Emotes.getMerged()
        end
        return prevGet(self, player, itemType)
    end

    local prevGetItem = shared.GetItem
    shared.GetItem = function(self, player, itemType, itemName)
        local result = prevGetItem(self, player, itemType, itemName)
        if result or not State.emote_enabled or player ~= nil or itemType ~= "Emote" then
            return result
        end
        local catalog = State.item_info.Emote
        if typeof(catalog) ~= "table" then return result end
        if catalog[itemName] then
            return { Id = itemName, Name = itemName }
        end
        local ok, conv = pcall(function() return self:StringToItem("Emote", itemName) end)
        if ok and typeof(conv) == "table" and conv.Name and catalog[conv.Name] then
            if conv.Id == nil then conv.Id = conv.Name end
            return conv
        end
        return result
    end

    local prevFindItems = shared.FindItemsWithKey
    if typeof(prevFindItems) == "function" then
        shared.FindItemsWithKey = function(self, player, itemType, key)
            local result = prevFindItems(self, player, itemType, key)
            if not State.emote_enabled or player ~= nil or itemType ~= "Emote" then
                return result
            end
            if typeof(result) == "table" and #result > 0 then return result end
            local catalog = State.item_info.Emote
            if catalog and catalog[key] then return { key } end
            return result
        end
    end

    local prevGetEquippedList = shared.GetEquippedList
    if typeof(prevGetEquippedList) == "function" then
        shared.GetEquippedList = function(self, player, itemType, ...)
            local result = prevGetEquippedList(self, player, itemType, ...)
            if not State.emote_enabled or player ~= nil or itemType ~= "Emote" then
                return result
            end
            local merged = {}
            if typeof(result) == "table" then
                for k, v in pairs(result) do merged[k] = v end
            end
            for k, name in pairs(State.emote_virtual) do
                merged[k] = { Name = name, Id = name }
            end
            return merged
        end
    end

    -- Hook InventoryController.GetFavoriteState for unowned emotes
    if State.inventory_controller and typeof(State.inventory_controller.GetFavoriteState) == "function" then
        local prevGetFav = State.inventory_controller.GetFavoriteState
        State.inventory_controller.GetFavoriteState = function(self, itemType, itemName, ...)
            local result = prevGetFav(self, itemType, itemName, ...)
            if State.emote_enabled and itemType == "Emote" and itemName and typeof(result) == "table" then
                if not Emotes.reallyOwned(itemName) and typeof(result.Get) == "function" and typeof(result.Set) == "function" then
                    State.emote_fav_statables = State.emote_fav_statables or {}
                    State.emote_fav_statables[itemName] = result
                end
            end
            return result
        end
    end

    -- Hook EmoteController.Play to intercept unowned emote plays
    if State.emote_controller and typeof(State.emote_controller.Play) == "function" then
        State.emote_ec_play = State.emote_controller.Play
        State.emote_controller.Play = function(self, emoteName, ...)
            if State.emote_enabled and typeof(emoteName) == "string" and emoteName ~= "" then
                if not State.emote_basic[emoteName] and not Emotes.reallyOwned(emoteName) then
                    Emotes.playLocal(emoteName)
                    return
                end
                Emotes.stopLocal()
            end
            return State.emote_ec_play(self, emoteName, ...)
        end
    end

    State.emote_installed = true
    return true
end

Emotes.findControllers = function()
    local controllers = ReplicatedStorage:FindFirstChild("Controllers")
    if not controllers then return end
    local ewc = controllers:FindFirstChild("EmoteWheelController")
    if ewc then
        local ok, mod = pcall(require, ewc)
        if ok and typeof(mod) == "table" then
            State.emote_wheel_controller = mod
        end
    end
    local ec = controllers:FindFirstChild("EmoteController")
    if ec then
        local ok, mod = pcall(require, ec)
        if ok and typeof(mod) == "table" then
            State.emote_controller = mod
        end
    end
    if not State.inventory_controller then
        local trading = controllers:FindFirstChild("Trading")
        local ic = trading and trading:FindFirstChild("InventoryController")
        if not ic then ic = controllers:FindFirstChild("InventoryController", true) end
        if ic then
            local ok, mod = pcall(require, ic)
            if ok and typeof(mod) == "table" then
                State.inventory_controller = mod
            end
        end
    end
end

Emotes.getEmoteWheel = function()
    local pg = localPlayer:FindFirstChild("PlayerGui")
    if not pg then return nil end
    return pg:FindFirstChild("EmoteWheel")
end

Emotes.repaintWheel = function()
    local ctrl = State.emote_wheel_controller
    if not ctrl then return end
    pcall(function() if ctrl.UpdateHolderEmotes then ctrl:UpdateHolderEmotes() end end)
    pcall(function() if ctrl.updateCenterText then ctrl:updateCenterText() end end)
    pcall(function() if ctrl.UpdateMenuContentEmotes then ctrl:UpdateMenuContentEmotes() end end)
    pcall(function() if ctrl.populateEmoteList then ctrl:populateEmoteList() end end)
end

Emotes.destroyCustomList = function()
    if State.emote_inventory_obj then
        pcall(function() State.emote_inventory_obj:Destroy() end)
        State.emote_inventory_obj = nil
    end
    if State.emote_our_container then
        pcall(function() State.emote_our_container:Destroy() end)
        State.emote_our_container = nil
    end
    -- restore original emote content if we hid it
    if State.emote_original_content then
        pcall(function()
            State.emote_original_content.Visible = true
            State.emote_original_content.Active = true
            if State.emote_original_pos then
                State.emote_original_content.Position = State.emote_original_pos
            end
        end)
        State.emote_original_content = nil
        State.emote_original_pos = nil
    end
end

Emotes.findStatable = function()
    if State.emote_statable then return State.emote_statable end
    local shared = ReplicatedStorage:FindFirstChild("Shared")
    if not shared then return nil end
    local mod = shared:FindFirstChild("Statable")
    if not mod then return nil end
    local ok, result = pcall(require, mod)
    if ok and typeof(result) == "table" then
        State.emote_statable = result
        return result
    end
    return nil
end

-- Flyte-style emote UI: hook controllers, paint wheel slots, no custom containers
Emotes.setEmoteButton = function(slot, emoteName)
    local folder = ReplicatedStorage:FindFirstChild("Misc")
    folder = folder and folder:FindFirstChild("Emotes")
    if not folder then return end
    local anim = folder:FindFirstChild(emoteName)
    if not anim then return end
    local displayName = anim:GetAttribute("EmoteName") or anim.Name
    local icon = anim:GetAttribute("Icon") or ""
    local pg = localPlayer:FindFirstChild("PlayerGui")
    local ew = pg and pg:FindFirstChild("EmoteWheel")
    if not ew then return end
    local wheel = ew:FindFirstChild("Wheel")
    local menu = ew:FindFirstChild("Menu")
    local holder = wheel and wheel:FindFirstChild("Holder")
    local menuContent = menu and menu:FindFirstChild("Content")
    local ctrl = State.emote_wheel_controller
    local page = ctrl and tonumber(ctrl.page) or 1
    local pageSize = 8
    local slotPage = math.floor((slot - 1) / pageSize) + 1
    local targets = {}
    if slotPage == page and holder then
        local el = holder:FindFirstChild(tostring((slot - 1) % pageSize + 1))
        if el then table.insert(targets, el) end
    end
    if menuContent then
        local el = menuContent:FindFirstChild(tostring(slot))
        if el then table.insert(targets, el) end
    end
    for _, el in targets do
        el:SetAttribute("EmoteId", emoteName)
        el:SetAttribute("EmoteName", displayName)
        local vec = el:FindFirstChild("Vector")
        if vec then
            vec.Image = icon
        elseif el:IsA("ImageButton") then
            el.Image = icon
        end
        local txt = el:FindFirstChild("Title") or el:FindFirstChild("ItemName") or el:FindFirstChild("Text")
        if txt and txt:IsA("TextLabel") then
            txt.Text = displayName
        end
    end
end

Emotes.refreshEmoteSlots = function()
    if not State.emote_virtual then return end
    for slot, name in pairs(State.emote_virtual) do
        Emotes.setEmoteButton(tonumber(slot) or slot, name)
    end
end

Emotes.patchEmoteControllers = function()
    if State.emote_controllers_patched then return end
    local ctrl = State.emote_controller
    local wheelCtrl = State.emote_wheel_controller
    if not ctrl or not wheelCtrl then return end

    -- Hook EmoteController.Play to intercept unowned emote plays
    if not State.emote_orig_play then
        State.emote_orig_play = ctrl.Play
        ctrl.Play = function(self, emoteName, ...)
            if State.emote_enabled and typeof(emoteName) == "string" and emoteName ~= "" then
                local folder = ReplicatedStorage:FindFirstChild("Misc")
                folder = folder and folder:FindFirstChild("Emotes")
                local anim = folder and folder:FindFirstChild(emoteName)
                if anim and anim.AnimationId ~= "" and anim.AnimationId ~= "rbxassetid://0" then
                    return Emotes.playLocal(emoteName)
                end
            end
            return State.emote_orig_play(self, emoteName, ...)
        end
    end

    -- Hook UpdateHolderEmotes + UpdateMenuContentEmotes to repaint after native updates
    for _, fnName in ipairs({"UpdateHolderEmotes", "UpdateMenuContentEmotes"}) do
        if wheelCtrl[fnName] and not State["emote_orig_" .. fnName] then
            State["emote_orig_" .. fnName] = wheelCtrl[fnName]
            wheelCtrl[fnName] = function(self, ...)
                local result = State["emote_orig_" .. fnName](self, ...)
                if State.emote_enabled then
                    task.defer(Emotes.refreshEmoteSlots)
                end
                return result
            end
        end
    end

    State.emote_controllers_patched = true
end

Emotes.unpatchEmoteControllers = function()
    if not State.emote_controllers_patched then return end
    local ctrl = State.emote_controller
    local wheelCtrl = State.emote_wheel_controller
    if ctrl and State.emote_orig_play then
        ctrl.Play = State.emote_orig_play
        State.emote_orig_play = nil
    end
    for _, fnName in ipairs({"UpdateHolderEmotes", "UpdateMenuContentEmotes"}) do
        if wheelCtrl and State["emote_orig_" .. fnName] then
            wheelCtrl[fnName] = State["emote_orig_" .. fnName]
            State["emote_orig_" .. fnName] = nil
        end
    end
    State.emote_controllers_patched = false
end

-- Hook emote cards in the emote list so clicking assigns to wheel slot
Emotes._cardConns = {}
Emotes._buttonConns = {}

Emotes.currentAbsSlot = function()
    local ctrl = State.emote_wheel_controller
    if not ctrl then return 1 end
    local n = tonumber(ctrl.selected) or 1
    if n < 1 then n = 1 end
    if ctrl.type == "Wheel" then
        local page = tonumber(ctrl.page) or 1
        return math.clamp(n, 1, 8) + (page - 1) * 8
    end
    return math.clamp(n, 1, 24)
end

Emotes.bindEmoteCard = function(btn)
    if not State.emote_enabled then return end
    if not btn:IsA("GuiButton") then return end
    local nameLabel = btn:FindFirstChild("ItemName")
    if not nameLabel then return end
    if Emotes._buttonConns[btn] then
        for _, c in Emotes._buttonConns[btn] do pcall(function() c:Disconnect() end) end
        Emotes._buttonConns[btn] = nil
    end
    -- Find emote name from display name
    local emoteName = nil
    local folder = ReplicatedStorage:FindFirstChild("Misc")
    folder = folder and folder:FindFirstChild("Emotes")
    if folder then
        for _, anim in folder:GetChildren() do
            if anim:IsA("Animation") then
                local display = anim:GetAttribute("EmoteName") or anim.Name
                if display == nameLabel.Text then
                    emoteName = anim.Name
                    break
                end
            end
        end
    end
    if not emoteName then return end
    local conns = {}
    table.insert(conns, btn.Activated:Connect(function()
        if not State.emote_enabled then return end
        local slot = Emotes.currentAbsSlot()
        if not State.emote_virtual then State.emote_virtual = {} end
        State.emote_virtual[slot] = emoteName
        persistConfig()
        Emotes.setEmoteButton(slot, emoteName)
        Emotes.repaintWheel()
        -- Close emote list
        pcall(function()
            local pg = localPlayer:FindFirstChild("PlayerGui")
            local ew = pg and pg:FindFirstChild("EmoteWheel")
            if ew then
                local list = ew:FindFirstChild("List")
                if list and list:IsA("GuiObject") then list.Visible = false end
            end
        end)
    end))
    Emotes._buttonConns[btn] = conns
end

Emotes.hookEmoteCard = function(el)
    if not State.emote_enabled then return end
    if not el:IsA("GuiButton") or not el:FindFirstChild("ItemName") then return end
    if Emotes._cardConns[el] then return end
    local nameLabel = el:FindFirstChild("ItemName")
    Emotes._cardConns[el] = nameLabel:GetPropertyChangedSignal("Text"):Connect(function()
        task.defer(Emotes.bindEmoteCard, el)
    end)
    task.defer(Emotes.bindEmoteCard, el)
end

Emotes.hookEmoteList = function()
    local pg = localPlayer:FindFirstChild("PlayerGui")
    local ew = pg and pg:FindFirstChild("EmoteWheel")
    if not ew then return end
    local list = ew:FindFirstChild("List")
    local content = list and list:FindFirstChild("Content")
    if not content then return end
    for _, desc in content:GetDescendants() do
        Emotes.hookEmoteCard(desc)
    end
    table.insert(State.emote_connections, content.DescendantAdded:Connect(function(desc)
        task.defer(Emotes.hookEmoteCard, desc)
    end))
end

Emotes.unhookEmoteCards = function()
    for el, conn in pairs(Emotes._cardConns) do
        pcall(function() conn:Disconnect() end)
    end
    Emotes._cardConns = {}
    for el, conns in pairs(Emotes._buttonConns) do
        for _, c in conns do pcall(function() c:Disconnect() end) end
    end
    Emotes._buttonConns = {}
end

-- Legacy stubs
Emotes.buildEmoteList = function() return true end
Emotes.refreshEmoteList = function() end
Emotes.bindWheelSlot = function() end
Emotes.bindWheelSlots = function() end

-- Keep repaintWheel but add slot refresh
local _oldRepaintWheel = Emotes.repaintWheel
Emotes.repaintWheel = function()
    if _oldRepaintWheel then pcall(_oldRepaintWheel) end
    task.defer(Emotes.refreshEmoteSlots)
end

-- Dummy to stop old code from breaking
local _dummyBuildList = true
-- old buildEmoteList body removed, using Flyte hook approach now

Emotes.syncListVisibility = function() end

Emotes.enable = function()
    if not Unlocker.loadModules() then
        warn("[Emotes] Failed to load game modules")
        return false
    end
    State.emote_boot_id = State.emote_boot_id + 1
    local bootId = State.emote_boot_id
    Emotes.loadAnimations()
    Emotes.findControllers()

    if not State.emote_installed then
        if not Emotes.installHooks() then
            warn("[Emotes] Failed to install hooks")
            return false
        end
    end
    State.emote_enabled = true
    Config.emote_enabled = true
    State.emote_merged = nil
    State.emote_merged_ref = nil
    Emotes.refreshOwned()

    -- Patch controllers (Flyte approach — hook Play + UpdateHolder/UpdateMenu)
    Emotes.patchEmoteControllers()
    Emotes.repaintWheel()

    task.spawn(function()
        local pg = localPlayer:WaitForChild("PlayerGui", 15)
        if not pg or State.emote_boot_id ~= bootId then return end
        local ew = pg:WaitForChild("EmoteWheel", 15)
        if not ew or not State.emote_enabled or State.emote_boot_id ~= bootId then return end

        -- Hook emote list cards for slot assignment
        Emotes.hookEmoteList()

        table.insert(State.emote_connections, ew:GetPropertyChangedSignal("Enabled"):Connect(function()
            if ew.Enabled and State.emote_enabled then
                task.defer(function()
                    Emotes.repaintWheel()
                    Emotes.hookEmoteList()
                end)
            end
        end))
    end)

    if State.emote_loop then
        pcall(function() task.cancel(State.emote_loop) end)
    end
    State.emote_loop = nil

    persistConfig()
    return true
end

Emotes.disable = function()
    State.emote_enabled = false
    Config.emote_enabled = false
    if State.emote_loop then
        pcall(function() task.cancel(State.emote_loop) end)
        State.emote_loop = nil
    end
    Emotes.stopLocal()
    Emotes.unpatchEmoteControllers()
    Emotes.unhookEmoteCards()
    Emotes.destroyCustomList()
    for _, conn in ipairs(State.emote_connections) do
        pcall(function()
            if typeof(conn) == "function" then conn()
            elseif conn.Disconnect then conn:Disconnect()
            elseif conn.Destroy then conn:Destroy()
            end
        end)
    end
    table.clear(State.emote_connections)
    State.emote_merged = nil
    State.emote_merged_ref = nil
    -- Force native emote wheel to refresh
    pcall(function()
        local ctrl = State.emote_wheel_controller
        if ctrl then
            if ctrl.UpdateHolderEmotes then ctrl:UpdateHolderEmotes() end
            if ctrl.UpdateMenuContentEmotes then ctrl:UpdateMenuContentEmotes() end
            if ctrl.updateCenterText then ctrl:updateCenterText() end
        end
    end)
    persistConfig()
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

    local main = Instance.new("Frame")
    main.Size = UDim2.new(0, 320, 0, 520)
    main.Position = UDim2.new(1, -340, 0.5, -260)
    main.BackgroundColor3 = C.bg
    main.BorderSizePixel = 0
    main.Active = true
    main.Draggable = true
    main.Parent = gui
    Instance.new("UICorner", main).CornerRadius = UDim.new(0, 12)
    local mainStroke = Instance.new("UIStroke", main)
    mainStroke.Color = C.border; mainStroke.Thickness = 1

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

    local header = Instance.new("Frame")
    header.Size = UDim2.new(1, 0, 0, 44)
    header.BackgroundColor3 = C.header
    header.BorderSizePixel = 0
    header.Parent = main
    local hc = Instance.new("UICorner", header); hc.CornerRadius = UDim.new(0, 12)
    local hfill = Instance.new("Frame", header); hfill.Size = UDim2.new(1, 0, 0, 14); hfill.Position = UDim2.new(0, 0, 1, -14); hfill.BackgroundColor3 = C.header; hfill.BorderSizePixel = 0

    local accentBar = Instance.new("Frame", main)
    accentBar.Size = UDim2.new(1, -24, 0, 2)
    accentBar.Position = UDim2.new(0, 12, 0, 44)
    accentBar.BackgroundColor3 = C.accent
    accentBar.BorderSizePixel = 0
    Instance.new("UICorner", accentBar).CornerRadius = UDim.new(0, 1)

    local title = Instance.new("TextLabel", header)
    title.Size = UDim2.new(1, -80, 1, 0); title.Position = UDim2.new(0, 16, 0, 0)
    title.BackgroundTransparency = 1; title.Text = "Avatar Changer"
    title.TextColor3 = C.text; title.TextSize = 15; title.Font = Enum.Font.GothamBold
    title.TextXAlignment = Enum.TextXAlignment.Left

    local minBtn = Instance.new("TextButton", header)
    minBtn.Size = UDim2.new(0, 28, 0, 28); minBtn.Position = UDim2.new(1, -68, 0, 8)
    minBtn.BackgroundColor3 = C.input; minBtn.Text = "_"; minBtn.TextColor3 = C.dim
    minBtn.TextSize = 14; minBtn.Font = Enum.Font.GothamBold; minBtn.BorderSizePixel = 0
    Instance.new("UICorner", minBtn).CornerRadius = UDim.new(0, 6)

    local closeBtn = Instance.new("TextButton", header)
    closeBtn.Size = UDim2.new(0, 28, 0, 28); closeBtn.Position = UDim2.new(1, -36, 0, 8)
    closeBtn.BackgroundColor3 = C.danger; closeBtn.BackgroundTransparency = 0.7
    closeBtn.Text = "X"; closeBtn.TextColor3 = C.dim
    closeBtn.TextSize = 12; closeBtn.Font = Enum.Font.GothamBold; closeBtn.BorderSizePixel = 0
    Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 6)

    closeBtn.MouseButton1Click:Connect(function() main.Visible = false end)
    minBtn.MouseButton1Click:Connect(function() main.Visible = false end)

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
    local avatarInput = mkInput("Username or UserId to copy...", Config.avatar_target, function(t) Config.avatar_target = t; Config.spoof_avatar_user = t; persistConfig() end)
    mkToggle("Enable Avatar Changer", Config.avatar_enabled, function(on)
        Config.avatar_enabled = on; persistConfig()
        if on then Avatar.saveOriginal(); if Config.avatar_target ~= "" then Avatar.apply(Config.avatar_target) end
        else Avatar.restore() end
    end)
    mkButton("Restore Original", Color3.fromRGB(70, 70, 95), function()
        Config.avatar_enabled = false; persistConfig(); Avatar.restore()
    end)

    mkSpacer(6)

    -- Quick Toggles
    mkSection("QUICK TOGGLES")
    mkToggle("Headless", Config.headless_enabled, setHeadless)
    mkToggle("Korblox Leg", Config.korblox_enabled, setKorblox)

    mkSpacer(6)

    -- Name Spoofer
    mkSection("NAME SPOOFER")
    mkToggle("Enable Name Spoofer", Config.spoofer_enabled, function(on)
        Config.spoofer_enabled = on; persistConfig()
        if on then
            Spoofer.init()
        else
            Spoofer.revertAll()
        end
    end)
    mkInput("Spoofed Username", Config.spoof_username, function(t)
        Config.spoof_username = t; persistConfig()
        if Config.spoofer_enabled then Spoofer.reapplyAll() end
    end)
    mkInput("Spoofed Display Name", Config.spoof_displayname, function(t)
        Config.spoof_displayname = t; persistConfig()
        if Config.spoofer_enabled then Spoofer.reapplyAll() end
    end)
    mkInput("Avatar Thumbnail User", Config.spoof_avatar_user, function(t)
        Config.spoof_avatar_user = t; persistConfig()
        if Config.spoofer_enabled then Spoofer.reapplyAll() end
    end)

    mkSpacer(6)

    -- Unlock All
    mkSection("UNLOCK ALL")
    local unlockStatus = Instance.new("TextLabel", scroll)
    unlockStatus.Size = UDim2.new(1, -4, 0, 20); unlockStatus.BackgroundTransparency = 1
    unlockStatus.Text = "  Status: Off"; unlockStatus.TextColor3 = C.dim
    unlockStatus.TextSize = 11; unlockStatus.Font = Enum.Font.Gotham
    unlockStatus.TextXAlignment = Enum.TextXAlignment.Left; unlockStatus.LayoutOrder = nextOrd()

    mkToggle("Unlock All Swords + Explosions", Config.unlock_all_enabled, function(on)
        if on then
            unlockStatus.Text = "  Status: Loading..."
            task.spawn(function()
                local ok = Unlocker.enable()
                unlockStatus.Text = ok and "  Status: Active" or "  Status: Failed"
                unlockStatus.TextColor3 = ok and C.accent2 or C.danger
            end)
        else
            Unlocker.disable()
            unlockStatus.Text = "  Status: Off"
            unlockStatus.TextColor3 = C.dim
        end
    end)

    local note = Instance.new("TextLabel", scroll)
    note.Size = UDim2.new(1, -4, 0, 40); note.BackgroundTransparency = 1
    note.Text = "  Open the sword/explosion shop after enabling.\n  Click any item to equip. You can also delete\n  fake items — they reappear on re-enable."
    note.TextColor3 = C.dim; note.TextSize = 10; note.Font = Enum.Font.Gotham
    note.TextXAlignment = Enum.TextXAlignment.Left; note.TextWrapped = true; note.LayoutOrder = nextOrd()

    local emoteStatus = Instance.new("TextLabel", scroll)
    emoteStatus.Size = UDim2.new(1, -4, 0, 20); emoteStatus.BackgroundTransparency = 1
    emoteStatus.Text = "  Emotes: Off"; emoteStatus.TextColor3 = C.dim
    emoteStatus.TextSize = 11; emoteStatus.Font = Enum.Font.Gotham
    emoteStatus.TextXAlignment = Enum.TextXAlignment.Left; emoteStatus.LayoutOrder = nextOrd()

    mkToggle("Unlock All Emotes", Config.emote_enabled or false, function(on)
        if on then
            emoteStatus.Text = "  Emotes: Loading..."
            task.spawn(function()
                local ok = Emotes.enable()
                emoteStatus.Text = ok and "  Emotes: Active" or "  Emotes: Failed"
                emoteStatus.TextColor3 = ok and C.accent2 or C.danger
            end)
        else
            Emotes.disable()
            emoteStatus.Text = "  Emotes: Off"
            emoteStatus.TextColor3 = C.dim
        end
    end)

    local emoteNote = Instance.new("TextLabel", scroll)
    emoteNote.Size = UDim2.new(1, -4, 0, 30); emoteNote.BackgroundTransparency = 1
    emoteNote.Text = "  Opens all emotes in the emote wheel.\n  Unowned emotes play client-side only."
    emoteNote.TextColor3 = C.dim; emoteNote.TextSize = 10; emoteNote.Font = Enum.Font.Gotham
    emoteNote.TextXAlignment = Enum.TextXAlignment.Left; emoteNote.TextWrapped = true; emoteNote.LayoutOrder = nextOrd()

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
                persistConfig()
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

    -- Background loop: refresh shop when visible + unlock active
    task.spawn(function()
        local wasVisible = false
        while gui.Parent do
            if State.unlock_active then
                local visible = Unlocker.isShopVisible()
                if visible and (not wasVisible or State.refresh_dirty or not State.shop_spoofed) then
                    task.spawn(function()
                        Unlocker.forceRefreshVirtualItems()
                    end)
                end
                wasVisible = visible
            end
            task.wait(wasVisible and 0.3 or 1.5)
        end
    end)

    -- Auto-enable features that were saved as on
    task.spawn(function()
        local char = localPlayer.Character or localPlayer.CharacterAdded:Wait()
        if char then
            local hum = char:FindFirstChildOfClass("Humanoid") or char:WaitForChild("Humanoid", 5)
            if hum then
                pcall(function()
                    if not localPlayer:HasAppearanceLoaded() then
                        localPlayer.CharacterAppearanceLoaded:Wait()
                    end
                end)
            end
        end
        task.wait(0.3)
        if Config.avatar_enabled and Config.avatar_target ~= "" then
            Avatar.saveOriginal()
            Avatar.apply(Config.avatar_target)
        end
        if Config.headless_enabled then
            char = localPlayer.Character
            if char then applyHeadless(char) end
        end
        if Config.korblox_enabled then
            char = localPlayer.Character
            if char then applyKorblox(char) end
        end
        if Config.spoofer_enabled then
            Spoofer.init()
        end
        if Config.unlock_all_enabled then
            unlockStatus.Text = "  Status: Loading..."
            local ok = Unlocker.enable()
            unlockStatus.Text = ok and "  Status: Active" or "  Status: Failed"
            unlockStatus.TextColor3 = ok and C.accent2 or C.danger
        end
        if Config.emote_enabled then
            emoteStatus.Text = "  Emotes: Loading..."
            local ok = Emotes.enable()
            emoteStatus.Text = ok and "  Emotes: Active" or "  Emotes: Failed"
            emoteStatus.TextColor3 = ok and C.accent2 or C.danger
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
print("[Avatar Changer] Settings are saved automatically between executions.")
