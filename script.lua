--[[=====================================================================
  VENICE HUB v6  ·  BLOX FRUITS  ·  Xeno / UNC / Solara / Delta
  RightControl = toggle UI   |   RightShift = unload
  Hover-over-mob farming: pin mobs under you, big hitbox, native attack.
=====================================================================]]

local Players     = game:GetService("Players")
local RS          = game:GetService("ReplicatedStorage")
local RunService  = game:GetService("RunService")
local UIS         = game:GetService("UserInputService")
local Tween       = game:GetService("TweenService")
local StarterGui  = game:GetService("StarterGui")
local VirtualUser = game:GetService("VirtualUser")
local VIM         = game:GetService("VirtualInputManager")
local Http        = game:GetService("HttpService")
local Lighting    = game:GetService("Lighting")
local TeleportSvc = game:GetService("TeleportService")

local LP = Players.LocalPlayer
if not LP then return end

if getgenv and getgenv().VeniceHub and getgenv().VeniceHub.Gui then
    pcall(function() getgenv().VeniceHub.Gui:Destroy() end)
end

local function log(...)
    local t = {}
    for i = 1, select("#", ...) do t[#t + 1] = tostring(select(i, ...)) end
    print("[VeniceHub] " .. table.concat(t, " "))
end
local function notify(text, title)
    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = title or "Venice Hub", Text = tostring(text), Duration = 5 })
    end)
    log(text)
end

--=====================================================================
--  COMBAT FRAMEWORK + NET
--=====================================================================
local CombatFramework, CameraShaker
local function loadCombat()
    if not CombatFramework then
        pcall(function()
            local ps = LP:WaitForChild("PlayerScripts", 15)
            local cf = ps and ps:WaitForChild("CombatFramework", 15)
            if cf then CombatFramework = require(cf) end
        end)
    end
    if not CameraShaker then
        pcall(function()
            local util = RS:FindFirstChild("Util")
            local cs = util and util:FindFirstChild("CameraShaker")
            if cs then CameraShaker = require(cs) end
        end)
    end
    return CombatFramework ~= nil
end

local Net = (getgenv and getgenv().VeniceHubNet) or
    { hitId = nil, hooked = false, combo = 0, fallbackTried = false }
if getgenv then getgenv().VeniceHubNet = Net end

local RA_cache, RH_cache
local function netModules()
    if RA_cache and RH_cache and RA_cache.Parent and RH_cache.Parent then
        return RA_cache, RH_cache
    end
    local mods = RS:FindFirstChild("Modules")
    local n = mods and mods:FindFirstChild("Net")
    if not n then return nil, nil end
    RA_cache = n:FindFirstChild("RE/RegisterAttack")
    RH_cache = n:FindFirstChild("RE/RegisterHit")
    return RA_cache, RH_cache
end

local function installHitCapture()
    if Net.hooked then return true end
    local _, RegisterHit = netModules()
    if not RegisterHit then return false end
    if not (hookmetamethod and getnamecallmethod and checkcaller and newcclosure) then
        log("hitId capture unavailable")
        return false
    end
    local old
    old = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
        if not checkcaller() and getnamecallmethod() == "FireServer" and self == RegisterHit then
            local a = table.pack(...)
            if a[4] ~= nil then
                Net.hitId = a[4]
            elseif a.n == 1 and type(a[1]) == "string" then
                Net.hitId = a[1]
            end
        end
        return old(self, ...)
    end))
    Net.hooked = true
    log("hitId capture installed")
    return true
end

local function ensureHitId()
    if Net.hitId then return Net.hitId end
    if Net.fallbackTried then return nil end
    Net.fallbackTried = true
    local _, RegisterHit = netModules()
    if not RegisterHit then return nil end
    local id = tostring(LP.UserId):sub(2, 4) .. tostring(math.floor(os.clock() * 100000))
    pcall(function() RegisterHit:FireServer(id) end)
    Net.hitId = id
    log("hitId fallback generated")
    return id
end

local Remotes = RS:FindFirstChild("Remotes") or RS:WaitForChild("Remotes", 30)
local CommF_  = Remotes and (Remotes:FindFirstChild("CommF_") or Remotes:WaitForChild("CommF_", 30))

local function invoke(...)
    if not CommF_ then
        Remotes = RS:FindFirstChild("Remotes")
        CommF_ = Remotes and Remotes:FindFirstChild("CommF_")
    end
    if not CommF_ then return nil end
    local args = { ... }
    local ok, res = pcall(function() return CommF_:InvokeServer(table.unpack(args)) end)
    return ok and res or nil
end

task.spawn(function()
    for _ = 1, 60 do
        loadCombat()
        installHitCapture()
        if CombatFramework and Net.hooked then break end
        task.wait(0.5)
    end
end)

--=====================================================================
--  CONFIG
--=====================================================================
local CONFIG_DIR  = "VeniceHub"
local CONFIG_FILE = CONFIG_DIR .. "/bloxfruits_v6.json"
local WP_FILE     = CONFIG_DIR .. "/waypoints.json"

local DEFAULTS = {
    FlySpeed = 220,
    -- farming / positioning
    AutoFarm = false, FarmNearest = false, BossFarm = false,
    HoverHeight = 25,        -- you float this far above the pinned mob stack
    EngageRange = 60,        -- fly when the nearest mob is farther than this
    MagnetRange = 300,       -- mobs inside this radius get pinned under you
    BringMob = true, FreezeMobs = true, BigHitbox = true,
    -- attack
    AttackMethod = "Native", Hitbox = 120, AttackInterval = 0.1, FastAttack = false,
    AutoEquip = true, EquipType = "Melee",
    QuestIndex = 0, BossIndex = 1, MaterialIndex = 1, MaterialFarm = false, AutoSaber = false,
    AutoPoints = false, Stat = "Melee", StatAmount = 1,
    AutoChest = false, AutoLoot = false, AutoFruit = false,
    CollectSpeed = 400, LootRange = 600,
    -- pvp
    KillAura = false, AuraRange = 80, LOS = false,
    AttackPlayers = false, PlayerRange = 60,
    Aimbot = false, AimSmooth = 15, Follow = false, Duel1v1 = false, Spectate = false,
    AutoSkills = false, SkillInterval = 250,
    KeyZ = true, KeyX = true, KeyC = false, KeyV = false, KeyF = false,
    AutoBounty = false, BountyTeam = "Both", BountyMethod = "Nearest",
    NoFriends = true, NoCup = true, NoStun = false, SafeHP = 20,
    -- player
    Speed = 16, Jump = 50, InfEnergy = false, Noclip = false, Fly = false,
    AutoBuso = true, AutoKen = false, AntiAFK = true, Fullbright = false,
    ESPMobs = false, ESPPlayers = false, ESPChests = false, ESPFruits = false,
    IslandIndex = 1, BossTPIndex = 1,
}

local S = {}
for k, v in pairs(DEFAULTS) do S[k] = v end

local function saveConfig()
    if not writefile then return end
    pcall(function()
        if isfolder and not isfolder(CONFIG_DIR) then makefolder(CONFIG_DIR) end
        writefile(CONFIG_FILE, Http:JSONEncode(S))
    end)
end
local function loadConfig()
    if not (readfile and isfile) then return end
    pcall(function()
        if not isfile(CONFIG_FILE) then return end
        for k, v in pairs(Http:JSONDecode(readfile(CONFIG_FILE))) do
            if S[k] ~= nil and type(S[k]) == type(v) then S[k] = v end
        end
    end)
end
local function resetConfig()
    for k, v in pairs(DEFAULTS) do S[k] = v end
    saveConfig()
end
loadConfig()

--=====================================================================
--  HELPERS
--=====================================================================
local function hrp() local c = LP.Character; return c and c:FindFirstChild("HumanoidRootPart") end
local function hum() local c = LP.Character; return c and c:FindFirstChildOfClass("Humanoid") end
local function level()
    local ok, v = pcall(function() return LP.Data.Level.Value end)
    return (ok and v) or 1
end
local function enemies() return workspace:FindFirstChild("Enemies") end
local function locations()
    local wo = workspace:FindFirstChild("_WorldOrigin")
    return wo and wo:FindFirstChild("Locations")
end
local function ping()
    local ok, p = pcall(function() return LP:GetNetworkPing() end)
    return ok and math.floor(p * 1000) or 0
end
local function sea()
    local id = game.PlaceId
    if id == 4442272183 then return 2 end
    if id == 7449423635 then return 3 end
    return 1
end

--=====================================================================
--  TELEPORT
--=====================================================================
local activeTween
local function tpCancel()
    if activeTween then pcall(function() activeTween:Cancel() end) activeTween = nil end
end
local function tpGo(pos, speed)
    if not pos then return end
    local h = hrp()
    if not h then return end
    local dist = (h.Position - pos).Magnitude
    if dist < 0.5 then return end
    local t = math.clamp(dist / math.max(speed or S.FlySpeed, 1), 0.05, 90)
    tpCancel()
    local tw = Tween:Create(h, TweenInfo.new(t, Enum.EasingStyle.Linear), { CFrame = CFrame.new(pos) })
    activeTween = tw
    tw.Completed:Connect(function() if activeTween == tw then activeTween = nil end end)
    tw:Play()
    return tw
end
RunService.Heartbeat:Connect(function()
    if not activeTween then return end
    local c = LP.Character
    local h = c and c:FindFirstChild("HumanoidRootPart")
    if h then h.AssemblyLinearVelocity = Vector3.zero end
    if c then
        for _, p in ipairs(c:GetDescendants()) do
            if p:IsA("BasePart") and p.CanCollide then p.CanCollide = false end
        end
    end
end)

--=====================================================================
--  DATA
--=====================================================================
local ISLANDS = {
    [1] = {
        { "Middle Town",        Vector3.new(-1193.9, 12, -549.8) },
        { "Pirate Starter",     Vector3.new(1038, 15, 1550) },
        { "Marine Starter",     Vector3.new(-2674.5, 32.1, 2187.0) },
        { "Jungle",             Vector3.new(-1866.3, 29.9, 21.6) },
        { "Buggy Island",       Vector3.new(-981.0, 30.4, 3966.8) },
        { "Desert Island",      Vector3.new(999.9, 7.6, 4490.3) },
        { "Snow Island",        Vector3.new(1519.5, 78.0, -1510.9) },
        { "Marineford",         Vector3.new(-4763.7, 13.4, 4288.8) },
        { "Sky Islands",        Vector3.new(-4973.7, 280.7, -1119.4) },
        { "Mob Island (Saber)", Vector3.new(-1527.2, 34.1, -33.2) },
        { "Impel Down",         Vector3.new(5278.6, 7.1, 391.6) },
        { "Colosseum",          Vector3.new(-1973.1, 9.0, -2744.9) },
        { "Volcano",            Vector3.new(-5623.8, 17.0, 8314.1) },
        { "Fishman Island",     Vector3.new(3894.3, 4.0, -1915.2) },
        { "Upper Sky Islands",  Vector3.new(-6040.2, 5468.0, 1734.2) },
        { "Water 7",            Vector3.new(5430.4, 78.0, 3953.6) },
    },
    [2] = {
        { "Kingdom of Rose",  Vector3.new(-195.1, 155.3, 279.9) },
        { "Cafe",             Vector3.new(-380.4, 72.8, 303.2) },
        { "Mansion",          Vector3.new(-393.3, 367.3, 687.5) },
        { "Colosseum",        Vector3.new(-1836.4, 72.8, 1360.2) },
        { "Swan's Room",      Vector3.new(2293.7, 12.5, 663.1) },
        { "Factory",          Vector3.new(431.0, 238.4, -433.2) },
        { "Green Zone",       Vector3.new(-2340.8, 155.3, -3396.3) },
        { "Dark Arena",       Vector3.new(3807.1, 11.8, -3452.2) },
        { "Graveyard Island", Vector3.new(-5577.9, 87.6, -782.2) },
        { "Snow Mountain",    Vector3.new(856.2, 50.3, -5278.3) },
        { "Hot and Cold",     Vector3.new(-5734.3, 49.4, -5146.4) },
        { "Cursed Ship",      Vector3.new(900.9, 144.0, 33072.6) },
        { "Ice Castle",       Vector3.new(6062.3, 155.3, -6880.9) },
        { "Forgotten Island", Vector3.new(-3194.2, 155.3, -10795.3) },
    },
    [3] = {
        { "Port Town",               Vector3.new(-610.4, 57.8, 6436.3) },
        { "Dragon Dojo",             Vector3.new(5704.4, 1168.1, 937.0) },
        { "Castle on the Sea",       Vector3.new(-5436.6, 815.6, -2701.7) },
        { "Floating Turtle",         Vector3.new(-12164.6, -548.9, -8454.9) },
        { "Friendly Arena",          Vector3.new(5012.8, 72.8, -1570.6) },
        { "Great Tree",              Vector3.new(3036.3, 815.6, -7149.9) },
        { "Haunted Castle",          Vector3.new(-9530.6, -132.9, 5763.1) },
        { "Beautiful Pirate Domain", Vector3.new(5366.6, 71.2, -225.9) },
        { "Mansion",                 Vector3.new(-12547.7, 290.1, -7487.1) },
        { "North Pole",              Vector3.new(-1141.1, 57.8, -14480.7) },
        { "Sea of Treats",           Vector3.new(-1505.3, 57.8, -10724.1) },
        { "Secret Temple",           Vector3.new(5226.2, 63.5, 858.8) },
        { "Tiki Outpost",            Vector3.new(-16641.5, 213.3, 435.4) },
        { "Heavenly Dimension",      Vector3.new(-22709.6, 5259.0, 3886.6) },
        { "Hell Dimension",          Vector3.new(-22737.6, 5120.0, 2234.6) },
    },
}
local BOSSES = {
    [1] = {
        { "Chef", 55, Vector3.new(-1120.5, 54.7, 4121.2) },
        { "Yeti", 110, Vector3.new(1181.7, 104.0, -1616.9) },
        { "Mob Boss", 120, Vector3.new(-2880.7, 6.7, 5430.9) },
        { "Saber Expert", 200, Vector3.new(-1527.2, 34.1, -33.2) },
        { "Warden", 230, Vector3.new(5623.2, 1.4, 733.8) },
        { "Magma General", 350, Vector3.new(-5625.7, 55.4, 8623.0) },
        { "Fishman Lord", 425, Vector3.new(61352.9, 67.2, 1029.1) },
        { "Sky Warlord", 500, Vector3.new(-6271.6, 5472.8, 1887.8) },
        { "Cyborg", 675, Vector3.new(6252.4, 9.3, 4941.4) },
        { "Ice Admiral", 700, Vector3.new(1212.4, 20.4, -1429.6) },
    },
    [2] = {
        { "Diamond", 750, Vector3.new(-1711.4, 206.0, -97.1) },
        { "Jeremy", 850, Vector3.new(2338.0, 451.4, 700.1) },
        { "Smoke Admiral", 1150, Vector3.new(-4857.4, 233.7, -5583.2) },
        { "Awakened Ice Admiral", 1400, Vector3.new(6551.8, 325.3, -6989.9) },
        { "rip_indra", 1500, Vector3.new(-26952.3, 21.5, 329.4) },
    },
    [3] = {
        { "Kilo Admiral", 1750, Vector3.new(2998.3, 508.8, -7344.3) },
        { "Captain Elephant", 1875, Vector3.new(-13365.5, 321.2, -8485.0) },
        { "Longma", 2000, Vector3.new(-10156.2, 337.8, -9445.9) },
        { "Cake Queen", 2175, Vector3.new(-678.5, 381.9, -11114.3) },
        { "Cake Prince", 2200, Vector3.new(-2089.9, 4536.9, -14800.0) },
    },
}
local QUESTS = {
    [1] = {
        { id="BanditQuest1", tier=1, lvl=1, mob="Bandit" },
        { id="JungleQuest", tier=1, lvl=10, mob="Monkey" },
        { id="JungleQuest", tier=2, lvl=15, mob="Gorilla" },
        { id="BuggyQuest1", tier=1, lvl=30, mob="Pirate" },
        { id="BuggyQuest1", tier=2, lvl=40, mob="Brute" },
        { id="DesertQuest", tier=1, lvl=60, mob="Desert Bandit" },
        { id="DesertQuest", tier=2, lvl=75, mob="Desert Officer" },
        { id="SnowQuest", tier=1, lvl=90, mob="Snow Bandit" },
        { id="SnowQuest", tier=2, lvl=100, mob="Snowman" },
        { id="MarineQuest2", tier=1, lvl=120, mob="Chief Petty Officer" },
        { id="MarineQuest2", tier=2, lvl=130, mob="Vice Admiral" },
        { id="SkyQuest", tier=1, lvl=150, mob="Sky Bandit" },
        { id="SkyQuest", tier=2, lvl=175, mob="Dark Master" },
        { id="PrisonerQuest", tier=1, lvl=190, mob="Prisoner" },
        { id="PrisonerQuest", tier=2, lvl=210, mob="Dangerous Prisoner" },
        { id="ColosseumQuest", tier=1, lvl=250, mob="Toga Warrior" },
        { id="ColosseumQuest", tier=2, lvl=275, mob="Gladiator" },
        { id="MagmaQuest", tier=1, lvl=300, mob="Military Soldier" },
        { id="MagmaQuest", tier=2, lvl=325, mob="Military Spy" },
        { id="FishmanQuest", tier=1, lvl=375, mob="Fishman Warrior" },
        { id="FishmanQuest", tier=2, lvl=400, mob="Fishman Commando" },
        { id="SkyExp1Quest", tier=1, lvl=450, mob="God's Guard" },
        { id="SkyExp1Quest", tier=2, lvl=475, mob="Shanda" },
        { id="SkyExp2Quest", tier=1, lvl=525, mob="Royal Squad" },
        { id="SkyExp2Quest", tier=2, lvl=550, mob="Royal Soldier" },
        { id="FountainQuest", tier=1, lvl=625, mob="Galley Pirate" },
        { id="FountainQuest", tier=2, lvl=650, mob="Galley Captain" },
    },
    [2] = {
        { id="Area1Quest", tier=1, lvl=700, mob="Raider" },
        { id="Area1Quest", tier=2, lvl=725, mob="Mercenary" },
        { id="Area2Quest", tier=1, lvl=775, mob="Swan Pirate" },
        { id="Area2Quest", tier=2, lvl=800, mob="Factory Staff" },
        { id="MarineQuest3", tier=1, lvl=875, mob="Marine Lieutenant" },
        { id="MarineQuest3", tier=2, lvl=900, mob="Marine Captain" },
        { id="ZombieQuest", tier=1, lvl=950, mob="Zombie" },
        { id="ZombieQuest", tier=2, lvl=975, mob="Vampire" },
        { id="SnowMountainQuest", tier=1, lvl=1000, mob="Snow Trooper" },
        { id="SnowMountainQuest", tier=2, lvl=1050, mob="Winter Warrior" },
        { id="IceSideQuest", tier=1, lvl=1100, mob="Lab Subordinate" },
        { id="IceSideQuest", tier=2, lvl=1125, mob="Horned Warrior" },
        { id="FireSideQuest", tier=1, lvl=1175, mob="Magma Ninja" },
        { id="FireSideQuest", tier=2, lvl=1200, mob="Lava Pirate" },
        { id="ShipQuest1", tier=1, lvl=1250, mob="Ship Deckhand" },
        { id="ShipQuest1", tier=2, lvl=1275, mob="Ship Engineer" },
        { id="ShipQuest2", tier=1, lvl=1300, mob="Ship Steward" },
        { id="ShipQuest2", tier=2, lvl=1325, mob="Ship Officer" },
        { id="FrostQuest", tier=1, lvl=1350, mob="Arctic Warrior" },
        { id="FrostQuest", tier=2, lvl=1375, mob="Snow Lurker" },
        { id="ForgottenQuest", tier=1, lvl=1425, mob="Sea Soldier" },
        { id="ForgottenQuest", tier=2, lvl=1450, mob="Water Fighter" },
    },
    [3] = {
        { id="PiratePortQuest", tier=1, lvl=1500, mob="Pirate Millionaire" },
        { id="PiratePortQuest", tier=2, lvl=1525, mob="Pistol Billionaire" },
        { id="DragonCrewQuest", tier=1, lvl=1575, mob="Dragon Crew Warrior" },
        { id="VenomCrewQuest", tier=4, lvl=1700, mob="Marine Commodore" },
        { id="VenomCrewQuest", tier=5, lvl=1725, mob="Marine Rear Admiral" },
        { id="VenomCrewQuest", tier=7, lvl=1775, mob="Fishman Raider" },
        { id="VenomCrewQuest", tier=8, lvl=1800, mob="Fishman Captain" },
        { id="VenomCrewQuest", tier=9, lvl=1825, mob="Forest Pirate" },
        { id="VenomCrewQuest", tier=10, lvl=1850, mob="Mythological Pirate" },
        { id="VenomCrewQuest", tier=12, lvl=1900, mob="Jungle Pirate" },
        { id="VenomCrewQuest", tier=13, lvl=1925, mob="Musketeer Pirate" },
        { id="HauntedQuest1", tier=1, lvl=1975, mob="Reborn Skeleton" },
        { id="HauntedQuest1", tier=2, lvl=2000, mob="Living Zombie" },
        { id="HauntedQuest2", tier=2, lvl=2050, mob="Posessed Mummy" },
        { id="NutsIslandQuest", tier=1, lvl=2075, mob="Peanut Scout" },
        { id="NutsIslandQuest", tier=2, lvl=2100, mob="Peanut President" },
        { id="IceCreamIslandQuest", tier=1, lvl=2125, mob="Ice Cream Chef" },
        { id="IceCreamIslandQuest", tier=2, lvl=2150, mob="Ice Cream Commander" },
        { id="CakeQuest2", tier=1, lvl=2250, mob="Baking Staff" },
        { id="CakeQuest2", tier=2, lvl=2275, mob="Head Baker" },
        { id="ChocQuest1", tier=1, lvl=2300, mob="Cocoa Warrior" },
        { id="ChocQuest1", tier=2, lvl=2325, mob="Chocolate Bar Battler" },
        { id="ChocQuest2", tier=1, lvl=2350, mob="Sweet Thief" },
        { id="ChocQuest2", tier=2, lvl=2375, mob="Candy Rebel" },
        { id="CandyQuest1", tier=1, lvl=2400, mob="Candy Pirate" },
        { id="CandyQuest1", tier=2, lvl=2425, mob="Snow Demon" },
        { id="TikiQuest1", tier=1, lvl=2450, mob="Isle Outlaw" },
        { id="TikiQuest1", tier=2, lvl=2475, mob="Island Boy" },
        { id="TikiQuest2", tier=1, lvl=2500, mob="Sun-kissed Warrior" },
        { id="TikiQuest2", tier=2, lvl=2525, mob="Isle Champion" },
        { id="TikiQuest3", tier=1, lvl=2550, mob="Serpent Hunter" },
        { id="TikiQuest3", tier=2, lvl=2575, mob="Skull Slayer" },
        { id="SubmergedQuest1", tier=1, lvl=2600, mob="Reef Bandit" },
        { id="SubmergedQuest1", tier=2, lvl=2625, mob="Coral Pirate" },
        { id="SubmergedQuest2", tier=1, lvl=2650, mob="Sea Chanter" },
        { id="SubmergedQuest2", tier=2, lvl=2675, mob="Ocean Prophet" },
        { id="SubmergedQuest3", tier=2, lvl=2700, mob="Grand Devotee" },
    },
}
local SPAWNS = {
    ["Bandit"]=Vector3.new(1143.7,17.4,1574.7), ["Monkey"]=Vector3.new(-1866.3,29.9,21.6),
    ["Gorilla"]=Vector3.new(-1266.6,14.5,-462.0), ["Pirate"]=Vector3.new(-981.0,30.4,3966.8),
    ["Brute"]=Vector3.new(-1085.9,28.1,4342.7), ["Desert Bandit"]=Vector3.new(999.9,7.6,4490.3),
    ["Desert Officer"]=Vector3.new(1523.8,15.3,4095.4), ["Snow Bandit"]=Vector3.new(1519.5,78.0,-1510.9),
    ["Snowman"]=Vector3.new(1121.5,98.2,-1669.0), ["Chief Petty Officer"]=Vector3.new(-4763.7,13.4,4288.8),
    ["Vice Admiral"]=Vector3.new(-5090.0,30.0,4200.0), ["Sky Bandit"]=Vector3.new(-4973.7,280.7,-1119.4),
    ["Dark Master"]=Vector3.new(-5283.2,505.1,-221.0), ["Prisoner"]=Vector3.new(5278.6,7.1,391.6),
    ["Dangerous Prisoner"]=Vector3.new(5058.3,9.1,900.9), ["Toga Warrior"]=Vector3.new(-1973.1,9.0,-2744.9),
    ["Gladiator"]=Vector3.new(-1161.9,11.6,-3097.2), ["Military Soldier"]=Vector3.new(-5623.8,17.0,8314.1),
    ["Military Spy"]=Vector3.new(-5952.5,76.9,8742.4), ["Fishman Warrior"]=Vector3.new(60736.8,23.8,1396.3),
    ["Fishman Commando"]=Vector3.new(61808.1,24.6,1328.6), ["God's Guard"]=Vector3.new(-4082.9,1087.3,-414.1),
    ["Shanda"]=Vector3.new(-6040.2,5468.0,1734.2), ["Royal Squad"]=Vector3.new(-6706.9,5551.4,1155.4),
    ["Royal Soldier"]=Vector3.new(-7138.5,5541.1,1050.8), ["Galley Pirate"]=Vector3.new(5430.4,78.0,3953.6),
    ["Galley Captain"]=Vector3.new(5409.5,77.7,4687.0), ["Raider"]=Vector3.new(-612.4,40.0,2557.4),
    ["Mercenary"]=Vector3.new(-1135.9,72.9,1248.3), ["Swan Pirate"]=Vector3.new(1067.0,72.8,1080.9),
    ["Factory Staff"]=Vector3.new(386.1,72.8,91.8), ["Marine Lieutenant"]=Vector3.new(-2583.9,71.0,-3039.6),
    ["Marine Captain"]=Vector3.new(-2103.9,73.0,-3259.3), ["Zombie"]=Vector3.new(-5615.0,49.3,-938.5),
    ["Vampire"]=Vector3.new(-6132.4,9.0,-1466.2), ["Snow Trooper"]=Vector3.new(484.3,400.8,-5472.4),
    ["Winter Warrior"]=Vector3.new(1226.3,428.8,-5216.0), ["Lab Subordinate"]=Vector3.new(-5998.3,90.0,-4386.5),
    ["Horned Warrior"]=Vector3.new(-6540.0,29.2,-5718.0), ["Magma Ninja"]=Vector3.new(-5711.4,47.4,-5658.5),
    ["Lava Pirate"]=Vector3.new(-5111.3,32.2,-5115.9), ["Ship Deckhand"]=Vector3.new(1157.3,125.6,32930.1),
    ["Ship Engineer"]=Vector3.new(834.8,43.7,32720.9), ["Ship Steward"]=Vector3.new(801.4,125.8,33505.2),
    ["Ship Officer"]=Vector3.new(694.5,179.9,33112.6), ["Arctic Warrior"]=Vector3.new(6271.3,27.6,-6151.5),
    ["Snow Lurker"]=Vector3.new(5524.2,27.6,-6583.8), ["Sea Soldier"]=Vector3.new(-2550.9,28.5,-9840.0),
    ["Water Fighter"]=Vector3.new(-3331.7,239.1,-10553.4),
    ["Pirate Millionaire"]=Vector3.new(-232.9,57.0,5757.8), ["Pistol Billionaire"]=Vector3.new(-54.8,83.8,5947.8),
    ["Dragon Crew Warrior"]=Vector3.new(7217.8,56.6,-680.8), ["Marine Commodore"]=Vector3.new(2577.3,75.6,-7739.9),
    ["Marine Rear Admiral"]=Vector3.new(3920.1,146.2,-7175.2), ["Fishman Raider"]=Vector3.new(-10223.1,332.6,-8482.5),
    ["Fishman Captain"]=Vector3.new(-10736.7,331.8,-8807.6), ["Forest Pirate"]=Vector3.new(-13105.5,332.2,-7705.8),
    ["Mythological Pirate"]=Vector3.new(-13221.0,519.1,-6689.0), ["Jungle Pirate"]=Vector3.new(-12321.3,331.4,-10669.3),
    ["Musketeer Pirate"]=Vector3.new(-13556.1,391.4,-9735.9), ["Reborn Skeleton"]=Vector3.new(-8710.1,141.0,6112.9),
    ["Living Zombie"]=Vector3.new(-10170.9,141.2,6159.6), ["Posessed Mummy"]=Vector3.new(-9399.6,12.2,6118.8),
    ["Peanut Scout"]=Vector3.new(-1924.0,37.3,-10199.7), ["Peanut President"]=Vector3.new(-1993.4,37.2,-10682.9),
    ["Ice Cream Chef"]=Vector3.new(-502.4,64.6,-10873.8), ["Ice Cream Commander"]=Vector3.new(-366.8,64.7,-11094.4),
    ["Baking Staff"]=Vector3.new(-1774.1,34.7,-12850.5), ["Head Baker"]=Vector3.new(-2389.2,51.0,-13018.3),
    ["Cocoa Warrior"]=Vector3.new(-128.7,26.2,-12249.8), ["Chocolate Bar Battler"]=Vector3.new(598.8,25.6,-12395.1),
    ["Sweet Thief"]=Vector3.new(-77.6,25.6,-12765.6), ["Candy Rebel"]=Vector3.new(166.8,25.6,-13035.3),
    ["Candy Pirate"]=Vector3.new(-1226.8,36.3,-14777.6), ["Snow Demon"]=Vector3.new(-936.2,14.0,-14552.5),
    ["Isle Outlaw"]=Vector3.new(-16351.8,23.5,-282.5), ["Island Boy"]=Vector3.new(-16736.2,22.2,-131.7),
    ["Sun-kissed Warrior"]=Vector3.new(-16413.5,56.7,1054.4), ["Isle Champion"]=Vector3.new(-16735.7,23.3,1110.6),
    ["Serpent Hunter"]=Vector3.new(-16536.0,106.9,1347.1), ["Skull Slayer"]=Vector3.new(-16829.4,193.2,1753.4),
    ["Reef Bandit"]=Vector3.new(10899.9,-2145.2,9279.3), ["Coral Pirate"]=Vector3.new(10703.7,-2087.3,9255.4),
    ["Sea Chanter"]=Vector3.new(10680.1,-2056.7,9933.9), ["Ocean Prophet"]=Vector3.new(11129.8,-2007.8,10051.5),
    ["Grand Devotee"]=Vector3.new(9559.2,-1994.4,9798.7),
}
local KILLS = {
    Bandit=5, Monkey=6, Gorilla=8, Pirate=8, Brute=8, ["Desert Bandit"]=8, ["Desert Officer"]=6,
    ["Snow Bandit"]=7, Snowman=8, ["Chief Petty Officer"]=8, ["Vice Admiral"]=1, ["Sky Bandit"]=7,
    ["Dark Master"]=8, Prisoner=8, ["Dangerous Prisoner"]=8, ["Toga Warrior"]=7, Gladiator=8,
    ["Military Soldier"]=7, ["Military Spy"]=8, ["Fishman Warrior"]=8, ["Fishman Commando"]=7,
    Shanda=9, ["Royal Squad"]=8, ["Royal Soldier"]=8, ["Galley Pirate"]=8, ["Galley Captain"]=9,
}
local MATERIALS = {
    [2] = { { "Scrap Metal","Factory Staff" }, { "Vampire Fang","Vampire" },
            { "Magma Ore","Magma Ninja" }, { "Conjured Cocoa","Ship Deckhand" },
            { "Mystic Droplet","Water Fighter" } },
    [3] = { { "Fish Tail","Fishman Raider" }, { "Mystic Droplet","Ocean Prophet" },
            { "Ectoplasm","Reborn Skeleton" }, { "Dragon Scale","Dragon Crew Warrior" },
            { "Gunpowder","Pirate Millionaire" } },
}

--=====================================================================
--  QUERIES
--=====================================================================
local function mobsNamed(name)
    local out, f = {}, enemies()
    if not f then return out end
    local lower = name:lower()
    for _, e in ipairs(f:GetChildren()) do
        if e.Name:lower() == lower then
            local h = e:FindFirstChildOfClass("Humanoid")
            if h and h.Health > 0 then out[#out + 1] = e end
        end
    end
    return out
end

local function nearestMob(name)
    local h, f = hrp(), enemies()
    if not h or not f then return nil end
    local lower = name:lower()
    local best, bd
    for _, e in ipairs(f:GetChildren()) do
        if e.Name:lower() == lower then
            local hu = e:FindFirstChildOfClass("Humanoid")
            local p = e:FindFirstChild("HumanoidRootPart") or e.PrimaryPart
            if hu and hu.Health > 0 and p then
                local d = (p.Position - h.Position).Magnitude
                if not bd or d < bd then best, bd = e, d end
            end
        end
    end
    return best
end

local function nearestAnyMob(range)
    local h, f = hrp(), enemies()
    if not h or not f then return nil end
    local best, bd
    for _, e in ipairs(f:GetChildren()) do
        local hu = e:FindFirstChildOfClass("Humanoid")
        local p = e:FindFirstChild("HumanoidRootPart") or e.PrimaryPart
        if hu and hu.Health > 0 and p then
            local d = (p.Position - h.Position).Magnitude
            if d <= (range or 1e9) and (not bd or d < bd) then best, bd = e, d end
        end
    end
    return best
end

local function getChests()
    local out, loc, h = {}, locations(), hrp()
    if not loc then return out end
    for _, v in ipairs(loc:GetChildren()) do
        if v:IsA("BasePart") then
            local n = v.Name:lower()
            if n:find("chest") or n:find("barrel") then
                out[#out + 1] = { part = v, d = h and (v.Position - h.Position).Magnitude or 0 }
            end
        end
    end
    return out
end

local FRUIT_SET = {}
do
    local names = {
        "Rocket","Spin","Chop","Spring","Bomb","Smoke","Spike","Flame","Falcon","Ice","Sand","Dark",
        "Diamond","Light","Rubber","Barrier","Ghost","Magma","Door","Blizzard","Gravity","Mammoth",
        "T-Rex","Dough","Shadow","Venom","Control","Spirit","Dragon","Leopard","Kitsune","Buddha",
        "Portal","Rumble","Paw","Sound","Phoenix","Pain","Love","Creation","Spider","Magnet","Yeti",
        "Gas","Revive","Eagle","Wolf","Quake","Lightning","Gem","Rift",
    }
    for _, f in ipairs(names) do
        FRUIT_SET[f] = true
        FRUIT_SET[f .. "-" .. f] = true
    end
end

local function isFruitPart(v)
    if not v:FindFirstChild("Handle") then return false end
    local o = v:GetAttribute("OriginalName")
    if o and tostring(o):find("%-") then return true end
    if FRUIT_SET[v.Name] then return true end
    local base = v.Name:match("^(.-)%-")
    if base and FRUIT_SET[base] then return true end
    return false
end

local function getGroundFruits()
    local out, h = {}, hrp()
    local function scan(cont)
        if not cont then return end
        for _, v in ipairs(cont:GetChildren()) do
            if (v:IsA("Model") or v:IsA("Tool")) and isFruitPart(v) then
                local hd = v.Handle
                out[#out + 1] = { model = v, part = hd, name = v.Name,
                    d = h and (hd.Position - h.Position).Magnitude or 0 }
            end
        end
    end
    scan(workspace)
    for _, c in ipairs(workspace:GetChildren()) do
        if c:IsA("Folder") then scan(c) end
    end
    return out
end

local function getLoot(range)
    local out, h = {}, hrp()
    if not h then return out end
    for _, v in ipairs(workspace:GetChildren()) do
        if (v:IsA("Model") or v:IsA("Tool")) and v:FindFirstChild("Handle") and not isFruitPart(v) then
            local n = v.Name:lower()
            if not (n:find("chest") or n:find("barrel")) then
                local hd = v.Handle
                local d = (hd.Position - h.Position).Magnitude
                if d <= (range or 600) then out[#out + 1] = { part = hd, d = d } end
            end
        end
    end
    return out
end

--=====================================================================
--  ATTACK LAYER
--=====================================================================
local function isRod(t)
    if not t then return false end
    local tip = t.ToolTip
    return (tip and (tostring(tip):find("Fishing") or tostring(tip):find("Rod"))) or t.Name:find("Rod") ~= nil
end

local function ensureNotRod()
    local c = LP.Character
    local eq = c and c:FindFirstChildOfClass("Tool")
    if eq and isRod(eq) then
        local h = c:FindFirstChildOfClass("Humanoid")
        if h then pcall(function() h:UnequipTools() end) end
    end
end

local function isFruitTool(t)
    local o = t:GetAttribute("OriginalName")
    return (o and tostring(o):find("%-") ~= nil) or t.ToolTip == "Blox Fruit"
end

local function equipKind(kind)
    local c = LP.Character
    local h = c and c:FindFirstChildOfClass("Humanoid")
    if not (c and h) then return end
    local function match(t)
        if kind == "Fruit" then return isFruitTool(t) end
        return t.ToolTip == kind
    end
    local eq = c:FindFirstChildOfClass("Tool")
    if eq and match(eq) and not isRod(eq) then return end
    for _, pool in ipairs({ c, LP:FindFirstChild("Backpack") }) do
        if pool then
            for _, t in ipairs(pool:GetChildren()) do
                if t:IsA("Tool") and match(t) and not isRod(t) then
                    pcall(function() h:EquipTool(t) end)
                    return
                end
            end
        end
    end
end

-- native: drive the game's own attack with a huge hitbox -> long reach
local function nativeAttack()
    local ac = CombatFramework and CombatFramework.activeController
    if not ac then return false end
    local ok = pcall(function()
        ac.attacking = false
        ac.blocking = false
        ac.timeToNextAttack = 0
        ac.timeToNextBlock = 0
        ac.increment = 3
        ac.hitboxMagnitude = S.Hitbox
        local c = LP.Character
        if c then
            local stun = c:FindFirstChild("Stun")
            if stun and stun:IsA("ValueBase") then stun.Value = 0 end
            local hu = c:FindFirstChildOfClass("Humanoid")
            if hu and hu.Sit then hu.Sit = false end
        end
        if CameraShaker and CameraShaker.Stop then pcall(function() CameraShaker:Stop() end) end
        ac:attack()
    end)
    return ok
end

local function mouseAttack()
    local ok = pcall(function()
        VirtualUser:CaptureController()
        VirtualUser:Button1Down(Vector2.new(1280, 672))
    end)
    return ok
end

local function remoteHit(enemy)
    local RA, RH = netModules()
    if not (RA and RH) then return end
    local function fire(targets)
        if #targets == 0 then return end
        local id = ensureHitId()
        Net.combo = (Net.combo % 4) + 1
        pcall(function()
            RA:FireServer(0.4, Net.combo)
            for i = 1, #targets do
                local p = targets[i]:FindFirstChild("HumanoidRootPart") or targets[i].PrimaryPart
                if p then RH:FireServer(p, {}, nil, id) end
            end
        end)
    end
    if S.BringMob and bestQ then
        fire(mobsNamed(bestQ.mob))
    elseif enemy and enemy.Parent then
        fire({ enemy })
    end
end

local function doAttack(enemy)
    if not LP.Character then return end
    ensureNotRod()
    local m = S.AttackMethod
    local did = false
    if m == "Native" or m == "Native + Remote" then
        did = nativeAttack()
    elseif m == "Mouse" then
        did = mouseAttack()
    end
    if (not did) or m == "Remote" or m == "Native + Remote" then
        remoteHit(enemy)
    end
end

local function losClear(from, part, ignore)
    local filter = { LP.Character }
    if ignore then filter[#filter + 1] = ignore end
    local rp = RaycastParams.new()
    rp.FilterType = Enum.RaycastFilterType.Exclude
    rp.FilterDescendantsInstances = filter
    return workspace:Raycast(from, part.Position - from, rp) == nil
end

local function playersInRange(range)
    local h, out = hrp(), {}
    if not h then return out end
    for _, p in ipairs(Players:GetPlayers()) do
        local c = (p ~= LP) and p.Character
        local ph = c and c:FindFirstChild("HumanoidRootPart")
        local hu = c and c:FindFirstChildOfClass("Humanoid")
        if ph and hu and hu.Health > 0 and (ph.Position - h.Position).Magnitude <= range then
            out[#out + 1] = c
        end
    end
    return out
end

local function nearestPlayer(range)
    local h = hrp()
    if not h then return nil end
    local best, bd
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LP and p.Character then
            local ph = p.Character:FindFirstChild("HumanoidRootPart")
            local hu = p.Character:FindFirstChildOfClass("Humanoid")
            if ph and hu and hu.Health > 0 then
                local d = (ph.Position - h.Position).Magnitude
                if (not range or d <= range) and (not bd or d < bd) then best, bd = p, d end
            end
        end
    end
    return best
end

local function effDelay() return S.FastAttack and 0.08 or S.AttackInterval end

local function pressKey(name)
    local kc = Enum.KeyCode[name]
    if not kc then return end
    pcall(function()
        VIM:SendKeyEvent(true, kc, false, game)
        task.wait(0.03)
        VIM:SendKeyEvent(false, kc, false, game)
    end)
end

--=====================================================================
--  FARM
--=====================================================================
local curKey, target, pinPos, killCount, prevAlive, bestQ
local farmGen = 0
local decollided = setmetatable({}, { __mode = "k" })

local function questList() return QUESTS[sea()] or QUESTS[1] end

local function bestQuest()
    local lv, best, list = level(), nil, questList()
    for _, q in ipairs(list) do
        if q.lvl <= lv then best = q else break end
    end
    return best or list[1]
end

local function currentQuest()
    if S.QuestIndex and S.QuestIndex > 0 then
        return questList()[S.QuestIndex] or bestQuest()
    end
    return bestQuest()
end

local function startQuest()
    local q = currentQuest()
    if q then invoke("StartQuest", q.id, q.tier) end
end

local function resetFarmState()
    curKey, target, pinPos, killCount, prevAlive, bestQ = nil, nil, nil, 0, nil, nil
    decollided = setmetatable({}, { __mode = "k" })
end

-- slow loop: target selection, quest bookkeeping, travel
local function farmMove()
    local q = currentQuest()
    if not q then return end
    bestQ = q

    local alive = mobsNamed(q.mob)
    local curr = {}
    for i = 1, #alive do curr[alive[i]] = true end
    if prevAlive then
        for e in pairs(prevAlive) do if not curr[e] then killCount = killCount + 1 end end
    end
    prevAlive = curr

    local key = q.id .. "#" .. q.tier
    local need = KILLS[q.mob] or 8
    if key ~= curKey then
        curKey, killCount = key, 0
        startQuest()
    elseif killCount >= need then
        killCount = 0
        startQuest()
    end

    local t = nearestMob(q.mob)
    if not t then
        target, pinPos = nil, nil
        local sp, h = SPAWNS[q.mob], hrp()
        if sp and h and (h.Position - sp).Magnitude > 120 then
            tpGo(sp + Vector3.new(0, S.HoverHeight, 0))
        end
        return
    end
    target = t

    local p = t:FindFirstChild("HumanoidRootPart") or t.PrimaryPart
    local h = hrp()
    if not (p and h) then return end
    local dist = (p.Position - h.Position).Magnitude

    if S.BringMob then
        -- drop the pin when the stack is dead / drifted away
        if pinPos then
            local near = false
            for i = 1, #alive do
                local ep = alive[i]:FindFirstChild("HumanoidRootPart")
                if ep and (ep.Position - pinPos).Magnitude < S.MagnetRange then near = true break end
            end
            if not near then pinPos = nil end
        end
        if not pinPos then
            if dist > S.EngageRange then
                tpGo(p.Position + Vector3.new(0, S.HoverHeight, 0))
            else
                pinPos = p.Position
                tpCancel()
            end
        end
    elseif dist > S.EngageRange then
        tpGo(p.Position + Vector3.new(0, S.HoverHeight, 0))
    end
end

local function runFarm()
    local gen = farmGen
    task.spawn(function()
        installHitCapture()
        loadCombat()
        while S.AutoFarm and farmGen == gen do
            local ok, err = pcall(farmMove)
            if not ok then log("farm: " .. tostring(err)) end
            task.wait(0.12)
        end
    end)
end

-- fast loop: hover above the pin, keep the stack glued underneath
RunService.RenderStepped:Connect(function()
    if not (S.AutoFarm or S.BossFarm or S.FarmNearest) then return end
    local h = hrp()
    if not h then return end
    if h.Anchored then h.Anchored = false end

    if S.BringMob and pinPos and bestQ then
        -- hover above the stack
        h.CFrame = CFrame.new(pinPos + Vector3.new(0, S.HoverHeight, 0))
        h.AssemblyLinearVelocity = Vector3.zero

        local f = enemies()
        if not f then return end
        local lower = bestQ.mob:lower()
        for _, e in ipairs(f:GetChildren()) do
            if e.Name:lower() == lower then
                local hu = e:FindFirstChildOfClass("Humanoid")
                local ep = e:FindFirstChild("HumanoidRootPart") or e.PrimaryPart
                if hu and hu.Health > 0 and ep and (ep.Position - pinPos).Magnitude < S.MagnetRange then
                    if not decollided[e] then
                        for _, bp in ipairs(e:GetDescendants()) do
                            if bp:IsA("BasePart") then bp.CanCollide = false end
                        end
                        decollided[e] = true
                    end
                    if S.BigHitbox and ep.Size ~= Vector3.new(60, 60, 60) then
                        ep.Size = Vector3.new(60, 60, 60)
                    end
                    if S.FreezeMobs then
                        if not hu.PlatformStand then hu.PlatformStand = true end
                        if hu.WalkSpeed ~= 0 then hu.WalkSpeed = 0 end
                        if hu.JumpPower ~= 0 then hu.JumpPower = 0 end
                    end
                    ep.CFrame = CFrame.new(pinPos)
                    ep.AssemblyLinearVelocity = Vector3.zero
                end
            end
        end
    elseif target and target.Parent and not S.BringMob then
        local p = target:FindFirstChild("HumanoidRootPart") or target.PrimaryPart
        if p and (p.Position - h.Position).Magnitude < S.EngageRange * 2 then
            h.CFrame = CFrame.new(p.Position + Vector3.new(0, S.HoverHeight, 0))
            h.AssemblyLinearVelocity = Vector3.zero
        end
    end
end)

--=====================================================================
--  LOOPS
--=====================================================================
local function farming() return S.AutoFarm or S.BossFarm or S.FarmNearest end

task.spawn(function()  -- attack driver
    local n = 0
    while true do
        if farming() and LP.Character then
            n = n + 1
            if S.AutoEquip and n % 5 == 1 then equipKind(S.EquipType) end
            doAttack(target)
            if S.AttackPlayers then
                local list = playersInRange(S.PlayerRange)
                for i = 1, #list do remoteHit(list[i]) end
            end
            task.wait(effDelay())
        else
            task.wait(0.1)
        end
    end
end)

task.spawn(function()  -- farm nearest
    while true do
        if S.FarmNearest and LP.Character then
            local t = nearestAnyMob(1e9)
            if t then
                target = t
                local p = t:FindFirstChild("HumanoidRootPart") or t.PrimaryPart
                local h = hrp()
                if p and h and (p.Position - h.Position).Magnitude > S.EngageRange then
                    tpGo(p.Position + Vector3.new(0, S.HoverHeight, 0))
                end
            else
                target = nil
            end
            task.wait(0.15)
        else
            task.wait(0.3)
        end
    end
end)

task.spawn(function()  -- boss farm
    while true do
        if S.BossFarm and LP.Character then
            local list = BOSSES[sea()] or BOSSES[1]
            local b = list[math.clamp(S.BossIndex, 1, #list)]
            if b then
                local t = nearestMob(b[1])
                if t then
                    target = t
                    local p = t:FindFirstChild("HumanoidRootPart") or t.PrimaryPart
                    local h = hrp()
                    if p and h and (p.Position - h.Position).Magnitude > S.EngageRange then
                        tpGo(p.Position + Vector3.new(0, S.HoverHeight, 0))
                    end
                else
                    target = nil
                    tpGo(b[3] + Vector3.new(0, S.HoverHeight, 0))
                    task.wait(2)
                end
            end
            task.wait(0.15)
        else
            task.wait(0.3)
        end
    end
end)

task.spawn(function()  -- kill aura
    while true do
        if S.KillAura and LP.Character then
            local h, f = hrp(), enemies()
            local list = {}
            if h and f then
                for _, e in ipairs(f:GetChildren()) do
                    local hu = e:FindFirstChildOfClass("Humanoid")
                    local p = e:FindFirstChild("HumanoidRootPart") or e.PrimaryPart
                    if hu and hu.Health > 0 and p and (p.Position - h.Position).Magnitude <= S.AuraRange then
                        if not S.LOS or losClear(h.Position, p, e) then list[#list + 1] = e end
                    end
                end
            end
            local m = S.AttackMethod
            if m ~= "Remote" then
                if m == "Mouse" then mouseAttack() else nativeAttack() end
            end
            if m ~= "Native" then
                local RA, RH = netModules()
                if RA and RH and #list > 0 then
                    local id = ensureHitId()
                    Net.combo = (Net.combo % 4) + 1
                    pcall(function()
                        RA:FireServer(0.4, Net.combo)
                        for i = 1, #list do
                            local p = list[i]:FindFirstChild("HumanoidRootPart") or list[i].PrimaryPart
                            if p then RH:FireServer(p, {}, nil, id) end
                        end
                    end)
                end
            end
            if S.AttackPlayers then
                local pl = playersInRange(S.AuraRange)
                for i = 1, #pl do remoteHit(pl[i]) end
            end
            task.wait(effDelay())
        else
            task.wait(0.25)
        end
    end
end)

task.spawn(function()  -- auto skills
    while true do
        if S.AutoSkills and LP.Character then
            local order = { { "Z", S.KeyZ }, { "X", S.KeyX }, { "C", S.KeyC },
                            { "V", S.KeyV }, { "F", S.KeyF } }
            for i = 1, #order do
                if not S.AutoSkills then break end
                if order[i][2] then pressKey(order[i][1]) end
            end
        end
        task.wait(S.SkillInterval / 1000)
    end
end)

task.spawn(function()  -- chests
    while true do
        if S.AutoChest and not farming() and LP.Character then
            local list = getChests()
            if #list > 0 then
                table.sort(list, function(a, b) return a.d < b.d end)
                for i = 1, #list do
                    if not S.AutoChest or farming() then break end
                    tpGo(list[i].part.Position + Vector3.new(0, 4, 0), S.CollectSpeed)
                    task.wait(0.15)
                end
            else
                task.wait(0.4)
            end
        else
            task.wait(0.3)
        end
    end
end)

task.spawn(function()  -- loot
    while true do
        if S.AutoLoot and not farming() and LP.Character then
            local list = getLoot(S.LootRange)
            if #list > 0 then
                table.sort(list, function(a, b) return a.d < b.d end)
                for i = 1, #list do
                    if not S.AutoLoot or farming() then break end
                    tpGo(list[i].part.Position + Vector3.new(0, 3, 0), S.CollectSpeed)
                    task.wait(0.12)
                end
            else
                task.wait(0.4)
            end
        else
            task.wait(0.3)
        end
    end
end)

task.spawn(function()  -- fruit
    while true do
        if S.AutoFruit and not farming() and LP.Character then
            local f = getGroundFruits()
            if #f > 0 then
                table.sort(f, function(a, b) return a.d < b.d end)
                tpGo(f[1].part.Position + Vector3.new(0, 3, 0), S.CollectSpeed)
                task.wait(0.25)
            else
                task.wait(0.5)
            end
        else
            task.wait(0.4)
        end
    end
end)

task.spawn(function()  -- haki
    while true do
        local c = LP.Character
        if c then
            if S.AutoBuso and not c:FindFirstChild("HasBuso") then invoke("Buso") end
            if S.AutoKen and not c:FindFirstChild("HasKen") then invoke("Ken") end
        end
        task.wait(0.5)
    end
end)

task.spawn(function()  -- auto points
    while true do
        if S.AutoPoints and LP.Character then
            local d = LP:FindFirstChild("Data")
            local pts = d and d:FindFirstChild("Points")
            if pts and pts.Value and pts.Value >= 1 then
                invoke("AddPoint", S.Stat, math.min(pts.Value, S.StatAmount))
            end
        end
        task.wait(1)
    end
end)

task.spawn(function()  -- bounty
    while true do
        if S.AutoBounty and LP.Character then
            local h = hrp()
            local myH = hum()
            local pct = (myH and myH.MaxHealth > 0) and (myH.Health / myH.MaxHealth * 100) or 100
            if pct < S.SafeHP and h then
                tpGo(h.Position + Vector3.new(0, 220, 0))
                task.wait(1.2)
            else
                local best, bd
                for _, p in ipairs(Players:GetPlayers()) do
                    if p ~= LP and p.Character and h then
                        local ph = p.Character:FindFirstChild("HumanoidRootPart")
                        local phu = p.Character:FindFirstChildOfClass("Humanoid")
                        if ph and phu and phu.Health > 0 then
                            local skip = false
                            if S.NoFriends then
                                local okf, isf = pcall(function() return LP:IsFriendsWith(p.UserId) end)
                                if okf and isf then skip = true end
                            end
                            if S.NoCup and not skip then
                                for _, t in ipairs(p.Character:GetChildren()) do
                                    if t:IsA("Tool") and t.Name == "Cup" then skip = true end
                                end
                            end
                            if S.BountyTeam ~= "Both" and p.Team and not skip then
                                if not p.Team.Name:lower():find(S.BountyTeam:lower()) then skip = true end
                            end
                            if not skip then
                                local d = (S.BountyMethod == "Lowest HP") and phu.Health
                                    or (ph.Position - h.Position).Magnitude
                                if not bd or d < bd then best, bd = p, d end
                            end
                        end
                    end
                end
                if best and best.Character then
                    local ph = best.Character:FindFirstChild("HumanoidRootPart")
                    if ph then
                        tpGo(ph.Position + ph.CFrame.LookVector * -6)
                        doAttack(best.Character)
                    end
                end
                task.wait(effDelay())
            end
        else
            task.wait(0.4)
        end
    end
end)

task.spawn(function()  -- camera
    while true do
        local cam = workspace.CurrentCamera
        if cam then
            if S.Aimbot then
                local p = nearestPlayer(1e9)
                local ph = p and p.Character and p.Character:FindFirstChild("HumanoidRootPart")
                if ph then
                    cam.CFrame = cam.CFrame:Lerp(CFrame.lookAt(cam.CFrame.Position, ph.Position), S.AimSmooth / 100)
                end
            end
            if S.Spectate then
                local p = nearestPlayer(1e9)
                local phu = p and p.Character and p.Character:FindFirstChildOfClass("Humanoid")
                if phu then cam.CameraSubject = phu end
            else
                local myH = hum()
                if myH and cam.CameraSubject ~= myH then cam.CameraSubject = myH end
            end
        end
        if S.Follow and LP.Character then
            local p = nearestPlayer(1e9)
            local ph = p and p.Character and p.Character:FindFirstChild("HumanoidRootPart")
            if ph then
                tpGo(ph.Position + ph.CFrame.LookVector * -6)
                if S.Duel1v1 then doAttack(p.Character) end
            end
        end
        task.wait(0.2)
    end
end)

task.spawn(function()  -- no stun
    while true do
        if S.NoStun then
            local c = LP.Character
            if c then
                local h = c:FindFirstChildOfClass("Humanoid")
                if h and h.PlatformStand then h.PlatformStand = false end
                for _, a in ipairs({ "Stun", "Stunned" }) do
                    if c:GetAttribute(a) then c:SetAttribute(a, false) end
                end
            end
        end
        task.wait(0.1)
    end
end)

--=====================================================================
--  PLAYER / VISUALS
--=====================================================================
local function applyStats()
    local h = hum()
    if h then
        h.WalkSpeed = S.Speed
        h.UseJumpPower = true
        h.JumpPower = S.Jump
    end
end
LP.CharacterAdded:Connect(function()
    task.wait(1.5)
    resetFarmState()
    loadCombat()
    applyStats()
end)

RunService.Stepped:Connect(function()
    if not S.Noclip then return end
    local c = LP.Character
    if c then
        for _, v in ipairs(c:GetDescendants()) do
            if v:IsA("BasePart") and v.CanCollide then v.CanCollide = false end
        end
    end
end)

local flyBV, flyBG
local function startFly()
    local h = hrp()
    if not h then return end
    local hu = hum()
    if hu then hu.PlatformStand = true end
    flyBV = Instance.new("BodyVelocity")
    flyBV.MaxForce = Vector3.new(9e9, 9e9, 9e9)
    flyBV.P = 1e4
    flyBV.Velocity = Vector3.zero
    flyBV.Parent = h
    flyBG = Instance.new("BodyGyro")
    flyBG.MaxTorque = Vector3.new(9e9, 9e9, 9e9)
    flyBG.P = 1e4
    flyBG.CFrame = h.CFrame
    flyBG.Parent = h
end
local function stopFly()
    if flyBV then flyBV:Destroy() flyBV = nil end
    if flyBG then flyBG:Destroy() flyBG = nil end
    local hu = hum()
    if hu then hu.PlatformStand = false end
end

RunService.RenderStepped:Connect(function()
    if not S.Fly then return end
    local h = hrp()
    if not h then return end
    if not flyBV or flyBV.Parent ~= h then startFly() end
    local cam = workspace.CurrentCamera
    local dir = Vector3.zero
    if UIS:IsKeyDown(Enum.KeyCode.W) then dir = dir + cam.CFrame.LookVector end
    if UIS:IsKeyDown(Enum.KeyCode.S) then dir = dir - cam.CFrame.LookVector end
    if UIS:IsKeyDown(Enum.KeyCode.A) then dir = dir - cam.CFrame.RightVector end
    if UIS:IsKeyDown(Enum.KeyCode.D) then dir = dir + cam.CFrame.RightVector end
    if UIS:IsKeyDown(Enum.KeyCode.Space) then dir = dir + Vector3.new(0, 1, 0) end
    if UIS:IsKeyDown(Enum.KeyCode.LeftShift) then dir = dir - Vector3.new(0, 1, 0) end
    if dir.Magnitude > 0 then dir = dir.Unit * S.FlySpeed end
    flyBV.Velocity = dir
    flyBG.CFrame = CFrame.new(h.Position, h.Position + cam.CFrame.LookVector)
end)

task.spawn(function()
    while task.wait(0.4) do
        if S.InfEnergy and LP.Character then
            pcall(function()
                local e = LP:FindFirstChild("Energy")
                if e then e.Value = 1e6 end
                local d = LP:FindFirstChild("Data")
                local de = d and d:FindFirstChild("Energy")
                if de then de.Value = 1e6 end
            end)
        end
    end
end)

local function setESP(inst, color, on)
    local ex = inst:FindFirstChild("VeniceESP")
    if on then
        if not ex then
            local h = Instance.new("Highlight")
            h.Name = "VeniceESP"
            h.FillColor = color
            h.OutlineColor = color
            h.FillTransparency = 0.65
            h.OutlineTransparency = 0
            h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
            h.Adornee = inst
            h.Parent = inst
        else
            ex.FillColor = color
        end
    elseif ex then
        ex:Destroy()
    end
end

task.spawn(function()
    while task.wait(0.7) do
        local f = enemies()
        if f then
            for _, m in ipairs(f:GetChildren()) do
                setESP(m, Color3.fromRGB(255, 85, 85), S.ESPMobs)
            end
        end
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= LP and p.Character then
                setESP(p.Character, Color3.fromRGB(85, 160, 255), S.ESPPlayers)
            end
        end
        local loc = locations()
        if loc then
            for _, v in ipairs(loc:GetChildren()) do
                if v:IsA("BasePart") then
                    local n = v.Name:lower()
                    if n:find("chest") or n:find("barrel") then
                        setESP(v, Color3.fromRGB(255, 215, 80), S.ESPChests)
                    end
                end
            end
        end
        if S.ESPFruits then
            for _, fr in ipairs(getGroundFruits()) do
                setESP(fr.model, Color3.fromRGB(170, 100, 255), true)
            end
        end
    end
end)

LP.Idled:Connect(function()
    if S.AntiAFK then
        pcall(function()
            VirtualUser:CaptureController()
            VirtualUser:Button2Down(Vector2.new())
            VirtualUser:Button2Up(Vector2.new())
        end)
    end
end)

--=====================================================================
--  GUI
--=====================================================================
local Theme = {
    BG = Color3.fromRGB(15, 15, 20), Panel = Color3.fromRGB(25, 25, 34),
    Panel2 = Color3.fromRGB(34, 34, 46), Stroke = Color3.fromRGB(50, 50, 66),
    Accent = Color3.fromRGB(139, 92, 246), Text = Color3.fromRGB(235, 235, 245),
    Sub = Color3.fromRGB(150, 150, 172),
}
local function make(cls, props)
    local o = Instance.new(cls)
    for k, v in pairs(props or {}) do o[k] = v end
    return o
end
local function corner(p, r) return make("UICorner", { CornerRadius = UDim.new(0, r or 6), Parent = p }) end
local function stroke(p, c, t) return make("UIStroke", { Color = c or Theme.Stroke, Thickness = t or 1, Parent = p }) end
local function padding(p, x)
    return make("UIPadding", { PaddingTop = UDim.new(0, x), PaddingBottom = UDim.new(0, x),
        PaddingLeft = UDim.new(0, x), PaddingRight = UDim.new(0, x), Parent = p })
end
local function vlist(p, sp)
    return make("UIListLayout", { FillDirection = Enum.FillDirection.Vertical,
        SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, sp or 5), Parent = p })
end

local Gui = make("ScreenGui", { Name = "VeniceHub", ResetOnSpawn = false,
    IgnoreGuiInset = true, ZIndexBehavior = Enum.ZIndexBehavior.Sibling })
local okP = pcall(function()
    Gui.Parent = (getgenv and gethui and gethui()) or LP:WaitForChild("PlayerGui")
end)
if not okP or not Gui.Parent then Gui.Parent = LP:WaitForChild("PlayerGui") end

local Main = make("Frame", { Name = "Main", Size = UDim2.new(0, 620, 0, 430),
    Position = UDim2.new(0.5, -310, 0.5, -215), BackgroundColor3 = Theme.BG,
    BorderSizePixel = 0, Parent = Gui })
corner(Main, 10)
stroke(Main)

local Bar = make("Frame", { Size = UDim2.new(1, 0, 0, 34), BackgroundColor3 = Theme.Panel,
    BorderSizePixel = 0, Parent = Main })
corner(Bar, 10)
make("Frame", { Size = UDim2.new(1, 0, 0, 12), Position = UDim2.new(0, 0, 1, -12),
    BackgroundColor3 = Theme.Panel, BorderSizePixel = 0, Parent = Bar })
make("TextLabel", { Size = UDim2.new(1, -100, 1, 0), Position = UDim2.new(0, 14, 0, 0),
    BackgroundTransparency = 1, Font = Enum.Font.GothamBold, TextSize = 14, TextColor3 = Theme.Text,
    TextXAlignment = Enum.TextXAlignment.Left, Text = "VENICE HUB v6  ·  BLOX FRUITS", Parent = Bar })

local TabHolder = make("Frame", { Size = UDim2.new(0, 128, 1, -66), Position = UDim2.new(0, 8, 0, 38),
    BackgroundTransparency = 1, Parent = Main })
vlist(TabHolder, 5)
local ContentHolder = make("Frame", { Size = UDim2.new(1, -150, 1, -68), Position = UDim2.new(0, 142, 0, 40),
    BackgroundTransparency = 1, Parent = Main })
local Status = make("TextLabel", { Size = UDim2.new(1, -16, 0, 16), Position = UDim2.new(0, 8, 1, -20),
    BackgroundTransparency = 1, Font = Enum.Font.Code, TextSize = 11, TextColor3 = Theme.Sub,
    TextXAlignment = Enum.TextXAlignment.Left, Text = "idle", Parent = Main })

local tabs = {}
local function newTab(name)
    local btn = make("TextButton", { Size = UDim2.new(1, 0, 0, 26), BackgroundColor3 = Theme.Panel,
        Text = "  " .. name, Font = Enum.Font.GothamMedium, TextSize = 12, TextColor3 = Theme.Sub,
        TextXAlignment = Enum.TextXAlignment.Left, AutoButtonColor = false, Parent = TabHolder })
    corner(btn, 6)
    local page = make("ScrollingFrame", { Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1,
        BorderSizePixel = 0, ScrollBarThickness = 3, ScrollBarImageColor3 = Theme.Stroke,
        CanvasSize = UDim2.new(0, 0, 0, 0), Visible = false, Parent = ContentHolder })
    padding(page, 4)
    local lay = vlist(page, 5)
    lay:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        page.CanvasSize = UDim2.new(0, 0, 0, lay.AbsoluteContentSize.Y + 16)
    end)
    tabs[#tabs + 1] = { btn = btn, page = page }
    btn.MouseButton1Click:Connect(function()
        for i = 1, #tabs do
            tabs[i].page.Visible = false
            tabs[i].btn.BackgroundColor3 = Theme.Panel
            tabs[i].btn.TextColor3 = Theme.Sub
        end
        page.Visible = true
        btn.BackgroundColor3 = Theme.Accent
        btn.TextColor3 = Theme.Text
    end)
    return page
end

local function Section(parent, text)
    return make("TextLabel", { Size = UDim2.new(1, 0, 0, 20), BackgroundTransparency = 1,
        Font = Enum.Font.GothamBold, TextSize = 11, TextColor3 = Theme.Accent,
        TextXAlignment = Enum.TextXAlignment.Left, Text = string.upper(text), Parent = parent })
end

local toggleRegistry = {}

local function Toggle(parent, text, default, cb, key)
    local f = make("Frame", { Size = UDim2.new(1, 0, 0, 27), BackgroundColor3 = Theme.Panel, Parent = parent })
    corner(f, 6)
    stroke(f)
    make("TextLabel", { Size = UDim2.new(1, -54, 1, 0), Position = UDim2.new(0, 9, 0, 0),
        BackgroundTransparency = 1, Font = Enum.Font.Gotham, TextSize = 12, TextColor3 = Theme.Text,
        TextXAlignment = Enum.TextXAlignment.Left, Text = text, Parent = f })
    local track = make("Frame", { Size = UDim2.new(0, 34, 0, 16), Position = UDim2.new(1, -44, 0.5, -8),
        BackgroundColor3 = Theme.Stroke, Parent = f })
    corner(track, 8)
    local knob = make("Frame", { Size = UDim2.new(0, 12, 0, 12), Position = UDim2.new(0, 2, 0.5, -6),
        BackgroundColor3 = Theme.Text, Parent = track })
    corner(knob, 6)

    local state = default and true or false
    local function render()
        Tween:Create(track, TweenInfo.new(0.13), { BackgroundColor3 = state and Theme.Accent or Theme.Stroke }):Play()
        Tween:Create(knob, TweenInfo.new(0.13), {
            Position = state and UDim2.new(1, -14, 0.5, -6) or UDim2.new(0, 2, 0.5, -6) }):Play()
    end
    local function apply(v, fire)
        state = v and true or false
        render()
        if fire and cb then pcall(cb, state) end
    end
    render()

    if key then
        toggleRegistry[key] = toggleRegistry[key] or {}
        table.insert(toggleRegistry[key], function(v) apply(v, false) end)
    end

    local hit = make("TextButton", { Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Text = "", Parent = f })
    hit.MouseButton1Click:Connect(function()
        apply(not state, true)
        if key and toggleRegistry[key] then
            for _, fn in ipairs(toggleRegistry[key]) do fn(state) end
        end
        saveConfig()
    end)
    return f, function(v) apply(v, false) end
end

local function Button(parent, text, cb)
    local b = make("TextButton", { Size = UDim2.new(1, 0, 0, 25), BackgroundColor3 = Theme.Panel2,
        Text = text, Font = Enum.Font.GothamMedium, TextSize = 12, TextColor3 = Theme.Text, Parent = parent })
    corner(b, 6)
    stroke(b)
    b.MouseButton1Click:Connect(function()
        local ok, err = pcall(cb)
        if not ok then notify("Button error: " .. tostring(err)) end
    end)
    return b
end

local function Slider(parent, text, min, max, default, cb)
    local f = make("Frame", { Size = UDim2.new(1, 0, 0, 38), BackgroundColor3 = Theme.Panel, Parent = parent })
    corner(f, 6)
    stroke(f)
    make("TextLabel", { Size = UDim2.new(0.66, 0, 0, 18), Position = UDim2.new(0, 9, 0, 1),
        BackgroundTransparency = 1, Font = Enum.Font.Gotham, TextSize = 12, TextColor3 = Theme.Text,
        TextXAlignment = Enum.TextXAlignment.Left, Text = text, Parent = f })
    local vL = make("TextLabel", { Size = UDim2.new(0.29, -9, 0, 18), Position = UDim2.new(0.70, 0, 0, 1),
        BackgroundTransparency = 1, Font = Enum.Font.GothamMedium, TextSize = 12, TextColor3 = Theme.Accent,
        TextXAlignment = Enum.TextXAlignment.Right, Text = "", Parent = f })
    local bar = make("Frame", { Size = UDim2.new(1, -18, 0, 5), Position = UDim2.new(0, 9, 1, -14),
        BackgroundColor3 = Theme.Stroke, BorderSizePixel = 0, Parent = f })
    corner(bar, 3)
    local fill = make("Frame", { Size = UDim2.new(0, 0, 1, 0), BackgroundColor3 = Theme.Accent,
        BorderSizePixel = 0, Parent = bar })
    corner(fill, 3)
    local function set(v, fire)
        v = math.clamp(v, min, max)
        fill.Size = UDim2.new((v - min) / (max - min), 0, 1, 0)
        vL.Text = tostring(math.floor(v * 100) / 100)
        if fire and cb then pcall(cb, v) end
    end
    set(default, false)
    local hit = make("TextButton", { Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Text = "", Parent = f })
    local drag = false
    local function fromMouse()
        local rel = math.clamp((UIS:GetMouseLocation().X - bar.AbsolutePosition.X) / math.max(bar.AbsoluteSize.X, 1), 0, 1)
        set(min + rel * (max - min), true)
    end
    hit.MouseButton1Down:Connect(function() drag = true fromMouse() end)
    UIS.InputChanged:Connect(function(i)
        if drag and i.UserInputType == Enum.UserInputType.MouseMovement then fromMouse() end
    end)
    UIS.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 and drag then
            drag = false
            saveConfig()
        end
    end)
    return f
end

local function Dropdown(parent, text, options, cb)
    local f = make("Frame", { Size = UDim2.new(1, 0, 0, 27), BackgroundColor3 = Theme.Panel, Parent = parent })
    corner(f, 6)
    stroke(f)
    make("TextLabel", { Size = UDim2.new(0.4, 0, 1, 0), Position = UDim2.new(0, 9, 0, 0),
        BackgroundTransparency = 1, Font = Enum.Font.Gotham, TextSize = 12, TextColor3 = Theme.Sub,
        TextXAlignment = Enum.TextXAlignment.Left, Text = text, Parent = f })
    local val = make("TextButton", { Size = UDim2.new(0.58, -13, 1, -5), Position = UDim2.new(0.41, 0, 0, 2.5),
        BackgroundColor3 = Theme.Panel2, Font = Enum.Font.GothamMedium, TextSize = 12,
        TextColor3 = Theme.Text, Text = "", Parent = f })
    corner(val, 5)
    local holder = make("ScrollingFrame", { Size = UDim2.new(1, 0, 0, 100), Position = UDim2.new(0, 0, 0, 29),
        BackgroundColor3 = Theme.BG, BorderSizePixel = 0, ScrollBarThickness = 3,
        ScrollBarImageColor3 = Theme.Stroke, CanvasSize = UDim2.new(0, 0, 0, 0),
        Visible = false, Parent = f })
    corner(holder, 6)
    stroke(holder)
    padding(holder, 3)
    vlist(holder, 1)

    local opts = options
    local idx = 1
    local listH = 100
    local open = false

    local function render() val.Text = tostring(opts[idx] or "-") end
    local function close()
        open = false
        holder.Visible = false
        f.Size = UDim2.new(1, 0, 0, 27)
    end
    local function openList()
        open = true
        holder.Visible = true
        f.Size = UDim2.new(1, 0, 0, 29 + listH)
    end
    local function buildRows()
        for _, c in ipairs(holder:GetChildren()) do
            if c:IsA("TextButton") then c:Destroy() end
        end
        local n = math.max(#opts, 1)
        listH = math.min(n * 20 + 6, 150)
        holder.CanvasSize = UDim2.new(0, 0, 0, n * 20 + 6)
        holder.Size = UDim2.new(1, 0, 0, listH)
        f.Size = UDim2.new(1, 0, 0, open and (29 + listH) or 27)
        for i = 1, #opts do
            local opt = opts[i]
            local ob = make("TextButton", { Size = UDim2.new(1, 0, 0, 19), BackgroundColor3 = Theme.BG,
                Text = "  " .. tostring(opt), Font = Enum.Font.Gotham, TextSize = 11,
                TextColor3 = Theme.Text, TextXAlignment = Enum.TextXAlignment.Left, Parent = holder })
            corner(ob, 4)
            ob.MouseEnter:Connect(function() ob.BackgroundColor3 = Theme.Panel2 end)
            ob.MouseLeave:Connect(function() ob.BackgroundColor3 = Theme.BG end)
            ob.MouseButton1Click:Connect(function()
                idx = i
                render()
                close()
                if cb then pcall(cb, opt, i) end
                saveConfig()
            end)
        end
    end

    val.MouseButton1Click:Connect(function()
        if open then close() else openList() end
    end)

    buildRows()
    render()

    return f, function() return opts[idx] end, function() return idx end, function(newOpts)
        opts = (#newOpts > 0) and newOpts or { "-" }
        idx = 1
        buildRows()
        render()
        close()
    end
end

local function Textbox(parent, placeholder, cb)
    local t = make("TextBox", { Size = UDim2.new(1, 0, 0, 26), BackgroundColor3 = Theme.Panel2,
        Text = "", PlaceholderText = placeholder, Font = Enum.Font.Gotham, TextSize = 12,
        TextColor3 = Theme.Text, PlaceholderColor3 = Theme.Sub, Parent = parent })
    corner(t, 6)
    stroke(t)
    if cb then t.FocusLost:Connect(function() pcall(cb, t.Text) end) end
    return t
end

--=====================================================================
--  WAYPOINTS
--=====================================================================
local waypoints = {}
if readfile and isfile then
    pcall(function()
        if isfile(WP_FILE) then
            for _, w in ipairs(Http:JSONDecode(readfile(WP_FILE))) do
                waypoints[#waypoints + 1] = { name = tostring(w.name),
                    pos = Vector3.new(tonumber(w.x) or 0, tonumber(w.y) or 0, tonumber(w.z) or 0) }
            end
        end
    end)
end
local function saveWaypoints()
    if not writefile then return end
    pcall(function()
        if isfolder and not isfolder(CONFIG_DIR) then makefolder(CONFIG_DIR) end
        local out = {}
        for i = 1, #waypoints do
            local w = waypoints[i]
            out[#out + 1] = { name = w.name, x = w.pos.X, y = w.pos.Y, z = w.pos.Z }
        end
        writefile(WP_FILE, Http:JSONEncode(out))
    end)
end

--=====================================================================
--  PAGES
--=====================================================================
local pFarm = newTab("Farm")
Section(pFarm, "Auto Level Farm")
local setFarmT, setNearestT, setBossT

local _, _, _, setQuestOptions = Dropdown(pFarm, "Quest", { "Auto (by level)" }, function(_, i)
    S.QuestIndex = i - 1
    curKey = nil
end)
setFarmT = select(2, Toggle(pFarm, "Auto Level Farm (quest)", S.AutoFarm, function(v)
    S.AutoFarm = v
    if v then
        S.FarmNearest = false
        S.BossFarm = false
        if setNearestT then setNearestT(false) end
        if setBossT then setBossT(false) end
        resetFarmState()
        farmGen = farmGen + 1
        runFarm()
    else
        resetFarmState()
    end
end))
setNearestT = select(2, Toggle(pFarm, "Farm Nearest (any mob)", S.FarmNearest, function(v)
    S.FarmNearest = v
    if v then
        S.AutoFarm = false
        S.BossFarm = false
        if setFarmT then setFarmT(false) end
        if setBossT then setBossT(false) end
        resetFarmState()
    end
end))

Section(pFarm, "Hover Setup  (mobs pinned under you)")
Slider(pFarm, "Hover Height", 5, 80, S.HoverHeight, function(v) S.HoverHeight = v end)
Slider(pFarm, "Engage Range  (fly when farther)", 10, 300, S.EngageRange, function(v) S.EngageRange = v end)
Slider(pFarm, "Magnet Range", 50, 1000, S.MagnetRange, function(v) S.MagnetRange = v end)
Toggle(pFarm, "Bring Mob (pin stack under you)", S.BringMob, function(v) S.BringMob = v end)
Toggle(pFarm, "Freeze Mobs", S.FreezeMobs, function(v) S.FreezeMobs = v end)
Toggle(pFarm, "Big Hitbox (60x60 mob HRP)", S.BigHitbox, function(v) S.BigHitbox = v end)

Section(pFarm, "Attack")
Dropdown(pFarm, "Attack Method", { "Native", "Mouse", "Remote", "Native + Remote" },
    function(v) S.AttackMethod = v end)
Slider(pFarm, "Hitbox Magnitude  (reach)", 40, 300, S.Hitbox, function(v) S.Hitbox = v end)
Slider(pFarm, "Attack Interval", 0.02, 1, S.AttackInterval, function(v) S.AttackInterval = v end)
Toggle(pFarm, "Fast Attack", S.FastAttack, function(v) S.FastAttack = v end)
Toggle(pFarm, "Auto Equip", S.AutoEquip, function(v) S.AutoEquip = v end)
Dropdown(pFarm, "Equip Type", { "Melee", "Sword", "Gun", "Fruit" }, function(v) S.EquipType = v end)

Section(pFarm, "Boss")
local _, _, _, setBossOptions = Dropdown(pFarm, "Boss", { "-" }, function(_, i) S.BossIndex = i end)
setBossT = select(2, Toggle(pFarm, "Farm Boss", S.BossFarm, function(v)
    S.BossFarm = v
    if v then
        S.AutoFarm = false
        S.FarmNearest = false
        if setFarmT then setFarmT(false) end
        if setNearestT then setNearestT(false) end
        resetFarmState()
    end
end))
Toggle(pFarm, "Auto Saber (Saber Expert)", S.AutoSaber, function(v)
    S.AutoSaber = v
    if not v then return end
    local list = BOSSES[sea()] or BOSSES[1]
    for i = 1, #list do
        if list[i][1] == "Saber Expert" then S.BossIndex = i break end
    end
    if setBossT then setBossT(true) end
end)

Section(pFarm, "Materials")
local _, _, _, setMatOptions = Dropdown(pFarm, "Material", { "-" }, function(_, i) S.MaterialIndex = i end)
Toggle(pFarm, "Material Farm", S.MaterialFarm, function(v)
    S.MaterialFarm = v
    if not v then return end
    local mats = MATERIALS[sea()]
    if not mats then notify("No materials in Sea " .. sea()) return end
    local m = mats[math.clamp(S.MaterialIndex, 1, #mats)]
    if not m then return end
    local found = false
    local list = questList()
    for i = 1, #list do
        if list[i].mob == m[2] then S.QuestIndex = i found = true break end
    end
    if found then
        curKey = nil
        if setFarmT then setFarmT(true) end
        notify("Material farm: " .. m[1])
    else
        notify("Source mob not in this sea's quest list")
    end
end)

Section(pFarm, "Auto Stats")
Dropdown(pFarm, "Stat", { "Melee", "Defense", "Sword", "Gun", "Blox Fruit", "Demon Fruit" },
    function(v) S.Stat = v end)
Slider(pFarm, "Points per add", 1, 100, S.StatAmount, function(v) S.StatAmount = v end)
Toggle(pFarm, "Auto Add Points", S.AutoPoints, function(v) S.AutoPoints = v end)

Section(pFarm, "Collect  (pauses while farming)")
Toggle(pFarm, "Auto Chest Farm", S.AutoChest, function(v) S.AutoChest = v end)
Toggle(pFarm, "Auto Collect Loot", S.AutoLoot, function(v) S.AutoLoot = v end)
Slider(pFarm, "Loot Range", 100, 2500, S.LootRange, function(v) S.LootRange = v end)
Slider(pFarm, "Collect Speed", 100, 1000, S.CollectSpeed, function(v) S.CollectSpeed = v end)

local pPvp = newTab("PVP")
Section(pPvp, "Combat")
Toggle(pPvp, "Attack Players", S.AttackPlayers, function(v) S.AttackPlayers = v end)
Slider(pPvp, "Player Range", 10, 300, S.PlayerRange, function(v) S.PlayerRange = v end)
Section(pPvp, "Kill Aura")
Toggle(pPvp, "Kill Aura", S.KillAura, function(v) S.KillAura = v end)
Slider(pPvp, "Aura Range", 10, 400, S.AuraRange, function(v) S.AuraRange = v end)
Toggle(pPvp, "Line of Sight", S.LOS, function(v) S.LOS = v end)
Section(pPvp, "Auto Skills")
Toggle(pPvp, "Auto Skills", S.AutoSkills, function(v) S.AutoSkills = v end)
Toggle(pPvp, "Key Z", S.KeyZ, function(v) S.KeyZ = v end)
Toggle(pPvp, "Key X", S.KeyX, function(v) S.KeyX = v end)
Toggle(pPvp, "Key C", S.KeyC, function(v) S.KeyC = v end)
Toggle(pPvp, "Key V", S.KeyV, function(v) S.KeyV = v end)
Toggle(pPvp, "Key F", S.KeyF, function(v) S.KeyF = v end)
Slider(pPvp, "Skill Interval (ms)", 100, 1000, S.SkillInterval, function(v) S.SkillInterval = v end)
Section(pPvp, "Players")
Toggle(pPvp, "Aimbot", S.Aimbot, function(v) S.Aimbot = v end)
Slider(pPvp, "Aim Smoothness", 3, 100, S.AimSmooth, function(v) S.AimSmooth = v end)
Toggle(pPvp, "Follow Nearest", S.Follow, function(v) S.Follow = v end)
Toggle(pPvp, "1v1 (attack followed)", S.Duel1v1, function(v) S.Duel1v1 = v end)
Toggle(pPvp, "Spectate Nearest", S.Spectate, function(v) S.Spectate = v end)
Button(pPvp, "Show Captured hitId", function()
    notify(Net.hitId and ("hitId: " .. tostring(Net.hitId)) or "No hitId yet - land one manual M1")
end)
Section(pPvp, "Auto Bounty")
Toggle(pPvp, "Auto Bounty", S.AutoBounty, function(v) S.AutoBounty = v end)
Dropdown(pPvp, "Target Team", { "Both", "Pirates", "Marines" }, function(v) S.BountyTeam = v end)
Dropdown(pPvp, "Method", { "Nearest", "Lowest HP" }, function(v) S.BountyMethod = v end)
Toggle(pPvp, "Skip Friends", S.NoFriends, function(v) S.NoFriends = v end)
Toggle(pPvp, "Skip Cup Holders", S.NoCup, function(v) S.NoCup = v end)
Toggle(pPvp, "No Stun", S.NoStun, function(v) S.NoStun = v end)
Slider(pPvp, "Retreat below HP %", 0, 100, S.SafeHP, function(v) S.SafeHP = v end)

local pTp = newTab("Teleport")
Section(pTp, "Islands")
local _, _, _, setIslandOptions = Dropdown(pTp, "Island", { "-" }, function(_, i) S.IslandIndex = i end)
Button(pTp, "Go to Island", function()
    local list = ISLANDS[sea()] or ISLANDS[1]
    local e = list[math.clamp(S.IslandIndex, 1, #list)]
    if e then
        tpGo(e[2] + Vector3.new(0, 5, 0))
        notify("Flying to " .. e[1])
    end
end)
Section(pTp, "Bosses")
local _, _, _, setBossTPOptions = Dropdown(pTp, "Boss", { "-" }, function(_, i) S.BossTPIndex = i end)
Button(pTp, "Go to Boss", function()
    local list = BOSSES[sea()] or BOSSES[1]
    local e = list[math.clamp(S.BossTPIndex, 1, #list)]
    if e then
        tpGo(e[3] + Vector3.new(0, 5, 0))
        notify("Flying to " .. e[1])
    end
end)
Section(pTp, "Seas")
Button(pTp, "Sail to Second Sea", function() invoke("TravelDressrosa") notify("Sailing to Sea 2") end)
Button(pTp, "Sail to Third Sea", function() invoke("TravelZou") notify("Sailing to Sea 3") end)
Button(pTp, "Set Spawn Here", function() invoke("SetSpawnPoint") notify("Spawn point set") end)
Button(pTp, "Notify My Position", function()
    local h = hrp()
    if not h then return end
    local p = h.Position
    local s = ("%.1f, %.1f, %.1f"):format(p.X, p.Y, p.Z)
    notify(s)
    if setclipboard then setclipboard(s) end
end)
Section(pTp, "Waypoints")
local wpName = Textbox(pTp, "Waypoint name...")
local wpHolder = make("Frame", { Size = UDim2.new(1, 0, 0, 0), BackgroundTransparency = 1, Parent = pTp })
vlist(wpHolder, 4)
local function refreshWaypoints()
    for _, c in ipairs(wpHolder:GetChildren()) do
        if c:IsA("TextButton") then c:Destroy() end
    end
    wpHolder.Size = UDim2.new(1, 0, 0, #waypoints * 29)
    for i = 1, #waypoints do
        local w = waypoints[i]
        local b = Button(wpHolder, "Go: " .. w.name, function() tpGo(w.pos) end)
        b.MouseButton2Click:Connect(function()
            table.remove(waypoints, i)
            saveWaypoints()
            refreshWaypoints()
            notify("Deleted " .. w.name)
        end)
    end
end
Button(pTp, "Save Current Position", function()
    local h = hrp()
    if not h then return end
    local name = (wpName.Text ~= "" and wpName.Text) or ("WP " .. (#waypoints + 1))
    waypoints[#waypoints + 1] = { name = name, pos = h.Position }
    wpName.Text = ""
    saveWaypoints()
    refreshWaypoints()
    notify("Saved waypoint: " .. name)
end)
Button(pTp, "Clear All Waypoints", function()
    waypoints = {}
    saveWaypoints()
    refreshWaypoints()
end)
Section(pTp, "Server")
Button(pTp, "Rejoin Server", function() TeleportSvc:Teleport(game.PlaceId, LP) end)
Button(pTp, "Server Hop", function()
    local ok, body = pcall(function()
        return game:HttpGet("https://games.roblox.com/v1/games/" .. game.PlaceId .. "/servers/Public?limit=100")
    end)
    if not ok then notify("Hop failed") return end
    local data
    pcall(function() data = Http:JSONDecode(body) end)
    if not (data and data.data) then notify("Bad response") return end
    local pool = {}
    for _, s in ipairs(data.data) do
        if s.id ~= game.JobId and s.playing < s.maxPlayers then pool[#pool + 1] = s.id end
    end
    if #pool == 0 then notify("No open servers") return end
    notify("Hopping...")
    task.wait(0.3)
    TeleportSvc:TeleportToPlaceInstance(game.PlaceId, pool[math.random(#pool)], LP)
end)
Button(pTp, "Copy Job ID", function()
    if setclipboard then setclipboard(game.JobId) notify("Job ID copied") end
end)

local pPlayer = newTab("Player")
Section(pPlayer, "Stats")
Slider(pPlayer, "Walk Speed", 16, 600, S.Speed, function(v) S.Speed = v applyStats() end)
Slider(pPlayer, "Jump Power", 50, 600, S.Jump, function(v) S.Jump = v applyStats() end)
Toggle(pPlayer, "Infinite Energy", S.InfEnergy, function(v) S.InfEnergy = v end)
Section(pPlayer, "Movement")
Toggle(pPlayer, "Noclip", S.Noclip, function(v) S.Noclip = v end)
Toggle(pPlayer, "Fly (WASD / Space / LShift)", S.Fly, function(v)
    S.Fly = v
    if not v then stopFly() end
end)
Slider(pPlayer, "Fly / Teleport Speed", 50, 1000, S.FlySpeed, function(v) S.FlySpeed = v end)
Section(pPlayer, "Haki")
Toggle(pPlayer, "Auto Buso Haki", S.AutoBuso, function(v) S.AutoBuso = v end)
Toggle(pPlayer, "Auto Ken Haki", S.AutoKen, function(v) S.AutoKen = v end)
Section(pPlayer, "Misc")
Toggle(pPlayer, "Anti-AFK", S.AntiAFK, function(v) S.AntiAFK = v end)
Button(pPlayer, "Reset Character", function()
    local h = hum()
    if h then h.Health = 0 end
end)

local pFruit = newTab("Fruits")
Section(pFruit, "Devil Fruits")
Toggle(pFruit, "Fruit ESP", S.ESPFruits, function(v) S.ESPFruits = v end, "fruitesp")
Toggle(pFruit, "Auto Collect Fruit", S.AutoFruit, function(v) S.AutoFruit = v end)
Button(pFruit, "Teleport to Nearest Fruit", function()
    local f = getGroundFruits()
    if #f == 0 then notify("No fruit on the ground") return end
    table.sort(f, function(a, b) return a.d < b.d end)
    tpGo(f[1].part.Position + Vector3.new(0, 3, 0), S.CollectSpeed)
    notify("Flying to " .. f[1].name)
end)
Section(pFruit, "Shop  (stand near the NPC)")
local shop = {
    { "Buy Busoshoku Haki", "BuyHaki", "Buso" },
    { "Buy Kenbunshoku Haki", "BuyHaki", "Ken" },
    { "Buy Geppo", "BuyHaki", "Geppo" },
    { "Buy Soru", "BuyHaki", "Soru" },
    { "Buy Black Leg", "BuyBlackLeg" },
    { "Buy Electro", "BuyElectro" },
    { "Buy Fishman Karate", "BuyFishmanKarate" },
    { "Buy Superhuman", "BuySuperhuman" },
    { "Buy Death Step", "BuyDeathStep" },
    { "Buy Sharkman Karate", "BuySharkmanKarate" },
    { "Buy Electric Claw", "BuyElectricClaw" },
    { "Buy Dragon Talon", "BuyDragonTalon" },
}
for i = 1, #shop do
    local s = shop[i]
    Button(pFruit, s[1], function()
        if s[3] then invoke(s[2], s[3]) else invoke(s[2]) end
        notify(s[1])
    end)
end
Button(pFruit, "Dragon Claw (Blackbeard)", function()
    invoke("BlackbeardReward", "DragonClaw", "1")
    invoke("BlackbeardReward", "DragonClaw", "2")
    notify("Dragon Claw requested")
end)

local pVis = newTab("Visuals")
Section(pVis, "ESP")
Toggle(pVis, "Mobs", S.ESPMobs, function(v) S.ESPMobs = v end)
Toggle(pVis, "Players", S.ESPPlayers, function(v) S.ESPPlayers = v end)
Toggle(pVis, "Chests / Barrels", S.ESPChests, function(v) S.ESPChests = v end)
Toggle(pVis, "Fruits", S.ESPFruits, function(v) S.ESPFruits = v end, "fruitesp")
Section(pVis, "World")
Toggle(pVis, "Fullbright", S.Fullbright, function(v)
    S.Fullbright = v
    Lighting.Brightness = v and 4 or 2
    Lighting.Ambient = v and Color3.fromRGB(190, 190, 190) or Color3.fromRGB(70, 70, 70)
    Lighting.OutdoorAmbient = v and Color3.fromRGB(190, 190, 190) or Color3.fromRGB(70, 70, 70)
    Lighting.GlobalShadows = not v
end)

local pMisc = newTab("Misc")
Section(pMisc, "Debug")
Button(pMisc, "Run Diagnostics (prints + copies)", function()
    local RA, RH = netModules()
    local l = {
        "Sea: " .. sea(),
        "Level: " .. level(),
        "Ping: " .. ping() .. "ms",
        "CombatFramework: " .. tostring(CombatFramework ~= nil),
        "activeController: " .. tostring(CombatFramework and CombatFramework.activeController ~= nil),
        "Attack method: " .. S.AttackMethod .. " | hitbox " .. S.Hitbox,
        "Enemies folder: " .. tostring(enemies()),
        "Enemy count: " .. tostring(enemies() and #enemies():GetChildren()),
        "_WorldOrigin.Locations: " .. tostring(locations()),
        "CommF_: " .. tostring(CommF_),
        "RegisterAttack: " .. tostring(RA),
        "RegisterHit: " .. tostring(RH),
        "hitId: " .. tostring(Net.hitId),
        "hookmetamethod: " .. tostring(hookmetamethod ~= nil),
    }
    local s = table.concat(l, "\n")
    print("[VeniceHub DIAG]\n" .. s)
    if setclipboard then setclipboard(s) notify("Diagnostics copied") end
end)
Button(pMisc, "Test Attack (nearest mob)", function()
    local t = nearestAnyMob(500)
    if not t then notify("No mob within 500 studs") return end
    target = t
    doAttack(t)
    notify("Attacked " .. t.Name .. " via " .. S.AttackMethod)
end)
Button(pMisc, "Force hitId Re-capture", function()
    Net.hooked = false
    Net.fallbackTried = false
    if installHitCapture() then notify("Capture reinstalled") else notify("Modules.Net not ready") end
end)
Section(pMisc, "Config")
Button(pMisc, "Save Settings", function() saveConfig() notify("Settings saved") end)
Button(pMisc, "Reset to Defaults", function()
    resetConfig()
    notify("Defaults restored (re-toggle to apply)")
end)
Section(pMisc, "Info")
Button(pMisc, "Toggle UI (RightControl)", function() Main.Visible = not Main.Visible end)
Button(pMisc, "Unload Hub (RightShift)", function()
    for k, v in pairs(S) do if type(v) == "boolean" then S[k] = false end end
    stopFly()
    tpCancel()
    pcall(function() Gui:Destroy() end)
    if getgenv then getgenv().VeniceHub = nil end
    notify("Unloaded")
end)

--=====================================================================
--  SEA WATCHER
--=====================================================================
local function rebuildForSea(s)
    local ql = { "Auto (by level)" }
    local src = QUESTS[s] or QUESTS[1]
    for i = 1, #src do ql[#ql + 1] = src[i].mob .. " (Lv " .. src[i].lvl .. ")" end
    setQuestOptions(ql)
    S.QuestIndex = 0

    local il = {}
    local isl = ISLANDS[s] or ISLANDS[1]
    for i = 1, #isl do il[#il + 1] = isl[i][1] end
    setIslandOptions(il)
    S.IslandIndex = 1

    local bl = {}
    local bs = BOSSES[s] or BOSSES[1]
    for i = 1, #bs do bl[#bl + 1] = bs[i][1] .. " (Lv " .. bs[i][2] .. ")" end
    setBossOptions(bl)
    setBossTPOptions(bl)
    S.BossIndex = 1
    S.BossTPIndex = 1

    local ml = {}
    local ms = MATERIALS[s]
    if ms then
        for i = 1, #ms do ml[#ml + 1] = ms[i][1] .. "  (" .. ms[i][2] .. ")" end
    else
        ml = { "none in this sea" }
    end
    setMatOptions(ml)
    S.MaterialIndex = 1

    resetFarmState()
    log("lists rebuilt for Sea " .. s)
end

rebuildForSea(sea())
refreshWaypoints()

task.spawn(function()
    local last = sea()
    while Gui.Parent do
        task.wait(2)
        local s = sea()
        if s ~= last then
            last = s
            rebuildForSea(s)
            notify("Sea change detected - rebuilt for Sea " .. s)
        end
    end
end)

if tabs[1] then
    tabs[1].page.Visible = true
    tabs[1].btn.BackgroundColor3 = Theme.Accent
    tabs[1].btn.TextColor3 = Theme.Text
end

--=====================================================================
--  DRAG · HOTKEYS · STATUS
--=====================================================================
local dragging, dragStart, startPos
Bar.InputBegan:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
        dragging, dragStart, startPos = true, i.Position, Main.Position
    end
end)
UIS.InputChanged:Connect(function(i)
    if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
        local d = i.Position - dragStart
        Main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X,
            startPos.Y.Scale, startPos.Y.Offset + d.Y)
    end
end)
UIS.InputEnded:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
        dragging = false
    end
end)
UIS.InputBegan:Connect(function(i, gp)
    if gp then return end
    if i.KeyCode == Enum.KeyCode.RightControl then
        Main.Visible = not Main.Visible
    elseif i.KeyCode == Enum.KeyCode.RightShift then
        for k, v in pairs(S) do if type(v) == "boolean" then S[k] = false end end
        stopFly()
        tpCancel()
        pcall(function() Gui:Destroy() end)
        if getgenv then getgenv().VeniceHub = nil end
    end
end)

task.spawn(function()
    while Gui.Parent do
        task.wait(0.8)
        local bits = {}
        local watch = { "AutoFarm", "FarmNearest", "BossFarm", "KillAura", "AutoChest",
                        "AutoLoot", "AutoFruit", "AutoBounty", "Fly", "AutoSkills", "FastAttack" }
        for i = 1, #watch do
            if S[watch[i]] then bits[#bits + 1] = watch[i] end
        end
        local q = currentQuest()
        local cnt = 0
        local f = enemies()
        if f then cnt = #f:GetChildren() end
        local pinned = 0
        if pinPos and bestQ then
            local list = mobsNamed(bestQ.mob)
            for i = 1, #list do
                local ep = list[i]:FindFirstChild("HumanoidRootPart")
                if ep and (ep.Position - pinPos).Magnitude < S.MagnetRange then pinned = pinned + 1 end
            end
        end
        Status.Text = (#bits > 0 and table.concat(bits, " · ") or "idle")
            .. "  |  Sea " .. sea() .. "  Lv " .. level()
            .. "  |  quest: " .. (q and q.mob or "-")
            .. "  |  pinned: " .. pinned
            .. "  |  hitbox: " .. S.Hitbox
            .. "  |  hitId: " .. tostring(Net.hitId and "ok" or "none")
    end
end)

if getgenv then getgenv().VeniceHub = { Gui = Gui, Config = S } end
loadCombat()
installHitCapture()
applyStats()
notify("Venice Hub v6 loaded  ·  RightControl to toggle", "Blox Fruits")
