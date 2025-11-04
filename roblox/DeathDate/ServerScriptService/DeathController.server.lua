--!strict

--[[
    Death Date - Countdown & Event Controller (Server)
    Place this Script in `ServerScriptService` inside a folder named `DeathDate`.

    Responsibilities:
      • Assigns each player a random countdown on spawn (30–300 seconds).
      • Tracks countdown state per player using server time for synchronization.
      • Fires remote signals so clients can render UI without excessive replication.
      • Triggers one of several cinematic death events when the timer expires.
      • Cleans up state on player death, respawn, or departure.
      • Ensures multiplayer scalability by avoiding per-frame server loops.

    Requirements on the place:
      • Keeps or creates a Folder named `DeathDateRemotes` under `ReplicatedStorage`.
      • Optionally create a Folder named `DeathDateAssets` under `ServerStorage`
        to supply custom models / sounds for the building-collapse event.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Debris = game:GetService("Debris")

local RANDOM_TIME_MIN = 30
local RANDOM_TIME_MAX = 300

local REMOTE_FOLDER_NAME = "DeathDateRemotes"
local REMOTE_EVENT_NAME = "CountdownEvent"

local OVERHEAD_GUI_NAME = "DeathBillboard"
local OVERHEAD_LABEL_NAME = "TimerLabel"

local countdownStates: {[Player]: {
    player: Player,
    character: Model?,
    deadline: number,
    cancelled: boolean,
    runner: thread?,
    humanoidDiedConn: RBXScriptConnection?,
}} = {}

local rng = Random.new()

local remoteFolder = ReplicatedStorage:FindFirstChild(REMOTE_FOLDER_NAME)
if not remoteFolder then
    remoteFolder = Instance.new("Folder")
    remoteFolder.Name = REMOTE_FOLDER_NAME
    remoteFolder.Parent = ReplicatedStorage
end

local countdownEvent = remoteFolder:FindFirstChild(REMOTE_EVENT_NAME)
if not countdownEvent then
    countdownEvent = Instance.new("RemoteEvent")
    countdownEvent.Name = REMOTE_EVENT_NAME
    countdownEvent.Parent = remoteFolder
end

type DeathEventFn = (player: Player, character: Model) -> ()

local function cleanupRunner(state)
    if state.runner then
        task.cancel(state.runner)
        state.runner = nil
    end
    if state.humanoidDiedConn then
        state.humanoidDiedConn:Disconnect()
        state.humanoidDiedConn = nil
    end
end

local function resetAttributes(player: Player)
    player:SetAttribute("DeathDeadline", nil)
    player:SetAttribute("DeathDuration", nil)
end

local function cancelCountdown(player: Player)
    local state = countdownStates[player]
    if state then
        state.cancelled = true
        cleanupRunner(state)
        countdownStates[player] = nil
    end
    resetAttributes(player)
    countdownEvent:FireClient(player, "Reset")
end

local function ensureOverheadGui(character: Model, player: Player)
    local head = character:FindFirstChild("Head")
    if not head or not head:IsA("BasePart") then
        warn(string.format("[DeathDate] Missing head for %s", player.Name))
        return nil
    end

    local existing = head:FindFirstChild(OVERHEAD_GUI_NAME)
    if existing then
        return existing
    end

    local billboard = Instance.new("BillboardGui")
    billboard.Name = OVERHEAD_GUI_NAME
    billboard.Adornee = head
    billboard.AlwaysOnTop = true
    billboard.ExtentsOffsetWorldSpace = Vector3.new(0, 1.5, 0)
    billboard.Size = UDim2.fromOffset(260, 50)
    billboard.MaxDistance = 200
    billboard.ResetOnSpawn = false
    billboard.Parent = head

    local label = Instance.new("TextLabel")
    label.Name = OVERHEAD_LABEL_NAME
    label.Size = UDim2.fromScale(1, 1)
    label.Position = UDim2.fromScale(0, 0)
    label.BackgroundTransparency = 1
    label.TextColor3 = Color3.new(1, 0.8, 0.1)
    label.Font = Enum.Font.GothamSemibold
    label.TextScaled = true
    label.TextStrokeTransparency = 0.25
    label.TextStrokeColor3 = Color3.new(0, 0, 0)
    label.Text = "You will die soon..."
    label.Parent = billboard

    return billboard
end

local function humanoidFromCharacter(character: Model?): Humanoid?
    if not character then
        return nil
    end
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    return humanoid
end

local function positionAbove(character: Model, offset: Vector3): CFrame
    local hrp = character:FindFirstChild("HumanoidRootPart")
    if hrp and hrp:IsA("BasePart") then
        return hrp.CFrame + offset
    end
    return CFrame.new(character:GetPivot().Position + offset)
end

local function lightningStrike(player: Player, character: Model)
    local targetCFrame = positionAbove(character, Vector3.new(0, 18, 0))
    local bolt = Instance.new("Part")
    bolt.Anchored = true
    bolt.CanCollide = false
    bolt.Material = Enum.Material.Neon
    bolt.Color = Color3.fromRGB(117, 186, 255)
    bolt.Transparency = 0
    bolt.Size = Vector3.new(0.35, 30, 0.35)
    bolt.CFrame = CFrame.new(targetCFrame.Position, character:GetPivot().Position)
    bolt.Parent = workspace

    local light = Instance.new("PointLight")
    light.Brightness = 6
    light.Range = 25
    light.Color = Color3.fromRGB(203, 233, 255)
    light.Parent = bolt

    local particles = Instance.new("ParticleEmitter")
    particles.Color = ColorSequence.new(Color3.new(1, 1, 1))
    particles.LightEmission = 1
    particles.Speed = NumberRange.new(12, 24)
    particles.Lifetime = NumberRange.new(0.15, 0.25)
    particles.Rate = 300
    particles.Texture = "rbxassetid://5695074144"
    particles.Parent = bolt
    particles:Emit(120)

    local sound = Instance.new("Sound")
    sound.SoundId = "rbxassetid://6026984221" -- thunder crack
    sound.Volume = 1.4
    sound.PlayOnRemove = true
    sound.Parent = bolt
    sound:Destroy()

    task.delay(0.3, function()
        bolt.Transparency = 1
    end)
    Debris:AddItem(bolt, 0.6)

    local humanoid = humanoidFromCharacter(character)
    if humanoid then
        humanoid:TakeDamage(humanoid.MaxHealth)
    end
end

local function meteorStrike(player: Player, character: Model)
    local hrp = character:FindFirstChild("HumanoidRootPart")
    if not hrp then
        return
    end

    local spawnPosition = hrp.Position + Vector3.new(rng:NextNumber(-30, 30), 60, rng:NextNumber(-30, 30))
    local meteor = Instance.new("Part")
    meteor.Name = "DeathMeteor"
    meteor.Shape = Enum.PartType.Ball
    meteor.Material = Enum.Material.Slate
    meteor.Color = Color3.fromRGB(140, 120, 100)
    meteor.Size = Vector3.new(8, 8, 8)
    meteor.Position = spawnPosition
    meteor.Massless = false
    meteor.CanCollide = true
    meteor.Anchored = false
    meteor.Parent = workspace

    local fire = Instance.new("ParticleEmitter")
    fire.Color = ColorSequence.new(Color3.fromRGB(255, 168, 66), Color3.fromRGB(255, 65, 35))
    fire.Texture = "rbxassetid://244221547"
    fire.Size = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 6),
        NumberSequenceKeypoint.new(1, 0.5),
    })
    fire.Lifetime = NumberRange.new(0.2, 0.4)
    fire.Speed = NumberRange.new(20, 40)
    fire.Rate = 400
    fire.Parent = meteor

    local trail = Instance.new("Trail")
    trail.Attachment0 = Instance.new("Attachment", meteor)
    trail.Attachment1 = Instance.new("Attachment", meteor)
    trail.Attachment0.Position = Vector3.new(0, 4, 0)
    trail.Attachment1.Position = Vector3.new(0, -4, 0)
    trail.Color = ColorSequence.new(Color3.fromRGB(253, 211, 103), Color3.fromRGB(255, 65, 35))
    trail.Transparency = NumberSequence.new(0, 0.7)
    trail.Lifetime = 0.4
    trail.MinLength = 0.1
    trail.Parent = meteor

    local bodyVelocity = Instance.new("BodyVelocity")
    bodyVelocity.MaxForce = Vector3.new(1e5, 1e5, 1e5)
    bodyVelocity.Velocity = (hrp.Position - spawnPosition).Unit * 140
    bodyVelocity.Parent = meteor

    local sound = Instance.new("Sound")
    sound.SoundId = "rbxassetid://1841436821" -- falling fireball
    sound.Volume = 1
    sound.Looped = true
    sound.Parent = meteor
    sound:Play()

    local function impact()
        if bodyVelocity.Parent then
            bodyVelocity:Destroy()
        end
        sound.Looped = false
        sound.SoundId = "rbxassetid://6026984223" -- explosion crack
        sound.TimePosition = 0
        sound:Play()

        local explosion = Instance.new("Explosion")
        explosion.BlastPressure = 0
        explosion.BlastRadius = 0
        explosion.Position = meteor.Position
        explosion.Parent = workspace

        local shockwave = Instance.new("ParticleEmitter")
        shockwave.Texture = "rbxassetid://138120125"
        shockwave.Speed = NumberRange.new(0)
        shockwave.Size = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 1),
            NumberSequenceKeypoint.new(1, 18),
        })
        shockwave.Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0.1),
            NumberSequenceKeypoint.new(1, 1),
        })
        shockwave.Lifetime = NumberRange.new(0.45)
        shockwave.Parent = meteor
        shockwave:Emit(1)

        local dust = Instance.new("ParticleEmitter")
        dust.Texture = "rbxassetid://258128463"
        dust.Speed = NumberRange.new(8, 16)
        dust.Size = NumberSequence.new(5)
        dust.Lifetime = NumberRange.new(0.8, 1.2)
        dust.Rate = 0
        dust.Parent = meteor
        dust:Emit(60)

        local humanoid = humanoidFromCharacter(character)
        if humanoid then
            humanoid:TakeDamage(humanoid.MaxHealth)
        end

        meteor.Anchored = true
        task.delay(1.8, function()
            meteor:Destroy()
        end)
    end

    meteor.Touched:Connect(function(part)
        if part:IsDescendantOf(character) then
            impact()
        elseif part:IsA("Terrain") or part.CanCollide then
            impact()
        end
    end)

    Debris:AddItem(meteor, 6)
end

local function collapseStructure(player: Player, character: Model)
    local hrp = character:FindFirstChild("HumanoidRootPart")
    if not hrp then
        return
    end

    local assetFolder = ServerStorage:FindFirstChild("DeathDateAssets")
    local prefab = assetFolder and assetFolder:FindFirstChild("CollapsingBuilding")
    local collapseModel: Model
    local usingPrefab = false

    if prefab and prefab:IsA("Model") then
        collapseModel = prefab:Clone()
        usingPrefab = true
    else
        collapseModel = Instance.new("Model")
        collapseModel.Name = "CollapsingBuilding"

        local colors = {
            Color3.fromRGB(66, 66, 72),
            Color3.fromRGB(88, 88, 96),
            Color3.fromRGB(58, 75, 90),
        }

        for level = 1, 4 do
            local wall = Instance.new("Part")
            wall.Size = Vector3.new(12, 3, 12)
            wall.Anchored = true
            wall.Material = Enum.Material.Concrete
            wall.Color = colors[(level - 1) % #colors + 1]
            wall.CFrame = CFrame.new(hrp.Position + Vector3.new(0, (level - 1) * 3 + 1.5, 0)) * CFrame.Angles(0, math.rad(level * 3), 0)
            wall.Parent = collapseModel
        end

        local roof = Instance.new("Part")
        roof.Size = Vector3.new(12, 1, 12)
        roof.Material = Enum.Material.Metal
        roof.Color = Color3.fromRGB(120, 120, 130)
        roof.CFrame = CFrame.new(hrp.Position + Vector3.new(0, 13, 0))
        roof.Anchored = true
        roof.Parent = collapseModel
    end

    collapseModel.Parent = workspace

    if usingPrefab then
        local targetCFrame = CFrame.new(hrp.Position) * CFrame.Angles(0, math.rad(rng:NextInteger(-12, 12)), 0)
        local success, err = pcall(function()
            collapseModel:PivotTo(targetCFrame)
        end)
        if not success then
            warn(string.format("[DeathDate] Failed to pivot collapse prefab for %s: %s", player.Name, err))
        end
    end

    local rumble = Instance.new("Sound")
    rumble.SoundId = "rbxassetid://1843529558"
    rumble.Volume = 1.2
    rumble.Looped = false
    rumble.Parent = collapseModel
    rumble:Play()

    local dustEmitter = Instance.new("ParticleEmitter")
    dustEmitter.Texture = "rbxassetid://258128463"
    dustEmitter.Size = NumberSequence.new(6)
    dustEmitter.Speed = NumberRange.new(5, 12)
    dustEmitter.Lifetime = NumberRange.new(1.2, 1.8)
    dustEmitter.Rate = 0

    local dustEmitters = {} :: {ParticleEmitter}

    for _, part in collapseModel:GetChildren() do
        if part:IsA("BasePart") then
            local attachment = Instance.new("Attachment")
            attachment.Parent = part
            local emitter = dustEmitter:Clone()
            emitter.Parent = attachment
            table.insert(dustEmitters, emitter)
        end
    end

    task.delay(0.35, function()
        for _, part in collapseModel:GetChildren() do
            if part:IsA("BasePart") then
                part.Anchored = false
                part.CanCollide = true
            end
        end

        for _, emitter in ipairs(dustEmitters) do
            emitter:Emit(rng:NextInteger(40, 70))
        end
    end)

    local humanoid = humanoidFromCharacter(character)
    if humanoid then
        humanoid:TakeDamage(humanoid.MaxHealth)
    end

    Debris:AddItem(collapseModel, 6)
end

local deathEvents: {[string]: {handler: DeathEventFn, description: string}} = {
    Lightning = {
        handler = lightningStrike,
        description = "A blinding bolt of lightning tears through the sky!",
    },
    Meteor = {
        handler = meteorStrike,
        description = "A burning meteor screams down from the heavens!",
    },
    Collapse = {
        handler = collapseStructure,
        description = "The world shakes as a structure collapses around you!",
    },
}

local function chooseDeathEvent(): (string, {handler: DeathEventFn, description: string})
    local keys = {} :: {string}
    for name in pairs(deathEvents) do
        table.insert(keys, name)
    end
    local choiceIndex = rng:NextInteger(1, #keys)
    local key = keys[choiceIndex]
    return key, deathEvents[key]
end

local function triggerDeathEvent(player: Player, character: Model)
    local state = countdownStates[player]
    if not state or state.cancelled then
        return
    end
    state.cancelled = true
    cleanupRunner(state)
    countdownStates[player] = nil

    local eventKey, eventData = chooseDeathEvent()
    local humanoid = humanoidFromCharacter(character)
    if humanoid then
        humanoid.WalkSpeed = 0
        humanoid.JumpPower = 0
    end

    local success, err = pcall(function()
        eventData.handler(player, character)
    end)

    if not success then
        warn(string.format("[DeathDate] Failed to run death event '%s' for %s: %s", eventKey, player.Name, err))
        if humanoid then
            humanoid:TakeDamage(humanoid.MaxHealth)
        end
    end

    countdownEvent:FireClient(player, "Event", eventKey, eventData.description)
    resetAttributes(player)
end

local function runCountdown(state)
    state.runner = task.spawn(function()
        while not state.cancelled do
            local remaining = state.deadline - workspace:GetServerTimeNow()
            if remaining <= 0 then
                break
            end
            task.wait(math.clamp(remaining, 0.25, 1))
        end

        if state.cancelled then
            return
        end

        local currentCharacter = state.player.Character
        if not currentCharacter or currentCharacter ~= state.character then
            cancelCountdown(state.player)
            return
        end

        triggerDeathEvent(state.player, state.character)
    end)
end

local function startCountdown(player: Player, character: Model)
    cancelCountdown(player)

    local duration = rng:NextInteger(RANDOM_TIME_MIN, RANDOM_TIME_MAX)
    local deadline = workspace:GetServerTimeNow() + duration

    local state = {
        player = player,
        character = character,
        deadline = deadline,
        cancelled = false,
    }
    countdownStates[player] = state

    player:SetAttribute("DeathDuration", duration)
    player:SetAttribute("DeathDeadline", deadline)

    countdownEvent:FireClient(player, "Start", duration, deadline)

    local humanoid = humanoidFromCharacter(character)
    if humanoid then
        state.humanoidDiedConn = humanoid.Died:Connect(function()
            cancelCountdown(player)
        end)
    end

    runCountdown(state)
end

local function onCharacterAdded(player: Player, character: Model)
    local billboard = ensureOverheadGui(character, player)
    if billboard then
        local label = billboard:FindFirstChild(OVERHEAD_LABEL_NAME)
        if label and label:IsA("TextLabel") then
            label.Text = "You will die soon..."
        end
    end

    -- Delay a bit so the character finishes spawning before the timer starts.
    task.delay(1, function()
        if player.Character ~= character then
            return
        end
        startCountdown(player, character)
    end)
end

local function onPlayerAdded(player: Player)
    player:SetAttribute("DeathDeadline", nil)
    player:SetAttribute("DeathDuration", nil)
    player.CharacterAdded:Connect(function(character)
        onCharacterAdded(player, character)
    end)
end

local function onPlayerRemoving(player: Player)
    cancelCountdown(player)
    countdownStates[player] = nil
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)

for _, player in ipairs(Players:GetPlayers()) do
    onPlayerAdded(player)
    if player.Character then
        onCharacterAdded(player, player.Character)
    end
end

print("[DeathDate] Death countdown system initialized.")
