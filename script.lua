--[[=====================================================================
  VENICE HUB  ·  BLOX FRUITS
  Executor: Xeno (standard UNC functions only)
  Toggle UI: RightControl    |    Unload: RightShift
  Save file: VeniceHub/bloxfruits.json
=====================================================================]]

local Players     = game:GetService("Players")
local RS          = game:GetService("ReplicatedStorage")
local RunService  = game:GetService("RunService")
local UIS         = game:GetService("UserInputService")
local Tween       = game:GetService("TweenService")
local StarterGui  = game:GetService("StarterGui")
local VirtualUser = game:GetService("VirtualUser")
local Http        = game:GetService("HttpService")
local Lighting    = game:GetService("Lighting")
local TeleportSvc = game:GetService("TeleportService")

local LP        = Players.LocalPlayer
local PLACE_ID  = 2753915549
local SKILL_KEYS = { 0x5A, 0x58, 0x43, 0x56 }   -- Z X C V
local HAKI_KEY   = 0x4A                          -- J

-- kill any previous instance of this hub
if getgenv().VeniceHub and getgenv().VeniceHub.Gui then
    pcall(function() getgenv().VeniceHub.Gui:Destroy() end)
end

local Remotes = RS:FindFirstChild("Remotes") or RS:WaitForChild("Remotes", 30)
local CommF_  = Remotes and (Remotes:FindFirstChild("CommF_") or Remotes:WaitForChild("CommF_", 30))

local function invoke(...)
    if not CommF_ then return nil end
    local ok, res = pcall(function() return CommF_:InvokeServer(...) end)
    if ok then return res end
end

--=====================================================================
--  CONFIG
--=====================================================================
local CONFIG_DIR  = "VeniceHub"
local CONFIG_FILE = CONFIG_DIR .. "/bloxfruits.json"

local S = {
    -- farming
    AutoFarm = false, BringMobs = false, FarmRange = 300, StandOff = 10,
    BossPriority = false, AutoEquip = true, UseFruitM1 = false,
    FastAttack = false, AutoSkills = false, SkillDelay = 2,
    AutoHaki = false, HakiDelay = 6, Hitbox = 120,
    -- chests / loot
    AutoChest = false, ChestDwell = 0.12,
    AutoLoot = false, LootRange = 600,
    -- fruits
    FruitESP = false, AutoFruit = false, FruitDwell = 0.15,
    -- stats
    Speed = 16, Jump = 50, InfEnergy = false,
    -- movement
    Noclip = false, Fly = false, FlySpeed = 60,
    -- visuals
    ESPMobs = false, ESPPlayers = false, ESPChests = false, Fullbright = false,
    -- misc
    AntiAFK = true, AutoStats = false, StatType = "Melee",
    ServerTP = true,
}

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
        local data = Http:JSONDecode(readfile(CONFIG_FILE))
        for k, v in pairs(data) do
            if S[k] ~= nil then S[k] = v end
        end
    end)
end
loadConfig()

--=====================================================================
--  SMALL HELPERS
--=====================================================================
local function notify(text, title)
    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = title or "Venice Hub", Text = tostring(text), Duration = 4 })
    end)
end

local function root() local c = LP.Character; return c and c:FindFirstChild("HumanoidRootPart") end
local function hum()  local c = LP.Character; return c and c:FindFirstChildOfClass("Humanoid") end

local function tpTo(v3)
    local r = root()
    if r and v3 then r.CFrame = CFrame.new(v3) end
end

local function tapKey(code)
    if keypress and keyrelease then
        pcall(function()
            keypress(code)
            task.wait(0.02)
            keyrelease(code)
        end)
    end
end

--=====================================================================
--  GAME READING
--=====================================================================
local function enemiesFolder() return workspace:FindFirstChild("Enemies") end
local function locations()
    local wo = workspace:FindFirstChild("_WorldOrigin")
    return wo and wo:FindFirstChild("Locations")
end

local function getEnemies(range)
    local out, f, p = {}, enemiesFolder(), root()
    if not f then return out end
    for _, m in ipairs(f:GetChildren()) do
        local h = m:FindFirstChildOfClass("Humanoid")
        local r = m:FindFirstChild("HumanoidRootPart")
        if h and r and h.Health > 0 then
            local d = p and (r.Position - p.Position).Magnitude or 0
            if not range or d <= range then
                out[#out + 1] = { model = m, root = r, hum = h, dist = d, name = m.Name }
            end
        end
    end
    return out
end

local function getTarget(range)
    local list = getEnemies(range)
    if #list == 0 then return nil end
    local pool = list
    if S.BossPriority then
        local bosses = {}
        for _, e in ipairs(list) do
            if not e.name:find("%[Lv") then bosses[#bosses + 1] = e end
        end
        if #bosses > 0 then pool = bosses end
    end
    table.sort(pool, function(a, b) return a.dist < b.dist end)
    return pool[1]
end

local function getChests(range)
    local out, loc, p = {}, locations(), root()
    if not loc then return out end
    for _, v in ipairs(loc:GetChildren()) do
        if v:IsA("BasePart") then
            local n = v.Name:lower()
            if n:find("chest") or n:find("barrel") then
                local d = p and (v.Position - p.Position).Magnitude or 0
                if not range or d <= range then out[#out + 1] = { part = v, dist = d } end
            end
        end
    end
    return out
end

local FRUIT_NAMES = {
    "Rocket","Spin","Chop","Spring","Bomb","Smoke","Spike","Flame","Falcon","Ice","Sand","Dark",
    "Diamond","Light","Rubber","Barrier","Ghost","Magma","Door","Blizzard","Gravity","Mammoth",
    "T-Rex","Dough","Shadow","Venom","Control","Spirit","Dragon","Leopard","Kitsune","Buddha",
    "Portal","Rumble","Paw","Sound","Phoenix","Pain","Love","Creation","Spider","Magnet","Yeti",
    "Gas","Revive","Eagle","Wolf","Quake","Lightning","Gem","Rift",
}
local FRUIT_SET = {}
for _, f in ipairs(FRUIT_NAMES) do
    FRUIT_SET[f] = true
    FRUIT_SET[f .. "-" .. f] = true
end

local function isFruit(inst)
    if not (inst:IsA("Model") or inst:IsA("Tool")) then return false end
    if not inst:FindFirstChild("Handle") then return false end
    local n = inst.Name
    if FRUIT_SET[n] then return true end
    if n:find("%-") and FRUIT_SET[n:gsub("%-.*$", "")] then return true end
    return false
end

local function getFruits(range)
    local out, p = {}, root()
    local function scan(container)
        if not container then return end
        for _, v in ipairs(container:GetChildren()) do
            if isFruit(v) then
                local h = v:FindFirstChild("Handle")
                if h then
                    local d = p and (h.Position - p.Position).Magnitude or 0
                    if not range or d <= range then
                        out[#out + 1] = { model = v, part = h, dist = d, name = v.Name }
                    end
                end
            end
        end
    end
    scan(workspace)
    scan(locations())
    return out
end

local function getLoot(range)
    local out, p = {}, root()
    if not p then return out end
    for _, v in ipairs(workspace:GetChildren()) do
        if (v:IsA("Model") or v:IsA("Tool")) and v:FindFirstChild("Handle") and not isFruit(v) then
            local n = v.Name:lower()
            if not (n:find("chest") or n:find("barrel")) then
                local h = v.Handle
                local d = (h.Position - p.Position).Magnitude
                if d <= (range or 500) then out[#out + 1] = { part = h, dist = d } end
            end
        end
    end
    return out
end

--=====================================================================
--  COMBAT
--=====================================================================
local CombatFramework
pcall(function()
    local ps = LP:WaitForChild("PlayerScripts", 15)
    local cf = ps and ps:WaitForChild("CombatFramework", 15)
    if cf then CombatFramework = require(cf) end
end)

local function attack()
    local ac = CombatFramework and CombatFramework.activeController
    if ac then
        pcall(function()
            ac.timeToNextAttack = 0
            ac.hitboxMagnitude  = S.Hitbox
            ac.increment        = 3
            ac:attack()
        end)
    else
        local c = LP.Character
        local t = c and c:FindFirstChildOfClass("Tool")
        if t then pcall(function() t:Activate() end) end
    end
end

local function equipWeapon()
    local c = LP.Character
    if not c or c:FindFirstChildOfClass("Tool") then return end
    local bp = LP:FindFirstChild("Backpack")
    if not bp then return end
    local pick
    if S.UseFruitM1 then
        for _, t in ipairs(bp:GetChildren()) do
            if t:IsA("Tool") and t.ToolTip == "Blox Fruit" then pick = t break end
        end
    end
    if not pick then
        for _, t in ipairs(bp:GetChildren()) do
            if t:IsA("Tool") and t.ToolTip ~= "Blox Fruit" then pick = t break end
        end
    end
    if pick then
        local h = c:FindFirstChildOfClass("Humanoid")
        if h then pcall(function() h:EquipTool(pick) end) end
    end
end

--=====================================================================
--  MOB MAGNET (tracked list)
--=====================================================================
local tracked = {}
local function refreshTracked()
    table.clear(tracked)
    for _, e in ipairs(getEnemies(S.FarmRange)) do
        if #tracked >= 12 then break end
        tracked[#tracked + 1] = e.model
    end
end

RunService.Heartbeat:Connect(function()
    if not (S.AutoFarm and S.BringMobs) then return end
    local p = root()
    if not p or #tracked == 0 then return end
    for i = 1, #tracked do
        local m = tracked[i]
        if m and m.Parent then
            local r = m:FindFirstChild("HumanoidRootPart")
            local h = m:FindFirstChildOfClass("Humanoid")
            if r and h and h.Health > 0 then
                local a = (i / #tracked) * math.pi * 2
                r.CFrame = p.CFrame * CFrame.new(math.cos(a) * S.StandOff, 0, math.sin(a) * S.StandOff)
                r.AssemblyLinearVelocity = Vector3.zero
            end
        end
    end
end)

--=====================================================================
--  MAIN FARM LOOP
--=====================================================================
task.spawn(function()
    local acc = 0
    while task.wait(0.05) do
        if S.AutoFarm and LP.Character then
            acc = acc + 0.05
            if acc >= 0.4 then acc = 0 refreshTracked() end

            local t = getTarget(S.FarmRange)
            if t then
                if not S.BringMobs then
                    local r = root()
                    if r then
                        r.CFrame = t.root.CFrame * CFrame.new(0, S.StandOff * 0.6, S.StandOff)
                    end
                end
                if S.AutoEquip then equipWeapon() end
                attack()
                if not S.FastAttack then task.wait(0.08) end
            end
        end
    end
end)

-- fast attack (spam with zero cooldown)
task.spawn(function()
    while task.wait(0.01) do
        if S.FastAttack and S.AutoFarm and LP.Character then attack() end
    end
end)

-- skills
task.spawn(function()
    while true do
        task.wait(S.SkillDelay)
        if S.AutoSkills and S.AutoFarm and LP.Character then
            for _, k in ipairs(SKILL_KEYS) do
                tapKey(k)
                task.wait(0.02)
            end
        end
    end
end)

-- haki
task.spawn(function()
    while true do
        task.wait(S.HakiDelay)
        if S.AutoHaki and LP.Character then tapKey(HAKI_KEY) end
    end
end)

--=====================================================================
--  CHESTS / LOOT / FRUITS  (paused while Auto Farm is on)
--=====================================================================
local function touch(part)
    local r = root()
    if not r then return end
    r.CFrame = CFrame.new(part.Position + Vector3.new(0, 4, 0))
    if firetouchinterest then
        pcall(function()
            firetouchinterest(r, part, 0)
            firetouchinterest(r, part, 1)
        end)
    end
end

task.spawn(function()
    while true do
        if S.AutoChest and not S.AutoFarm and LP.Character then
            local list = getChests()
            local p = root()
            if p and #list > 0 then
                table.sort(list, function(a, b) return a.dist < b.dist end)
                for _, c in ipairs(list) do
                    if not (S.AutoChest and not S.AutoFarm) then break end
                    touch(c.part)
                    task.wait(S.ChestDwell)
                end
            else
                task.wait(0.4)
            end
        else
            task.wait(0.3)
        end
    end
end)

task.spawn(function()
    while true do
        if S.AutoLoot and not S.AutoFarm and LP.Character then
            local list = getLoot(S.LootRange)
            local p = root()
            if p and #list > 0 then
                table.sort(list, function(a, b) return a.dist < b.dist end)
                for _, it in ipairs(list) do
                    if not (S.AutoLoot and not S.AutoFarm) then break end
                    touch(it.part)
                    task.wait(0.1)
                end
            else
                task.wait(0.4)
            end
        else
            task.wait(0.3)
        end
    end
end)

task.spawn(function()
    while true do
        if S.AutoFruit and not S.AutoFarm and LP.Character then
            local list = getFruits()
            local p = root()
            if p and #list > 0 then
                table.sort(list, function(a, b) return a.dist < b.dist end)
                local f = list[1]
                if f then
                    touch(f.part)
                    task.wait(S.FruitDwell)
                end
            else
                task.wait(0.4)
            end
        else
            task.wait(0.3)
        end
    end
end)

--=====================================================================
--  ESP
--=====================================================================
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
    while task.wait(0.75) do
        local f = enemiesFolder()
        if f then
            for _, m in ipairs(f:GetChildren()) do
                setESP(m, Color3.fromRGB(255, 85, 85), S.ESPMobs)
            end
        end
        for _, pl in ipairs(Players:GetPlayers()) do
            if pl ~= LP and pl.Character then
                setESP(pl.Character, Color3.fromRGB(85, 160, 255), S.ESPPlayers)
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
        for _, fr in ipairs(getFruits()) do
            setESP(fr.model, Color3.fromRGB(170, 100, 255), S.FruitESP)
        end
    end
end)

--=====================================================================
--  MOVEMENT / STATS
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

-- fly
local flyBV, flyBG
local function startFly()
    local r = root()
    if not r then return end
    local h = hum()
    if h then h.PlatformStand = true end
    flyBV = Instance.new("BodyVelocity")
    flyBV.MaxForce = Vector3.new(9e9, 9e9, 9e9)
    flyBV.P = 1e4
    flyBV.Velocity = Vector3.zero
    flyBV.Parent = r
    flyBG = Instance.new("BodyGyro")
    flyBG.MaxTorque = Vector3.new(9e9, 9e9, 9e9)
    flyBG.P = 1e4
    flyBG.CFrame = r.CFrame
    flyBG.Parent = r
end

local function stopFly()
    if flyBV then flyBV:Destroy() flyBV = nil end
    if flyBG then flyBG:Destroy() flyBG = nil end
    local h = hum()
    if h then h.PlatformStand = false end
end

RunService.RenderStepped:Connect(function()
    if not S.Fly then return end
    local r = root()
    if not r then return end
    if not flyBV or flyBV.Parent ~= r then startFly() end
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
    flyBG.CFrame = CFrame.new(r.Position, r.Position + cam.CFrame.LookVector)
end)

-- infinite energy
task.spawn(function()
    while task.wait(0.4) do
        if S.InfEnergy and LP.Character then
            pcall(function()
                local e = LP:FindFirstChild("Energy")
                if e then e.Value = 1e6 end
                local d = LP:FindFirstChild("Data")
                if d then
                    local de = d:FindFirstChild("Energy")
                    if de then de.Value = 1e6 end
                end
            end)
        end
    end
end)

-- auto stat points
task.spawn(function()
    while task.wait(0.25) do
        if S.AutoStats and LP.Character then
            local d = LP:FindFirstChild("Data")
            local pts = d and d:FindFirstChild("Points")
            if pts and pts.Value and pts.Value >= 1 then
                invoke("AddPoint", S.StatType, math.floor(pts.Value))
            end
        end
    end
end)

-- anti afk
LP.Idled:Connect(function()
    if S.AntiAFK then
        pcall(function()
            VirtualUser:CaptureController()
            VirtualUser:ClickButton2(Vector2.new())
        end)
    end
end)

--=====================================================================
--  GUI LIBRARY
--=====================================================================
local Theme = {
    BG     = Color3.fromRGB(17, 17, 22),
    Panel  = Color3.fromRGB(27, 27, 36),
    Panel2 = Color3.fromRGB(36, 36, 48),
    Stroke = Color3.fromRGB(50, 50, 66),
    Accent = Color3.fromRGB(139, 92, 246),
    Text   = Color3.fromRGB(235, 235, 245),
    Sub    = Color3.fromRGB(150, 150, 172),
}

local function make(class, props)
    local o = Instance.new(class)
    for k, v in pairs(props or {}) do o[k] = v end
    return o
end
local function corner(p, r) return make("UICorner", { CornerRadius = UDim.new(0, r or 6), Parent = p }) end
local function stroke(p, c, t) return make("UIStroke", { Color = c or Theme.Stroke, Thickness = t or 1, Parent = p }) end
local function padding(p, x, y)
    return make("UIPadding", {
        PaddingTop = UDim.new(0, y or x), PaddingBottom = UDim.new(0, y or x),
        PaddingLeft = UDim.new(0, x), PaddingRight = UDim.new(0, x), Parent = p })
end
local function vlist(p, sp)
    return make("UIListLayout", {
        FillDirection = Enum.FillDirection.Vertical, SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, sp or 6), Parent = p })
end

local Gui = make("ScreenGui", {
    Name = "VeniceHub", ResetOnSpawn = false, IgnoreGuiInset = true,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling })
pcall(function() Gui.Parent = (gethui and gethui()) or LP:WaitForChild("PlayerGui") end)
if not Gui.Parent then Gui.Parent = LP:WaitForChild("PlayerGui") end

local Main = make("Frame", {
    Name = "Main", Size = UDim2.new(0, 600, 0, 380), Position = UDim2.new(0.5, -300, 0.5, -190),
    BackgroundColor3 = Theme.BG, BorderSizePixel = 0, Parent = Gui })
corner(Main, 10); stroke(Main)

local Bar = make("Frame", { Size = UDim2.new(1, 0, 0, 34), BackgroundColor3 = Theme.Panel, BorderSizePixel = 0, Parent = Main })
corner(Bar, 10)
make("Frame", { Size = UDim2.new(1, 0, 0, 12), Position = UDim2.new(0, 0, 1, -12), BackgroundColor3 = Theme.Panel, BorderSizePixel = 0, Parent = Bar })
make("TextLabel", {
    Size = UDim2.new(1, -90, 1, 0), Position = UDim2.new(0, 14, 0, 0), BackgroundTransparency = 1,
    Font = Enum.Font.GothamBold, TextSize = 14, TextColor3 = Theme.Text,
    TextXAlignment = Enum.TextXAlignment.Left, Text = "VENICE HUB  ·  BLOX FRUITS", Parent = Bar })

local HideBtn = make("TextButton", {
    Size = UDim2.new(0, 26, 0, 20), Position = UDim2.new(1, -34, 0.5, -10),
    BackgroundColor3 = Theme.Panel2, Text = "–", Font = Enum.Font.GothamBold,
    TextSize = 14, TextColor3 = Theme.Text, Parent = Bar })
corner(HideBtn, 5)

local TabHolder = make("Frame", {
    Size = UDim2.new(0, 138, 1, -42), Position = UDim2.new(0, 8, 0, 38),
    BackgroundTransparency = 1, Parent = Main })
padding(TabHolder, 0); vlist(TabHolder, 6)

local ContentHolder = make("Frame", {
    Size = UDim2.new(1, -160, 1, -44), Position = UDim2.new(0, 152, 0, 40),
    BackgroundTransparency = 1, Parent = Main })

local tabs = {}
local function newTab(name)
    local btn = make("TextButton", {
        Size = UDim2.new(1, 0, 0, 30), BackgroundColor3 = Theme.Panel, Text = "  " .. name,
        Font = Enum.Font.GothamMedium, TextSize = 13, TextColor3 = Theme.Sub,
        TextXAlignment = Enum.TextXAlignment.Left, AutoButtonColor = false, Parent = TabHolder })
    corner(btn, 6)

    local page = make("ScrollingFrame", {
        Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, BorderSizePixel = 0,
        ScrollBarThickness = 3, ScrollBarImageColor3 = Theme.Stroke,
        CanvasSize = UDim2.new(0, 0, 0, 0), Visible = false, Parent = ContentHolder })
    padding(page, 4, 4)
    local lay = vlist(page, 6)
    lay:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        page.CanvasSize = UDim2.new(0, 0, 0, lay.AbsoluteContentSize.Y + 16)
    end)

    tabs[#tabs + 1] = { btn = btn, page = page }
    btn.MouseButton1Click:Connect(function()
        for _, t in ipairs(tabs) do
            t.page.Visible = false
            t.btn.BackgroundColor3 = Theme.Panel
            t.btn.TextColor3 = Theme.Sub
        end
        page.Visible = true
        btn.BackgroundColor3 = Theme.Accent
        btn.TextColor3 = Theme.Text
    end)
    return page
end

local function Section(parent, text)
    return make("TextLabel", {
        Size = UDim2.new(1, 0, 0, 24), BackgroundTransparency = 1, Font = Enum.Font.GothamBold,
        TextSize = 12, TextColor3 = Theme.Accent, TextXAlignment = Enum.TextXAlignment.Left,
        Text = string.upper(text), Parent = parent })
end

local function Toggle(parent, text, default, cb)
    local f = make("Frame", { Size = UDim2.new(1, 0, 0, 30), BackgroundColor3 = Theme.Panel, Parent = parent })
    corner(f, 6); stroke(f)
    make("TextLabel", {
        Size = UDim2.new(1, -56, 1, 0), Position = UDim2.new(0, 10, 0, 0), BackgroundTransparency = 1,
        Font = Enum.Font.Gotham, TextSize = 12, TextColor3 = Theme.Text,
        TextXAlignment = Enum.TextXAlignment.Left, Text = text, Parent = f })
    local track = make("Frame", { Size = UDim2.new(0, 36, 0, 18), Position = UDim2.new(1, -46, 0.5, -9),
        BackgroundColor3 = Theme.Stroke, Parent = f })
    corner(track, 9)
    local knob = make("Frame", { Size = UDim2.new(0, 14, 0, 14), Position = UDim2.new(0, 2, 0.5, -7),
        BackgroundColor3 = Theme.Text, Parent = track })
    corner(knob, 7)
    local state = default and true or false
    local function render()
        Tween:Create(track, TweenInfo.new(0.15), { BackgroundColor3 = state and Theme.Accent or Theme.Stroke }):Play()
        Tween:Create(knob, TweenInfo.new(0.15), {
            Position = state and UDim2.new(1, -16, 0.5, -7) or UDim2.new(0, 2, 0.5, -7) }):Play()
    end
    render()
    local hit = make("TextButton", { Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Text = "", Parent = f })
    hit.MouseButton1Click:Connect(function()
        state = not state
        render()
        if cb then pcall(cb, state) end
        saveConfig()
    end)
    return f
end

local function Button(parent, text, cb)
    local b = make("TextButton", {
        Size = UDim2.new(1, 0, 0, 28), BackgroundColor3 = Theme.Panel2, Text = text,
        Font = Enum.Font.GothamMedium, TextSize = 12, TextColor3 = Theme.Text, Parent = parent })
    corner(b, 6); stroke(b)
    b.MouseButton1Click:Connect(function() task.spawn(cb) end)
    return b
end

local function Slider(parent, text, min, max, default, cb)
    local f = make("Frame", { Size = UDim2.new(1, 0, 0, 42), BackgroundColor3 = Theme.Panel, Parent = parent })
    corner(f, 6); stroke(f)
    make("TextLabel", {
        Size = UDim2.new(0.6, 0, 0, 20), Position = UDim2.new(0, 10, 0, 2), BackgroundTransparency = 1,
        Font = Enum.Font.Gotham, TextSize = 12, TextColor3 = Theme.Text,
        TextXAlignment = Enum.TextXAlignment.Left, Text = text, Parent = f })
    local vLbl = make("TextLabel", {
        Size = UDim2.new(0.35, -10, 0, 20), Position = UDim2.new(0.65, 0, 0, 2), BackgroundTransparency = 1,
        Font = Enum.Font.GothamMedium, TextSize = 12, TextColor3 = Theme.Accent,
        TextXAlignment = Enum.TextXAlignment.Right, Text = "", Parent = f })
    local bar = make("Frame", { Size = UDim2.new(1, -20, 0, 6), Position = UDim2.new(0, 10, 1, -16),
        BackgroundColor3 = Theme.Stroke, BorderSizePixel = 0, Parent = f })
    corner(bar, 3)
    local fill = make("Frame", { Size = UDim2.new(0, 0, 1, 0), BackgroundColor3 = Theme.Accent, BorderSizePixel = 0, Parent = bar })
    corner(fill, 3)

    local val = default
    local function set(v, fire)
        v = math.clamp(v, min, max)
        val = v
        fill.Size = UDim2.new((v - min) / (max - min), 0, 1, 0)
        vLbl.Text = tostring(math.floor(v * 100) / 100)
        if fire and cb then pcall(cb, v) end
    end
    set(default, false)

    local hit = make("TextButton", { Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Text = "", Parent = f })
    local dragging = false
    local function fromMouse()
        local mx = UIS:GetMouseLocation().X
        local rel = math.clamp((mx - bar.AbsolutePosition.X) / math.max(bar.AbsoluteSize.X, 1), 0, 1)
        set(min + rel * (max - min), true)
    end
    hit.MouseButton1Down:Connect(function() dragging = true fromMouse() end)
    UIS.InputChanged:Connect(function(i)
        if dragging and i.UserInputType == Enum.UserInputType.MouseMovement then fromMouse() end
    end)
    UIS.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 and dragging then
            dragging = false
            saveConfig()
        end
    end)
    return f
end

local function Cycle(parent, text, options, defaultIndex, cb)
    local f = make("Frame", { Size = UDim2.new(1, 0, 0, 30), BackgroundColor3 = Theme.Panel, Parent = parent })
    corner(f, 6); stroke(f)
    make("TextLabel", {
        Size = UDim2.new(0.42, 0, 1, 0), Position = UDim2.new(0, 10, 0, 0), BackgroundTransparency = 1,
        Font = Enum.Font.Gotham, TextSize = 12, TextColor3 = Theme.Sub,
        TextXAlignment = Enum.TextXAlignment.Left, Text = text, Parent = f })
    local val = make("TextButton", {
        Size = UDim2.new(0.56, -14, 1, -6), Position = UDim2.new(0.43, 0, 0, 3),
        BackgroundColor3 = Theme.Panel2, Font = Enum.Font.GothamMedium, TextSize = 12,
        TextColor3 = Theme.Text, Text = "", Parent = f })
    corner(val, 5)
    if #options == 0 then options = { "none" } end
    local idx = math.clamp(defaultIndex or 1, 1, #options)
    local function render() val.Text = tostring(options[idx]) end
    render()
    val.MouseButton1Click:Connect(function()
        idx = idx % #options + 1
        render()
        if cb then pcall(cb, options[idx], idx) end
    end)
    return f, function() return options[idx] end
end

--=====================================================================
--  ISLAND DATA (approximate coords — the marker list below is exact)
--=====================================================================
local ISLANDS = {
    "Middle Town", "Jungle", "Pirate Village", "Desert", "Frozen Village", "Marine Ford",
    "Skyland", "Colosseum", "Magma Village", "Underwater City", "Fountain City", "Impel Down",
    "Kingdom of Rose", "Cafe", "Green Zone", "Graveyard", "Snow Mountain", "Hot and Cold",
    "Cursed Ship", "Ice Castle", "Forgotten Island",
    "Port Town", "Hydra Island", "Great Tree", "Floating Turtle", "Haunted Castle",
    "Castle on the Sea", "Sea of Treats", "Temple of Time",
}
local ISLAND_POS = {
    ["Middle Town"]     = Vector3.new(-50, 25, 2750),
    ["Jungle"]          = Vector3.new(-1600, 40, 150),
    ["Pirate Village"]  = Vector3.new(-1150, 20, 3890),
    ["Desert"]          = Vector3.new(950, 10, 4230),
    ["Frozen Village"]  = Vector3.new(-1130, 25, 1260),
    ["Marine Ford"]     = Vector3.new(-4840, 25, 4310),
    ["Skyland"]         = Vector3.new(-7900, 5550, -370),
    ["Colosseum"]       = Vector3.new(-1650, 35, -3000),
    ["Magma Village"]   = Vector3.new(-5250, 25, 850),
    ["Underwater City"] = Vector3.new(4200, -245, -4200),
    ["Fountain City"]   = Vector3.new(5250, 45, 4000),
    ["Impel Down"]      = Vector3.new(4840, 10, 710),
    ["Kingdom of Rose"] = Vector3.new(-400, 30, -3400),
    ["Cafe"]            = Vector3.new(-380, 60, -280),
    ["Green Zone"]      = Vector3.new(1000, 70, -2900),
    ["Graveyard"]       = Vector3.new(-1900, 30, -3000),
    ["Snow Mountain"]   = Vector3.new(1000, 20, -2200),
    ["Hot and Cold"]    = Vector3.new(-600, 20, -4000),
    ["Cursed Ship"]     = Vector3.new(900, 130, -1250),
    ["Ice Castle"]      = Vector3.new(600, 20, -3100),
    ["Forgotten Island"]= Vector3.new(-3000, 50, -2300),
    ["Port Town"]       = Vector3.new(-270, 10, 3500),
    ["Hydra Island"]    = Vector3.new(5800, 400, -2800),
    ["Great Tree"]      = Vector3.new(2800, 500, -2400),
    ["Floating Turtle"] = Vector3.new(-7200, 500, -1800),
    ["Haunted Castle"]  = Vector3.new(-6000, 400, -2800),
    ["Castle on the Sea"]= Vector3.new(-5000, 300, -3300),
    ["Sea of Treats"]   = Vector3.new(-1600, 40, 2500),
    ["Temple of Time"]  = Vector3.new(28000, 1000, 20000),
}

local function goToIsland(name)
    local pos = ISLAND_POS[name]
    if not pos then notify("No coordinates for " .. name) return end
    if S.ServerTP then
        invoke("requestEntrance", CFrame.new(pos))
    else
        tpTo(pos)
    end
    notify("Travelling to " .. name)
end

local function markerNames()
    local out, seen = {}, {}
    local loc = locations()
    if loc then
        for _, v in ipairs(loc:GetChildren()) do
            local n = v.Name
            if not seen[n] then seen[n] = true out[#out + 1] = n end
        end
    end
    table.sort(out)
    return out
end

local function goToMarker(name)
    local loc = locations()
    if not loc then return end
    for _, v in ipairs(loc:GetChildren()) do
        if v:IsA("BasePart") and v.Name == name then
            tpTo(v.Position + Vector3.new(0, 5, 0))
            return
        end
    end
end

local function seaTravel(sea)
    local sets = {
        ["First Sea"]  = { "TravelMain", "TravelEastBlue" },
        ["Second Sea"] = { "TravelDressrosa" },
        ["Third Sea"]  = { "TravelZou" },
    }
    for _, remote in ipairs(sets[sea] or {}) do
        local res = invoke(remote)
        if res ~= nil then break end
    end
    notify("Sailing to " .. sea)
end

local function serverHop()
    local url = "https://games.roblox.com/v1/games/" .. PLACE_ID .. "/servers/Public?limit=100"
    local ok, body = pcall(function() return game:HttpGet(url) end)
    if not ok then notify("Server hop failed (HTTP)") return end
    local data
    pcall(function() data = Http:JSONDecode(body) end)
    if not (data and data.data) then notify("Server hop: bad response") return end
    local pool = {}
    for _, s in ipairs(data.data) do
        if s.id ~= game.JobId and s.playing < s.maxPlayers then pool[#pool + 1] = s.id end
    end
    if #pool == 0 then notify("No open servers") return end
    notify("Hopping server...")
    task.wait(0.4)
    TeleportSvc:TeleportToPlaceInstance(PLACE_ID, pool[math.random(#pool)], LP)
end

--=====================================================================
--  TABS
--=====================================================================
local pFarm = newTab("Farm")
Section(pFarm, "Level Farming")
Toggle(pFarm, "Auto Farm (nearest mob)", S.AutoFarm, function(v) S.AutoFarm = v end)
Toggle(pFarm, "Magnet Mobs / Kill Aura", S.BringMobs, function(v) S.BringMobs = v end)
Slider(pFarm, "Farm Range", 50, 1000, S.FarmRange, function(v) S.FarmRange = v end)
Slider(pFarm, "Stand-off Distance", 3, 30, S.StandOff, function(v) S.StandOff = v end)
Toggle(pFarm, "Boss Priority (skip [Lv. mobs])", S.BossPriority, function(v) S.BossPriority = v end)
Toggle(pFarm, "Auto Equip Weapon", S.AutoEquip, function(v) S.AutoEquip = v end)
Toggle(pFarm, "Use Fruit M1 instead", S.UseFruitM1, function(v) S.UseFruitM1 = v end)
Toggle(pFarm, "Fast Attack (zero cooldown)", S.FastAttack, function(v) S.FastAttack = v end)
Toggle(pFarm, "Auto Skills (Z X C V)", S.AutoSkills, function(v) S.AutoSkills = v end)
Slider(pFarm, "Skill Delay", 0.5, 8, S.SkillDelay, function(v) S.SkillDelay = v end)
Toggle(pFarm, "Auto Haki (J)", S.AutoHaki, function(v) S.AutoHaki = v end)
Slider(pFarm, "Haki Delay", 1, 20, S.HakiDelay, function(v) S.HakiDelay = v end)

Section(pFarm, "Chests & Loot  (paused while Auto Farm is on)")
Toggle(pFarm, "Auto Chest Farm", S.AutoChest, function(v) S.AutoChest = v end)
Slider(pFarm, "Chest Dwell", 0.05, 1, S.ChestDwell, function(v) S.ChestDwell = v end)
Toggle(pFarm, "Auto Collect Loot", S.AutoLoot, function(v) S.AutoLoot = v end)
Slider(pFarm, "Loot Range", 100, 2500, S.LootRange, function(v) S.LootRange = v end)

local pFruit = newTab("Fruits")
Section(pFruit, "Devil Fruits  (paused while Auto Farm is on)")
Toggle(pFruit, "Fruit ESP", S.FruitESP, function(v) S.FruitESP = v end)
Toggle(pFruit, "Auto Collect Fruit", S.AutoFruit, function(v) S.AutoFruit = v end)
Slider(pFruit, "Fruit Dwell", 0.05, 1, S.FruitDwell, function(v) S.FruitDwell = v end)
Button(pFruit, "Teleport to nearest fruit", function()
    local list = getFruits()
    if #list == 0 then notify("No fruit found") return end
    table.sort(list, function(a, b) return a.dist < b.dist end)
    touch(list[1].part)
    notify("Jumped to " .. list[1].name)
end)
Button(pFruit, "Copy fruit name list to clipboard", function()
    if setclipboard then
        setclipboard(table.concat(FRUIT_NAMES, ", "))
        notify("Fruit list copied")
    end
end)

Section(pFruit, "Shop / Unlocks  (stand near the NPC)")
Button(pFruit, "Buy Busoshoku Haki", function() invoke("BuyHaki", "Buso") notify("Buso requested") end)
Button(pFruit, "Buy Kenbunshoku Haki", function() invoke("BuyHaki", "Ken") notify("Ken requested") end)
Button(pFruit, "Buy Geppo (Sky Walk)", function() invoke("BuyHaki", "Geppo") notify("Geppo requested") end)
Button(pFruit, "Buy Soru", function() invoke("BuyHaki", "Soru") notify("Soru requested") end)
Button(pFruit, "Buy Black Leg", function() invoke("BuyBlackLeg") notify("Black Leg requested") end)
Button(pFruit, "Buy Electro", function() invoke("BuyElectro") notify("Electro requested") end)
Button(pFruit, "Buy Fishman Karate", function() invoke("BuyFishmanKarate") notify("Fishman Karate requested") end)
Button(pFruit, "Buy Superhuman", function() invoke("BuySuperhuman") notify("Superhuman requested") end)

local pTp = newTab("Teleport")
Section(pTp, "Seas")
Button(pTp, "Sail to First Sea", function() seaTravel("First Sea") end)
Button(pTp, "Sail to Second Sea", function() seaTravel("Second Sea") end)
Button(pTp, "Sail to Third Sea", function() seaTravel("Third Sea") end)

Section(pTp, "Islands")
local _, getIsland = Cycle(pTp, "Island", ISLANDS, 1, nil)
Button(pTp, "Teleport to Island", function() goToIsland(getIsland()) end)
Toggle(pTp, "Server-side teleport (requestEntrance)", S.ServerTP, function(v) S.ServerTP = v end)

Section(pTp, "Live Map Markers (exact positions)")
local markerList = markerNames()
local _, getMarker = Cycle(pTp, "Marker", markerList, 1, nil)
Button(pTp, "Teleport to Marker", function() goToMarker(getMarker()) end)
Button(pTp, "Copy all marker names", function()
    if setclipboard then
        setclipboard(table.concat(markerNames(), "\n"))
        notify("Marker names copied to clipboard")
    end
end)

Section(pTp, "Server")
Button(pTp, "Rejoin Server", function() TeleportSvc:Teleport(PLACE_ID, LP) end)
Button(pTp, "Server Hop (random)", serverHop)
Button(pTp, "Copy Job ID", function()
    if setclipboard then setclipboard(game.JobId) notify("Job ID copied") end
end)

local pPlayer = newTab("Player")
Section(pPlayer, "Stats")
Slider(pPlayer, "Walk Speed", 16, 600, S.Speed, function(v) S.Speed = v applyStats() end)
Slider(pPlayer, "Jump Power", 50, 600, S.Jump, function(v) S.Jump = v applyStats() end)
Toggle(pPlayer, "Infinite Energy", S.InfEnergy, function(v) S.InfEnergy = v end)

Section(pPlayer, "Auto Stat Points")
local STATS = { "Melee", "Defense", "Sword", "Gun", "Blox Fruit", "Demon Fruit" }
Cycle(pPlayer, "Stat", STATS, 1, function(v) S.StatType = v end)
Toggle(pPlayer, "Auto Spend Points", S.AutoStats, function(v) S.AutoStats = v end)

Section(pPlayer, "Movement")
Toggle(pPlayer, "Noclip", S.Noclip, function(v) S.Noclip = v end)
Toggle(pPlayer, "Fly (WASD / Space / LShift)", S.Fly, function(v)
    S.Fly = v
    if not v then stopFly() end
end)
Slider(pPlayer, "Fly Speed", 10, 600, S.FlySpeed, function(v) S.FlySpeed = v end)

local pVis = newTab("Visuals")
Section(pVis, "ESP")
Toggle(pVis, "Mobs", S.ESPMobs, function(v) S.ESPMobs = v end)
Toggle(pVis, "Players", S.ESPPlayers, function(v) S.ESPPlayers = v end)
Toggle(pVis, "Chests / Barrels", S.ESPChests, function(v) S.ESPChests = v end)
Toggle(pVis, "Devil Fruits", S.FruitESP, function(v) S.FruitESP = v end)
Section(pVis, "World")
Toggle(pVis, "Fullbright", S.Fullbright, function(v)
    S.Fullbright = v
    Lighting.Brightness = v and 4 or 2
    Lighting.Ambient = v and Color3.fromRGB(190, 190, 190) or Color3.fromRGB(70, 70, 70)
    Lighting.OutdoorAmbient = v and Color3.fromRGB(190, 190, 190) or Color3.fromRGB(70, 70, 70)
    Lighting.GlobalShadows = not v
end)

local pMisc = newTab("Misc")
Section(pMisc, "Utility")
Toggle(pMisc, "Anti-AFK", S.AntiAFK, function(v) S.AntiAFK = v end)
Button(pMisc, "Reset Character", function()
    local h = hum()
    if h then h.Health = 0 end
end)
Button(pMisc, "Save Settings", function() saveConfig() notify("Settings saved") end)
Button(pMisc, "Load Settings", function()
    loadConfig()
    notify("Settings loaded (re-toggle to apply)")
end)
Button(pMisc, "Copy Marker Names", function()
    if setclipboard then setclipboard(table.concat(markerNames(), "\n")) notify("Copied") end
end)

Section(pMisc, "Info")
Button(pMisc, "Toggle UI  (RightControl)", function() Main.Visible = not Main.Visible end)
Button(pMisc, "Unload Hub  (RightShift)", function()
    for k in pairs(S) do
        if type(S[k]) == "boolean" then S[k] = false end
    end
    stopFly()
    pcall(function() Gui:Destroy() end)
    getgenv().VeniceHub = nil
    notify("Venice Hub unloaded")
end)

-- select first tab
if tabs[1] then
    tabs[1].page.Visible = true
    tabs[1].btn.BackgroundColor3 = Theme.Accent
    tabs[1].btn.TextColor3 = Theme.Text
end

--=====================================================================
--  DRAG + HOTKEYS
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
        Main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
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
        for k in pairs(S) do if type(S[k]) == "boolean" then S[k] = false end end
        stopFly()
        pcall(function() Gui:Destroy() end)
        getgenv().VeniceHub = nil
    end
end)

getgenv().VeniceHub = { Gui = Gui, Config = S }
applyStats()
notify("Venice Hub loaded  ·  RightControl to toggle", "Blox Fruits")
