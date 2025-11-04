--!strict

--[[
    Chair Tag - Core Server Controller

    Drop this Script inside `ServerScriptService/ChairTag` (or any folder replicated in that service).

    Responsibilities
      • Controls the chair-spawning musical-chaos round loop.
      • Tracks alive players, round phases, and victory conditions.
      • Handles push / shove combat requests from clients with validation + cooldowns.
      • Spawns trap (fake) chairs that vanish shortly after being used.
      • Fires periodic hazards to keep players moving and fighting for seats.
      • Streams high-level round state updates to clients through RemoteEvents.

    World expectations
      • If no arena exists, the script generates one at runtime using parts.
      • You can customise the arena by providing a `Folder` named `ChairTagArena`
        in `Workspace` containing spawn pads or decorative geometry.
      • Hazards avoid anchored parts tagged `ChairTagSafe`.

    Remote events
      • Folder: `ReplicatedStorage.ChairTagRemotes`
          - `RoundEvent`  (RemoteEvent) : server ➜ all/one client updates.
          - `PushRequest` (RemoteEvent) : client ➜ server push attempts.

    Round flow
      Waiting → PreRound countdown → Active round (hazards) → Sudden death sweep → Winner intermission.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")

local rng = Random.new()

-- Settings ---------------------------------------------------------------

local ROUND_MIN_PLAYERS = 2
local ROUND_PREP_TIME = 12
local ROUND_DURATION = 60
local ROUND_INTERMISSION = 10
local ROUND_STATUS_BROADCAST_HZ = 4

local PUSH_COOLDOWN = 4
local PUSH_RADIUS = 16
local PUSH_FORCE = 120

local FAKE_CHAIR_RATIO = 0.25
local FAKE_CHAIR_MIN = 1
local FAKE_CHAIR_DELAY = 1.8

local HAZARD_MIN_DELAY = 12
local HAZARD_MAX_DELAY = 22

local ARENA_CENTER = Vector3.new(0, 4, 0)
local ARENA_RADIUS = 45
local CHAIR_HEIGHT = 3

-- Remote setup ----------------------------------------------------------

local REMOTE_FOLDER_NAME = "ChairTagRemotes"
local ROUND_EVENT_NAME = "RoundEvent"
local PUSH_EVENT_NAME = "PushRequest"

local remoteFolder = ReplicatedStorage:FindFirstChild(REMOTE_FOLDER_NAME)
if not remoteFolder then
    remoteFolder = Instance.new("Folder")
    remoteFolder.Name = REMOTE_FOLDER_NAME
    remoteFolder.Parent = ReplicatedStorage
end

local roundEvent = remoteFolder:FindFirstChild(ROUND_EVENT_NAME)
if not roundEvent then
    roundEvent = Instance.new("RemoteEvent")
    roundEvent.Name = ROUND_EVENT_NAME
    roundEvent.Parent = remoteFolder
end

local pushRequest = remoteFolder:FindFirstChild(PUSH_EVENT_NAME)
if not pushRequest then
    pushRequest = Instance.new("RemoteEvent")
    pushRequest.Name = PUSH_EVENT_NAME
    pushRequest.Parent = remoteFolder
end

-- Types -----------------------------------------------------------------

type PlayerState = {
    player: Player,
    alive: boolean,
    lastPush: number,
}

type ChairInfo = {
    seat: Seat,
    isFake: boolean,
    vanishToken: any?,
}

type RoundContext = {
    chairs: {ChairInfo},
    roundId: number,
    startTime: number,
    endTime: number,
    active: boolean,
}

type HazardHandler = (ctx: RoundContext) -> ()

type HazardDefinition = {
    key: string,
    name: string,
    description: string,
    handler: HazardHandler,
}

-- State -----------------------------------------------------------------

local playerStates: {[Player]: PlayerState} = {}

local roundContext: RoundContext = {
    chairs = {},
    roundId = 0,
    startTime = 0,
    endTime = 0,
    active = false,
}

local arenaFolder: Folder = (function()
    local existing = Workspace:FindFirstChild("ChairTagArena")
    if existing and existing:IsA("Folder") then
        return existing
    end

    local generated = Instance.new("Folder")
    generated.Name = "ChairTagArena"
    generated.Parent = Workspace

    local floor = Instance.new("Part")
    floor.Name = "ArenaFloor"
    floor.Size = Vector3.new(110, 1, 110)
    floor.Anchored = true
    floor.Material = Enum.Material.SmoothPlastic
    floor.Color = Color3.fromRGB(40, 45, 65)
    floor.CFrame = CFrame.new(ARENA_CENTER.X, CHAIR_HEIGHT - 2.5, ARENA_CENTER.Z)
    floor:SetAttribute("ChairTagSafe", true)
    floor.Parent = generated

    local ring = Instance.new("CylinderHandleAdornment")
    ring.Name = "ArenaRing"
    ring.Adornee = floor
    ring.Color3 = Color3.fromRGB(255, 205, 90)
    ring.Radius = ARENA_RADIUS
    ring.Height = 0.4
    ring.CFrame = CFrame.Angles(math.rad(90), 0, 0)
    ring.ZIndex = 0
    ring.Transparency = 0.2
    ring.Parent = generated

    return generated
end)()

local chairsFolder: Folder = (function()
    local existing = arenaFolder:FindFirstChild("Chairs")
    if existing and existing:IsA("Folder") then
        return existing
    end
    local folder = Instance.new("Folder")
    folder.Name = "Chairs"
    folder.Parent = arenaFolder
    return folder
end)()

-- Utility functions -----------------------------------------------------

local function now(): number
    return Workspace:GetServerTimeNow()
end

local function broadcast(action: string, ...: any)
    roundEvent:FireAllClients(action, ...)
end

local function sendTo(player: Player, action: string, ...: any)
    roundEvent:FireClient(player, action, ...)
end

local function getHumanoid(character: Model?): Humanoid?
    if not character then
        return nil
    end
    return character:FindFirstChildOfClass("Humanoid")
end

local function getRootPart(character: Model?): BasePart?
    if not character then
        return nil
    end
    local root = character:FindFirstChild("HumanoidRootPart")
    if root and root:IsA("BasePart") then
        return root
    end
    return nil
end

local function alivePlayers(): {Player}
    local list = {} :: {Player}
    for player, state in pairs(playerStates) do
        if state.alive then
            table.insert(list, player)
        end
    end
    return list
end

local function setPlayerAlive(player: Player, isAlive: boolean)
    local state = playerStates[player]
    if not state then
        state = {
            player = player,
            alive = isAlive,
            lastPush = 0,
        }
        playerStates[player] = state
    else
        state.alive = isAlive
    end
    player:SetAttribute("ChairTagAlive", isAlive)
end

local function killPlayer(player: Player)
    setPlayerAlive(player, false)
    local humanoid = getHumanoid(player.Character)
    if humanoid then
        humanoid:TakeDamage(humanoid.MaxHealth)
    end
    broadcast("PlayerEliminated", player.DisplayName)
end

local function ensureCharacter(player: Player)
    if player.Character then
        return
    end
    player:LoadCharacter()
    player.CharacterAdded:Wait()
end

local function placeCharacterRandomly(player: Player)
    local character = player.Character
    if not character then
        return
    end
    local root = getRootPart(character)
    if not root then
        return
    end
    local angle = rng:NextNumber(0, math.pi * 2)
    local radius = rng:NextNumber(ARENA_RADIUS * 0.25, ARENA_RADIUS * 0.8)
    local x = ARENA_CENTER.X + math.cos(angle) * radius
    local z = ARENA_CENTER.Z + math.sin(angle) * radius
    local position = Vector3.new(x, CHAIR_HEIGHT + 1.5, z)
    root.CFrame = CFrame.new(position, Vector3.new(ARENA_CENTER.X, CHAIR_HEIGHT, ARENA_CENTER.Z))
end

local function clearChairs()
    for _, info in ipairs(roundContext.chairs) do
        if info.seat and info.seat.Parent then
            info.seat:Destroy()
        end
    end
    roundContext.chairs = {}
    for _, child in ipairs(chairsFolder:GetChildren()) do
        if child:IsA("Seat") then
            child:Destroy()
        end
    end
end

local function makeChair(position: CFrame, isFake: boolean): ChairInfo
    local seat = Instance.new("Seat")
    seat.Name = isFake and "TrapChair" or "Chair"
    seat.Size = Vector3.new(4.2, 1.1, 4.2)
    seat.Anchored = true
    seat.CanCollide = true
    seat.Color = isFake and Color3.fromRGB(212, 84, 84) or Color3.fromRGB(255, 210, 94)
    seat.Material = Enum.Material.SmoothPlastic
    seat.CFrame = position
    seat.TopSurface = Enum.SurfaceType.Smooth
    seat.BottomSurface = Enum.SurfaceType.Smooth
    seat.Parent = chairsFolder

    if isFake then
        local neon = Instance.new("SelectionBox")
        neon.Color3 = Color3.fromRGB(255, 120, 120)
        neon.LineThickness = 0.1
        neon.SurfaceTransparency = 1
        neon.Adornee = seat
        neon.Parent = seat
    end

    local info: ChairInfo = {
        seat = seat,
        isFake = isFake,
        vanishToken = nil,
    }

    seat:GetPropertyChangedSignal("Occupant"):Connect(function()
        local occupant = seat.Occupant
        if not occupant then
            info.vanishToken = nil
            return
        end

        if not info.isFake then
            return
        end

        local token = {}
        info.vanishToken = token
        task.delay(FAKE_CHAIR_DELAY, function()
            if info.vanishToken ~= token then
                return
            end
            if seat.Occupant ~= occupant then
                return
            end

            local humanoid = seat.Occupant
            if humanoid then
                humanoid.Sit = false
            end

            broadcast("ChairTrap", seat.Position)

            seat.CanCollide = false
            seat.Transparency = 1
            for _, child in ipairs(seat:GetChildren()) do
                if child:IsA("SelectionBox") then
                    child:Destroy()
                end
            end

            Debris:AddItem(seat, 0.1)
            info.seat = seat
            info.vanishToken = nil
        end)
    end)

    return info
end

local function generateChairPositions(count: number): {CFrame}
    local positions = {} :: {CFrame}
    local radius = math.clamp(ARENA_RADIUS * 0.65, 12, ARENA_RADIUS * 0.9)
    local vertical = CHAIR_HEIGHT

    for index = 1, count do
        local t = (index / count) * math.pi * 2 + rng:NextNumber(-0.3, 0.3)
        local dist = radius + rng:NextNumber(-6, 6)
        local pos = Vector3.new(
            ARENA_CENTER.X + math.cos(t) * dist,
            vertical,
            ARENA_CENTER.Z + math.sin(t) * dist
        )
        local lookAt = CFrame.new(pos, Vector3.new(ARENA_CENTER.X, vertical, ARENA_CENTER.Z))
        positions[index] = lookAt * CFrame.new(0, 0, 0)
    end

    return positions
end

local function spawnChairs(count: number)
    clearChairs()
    if count <= 0 then
        return
    end

    local trapCount = math.max(FAKE_CHAIR_MIN, math.floor(count * FAKE_CHAIR_RATIO))
    trapCount = math.clamp(trapCount, 0, math.max(0, count - 1))

    local trapIndices = {}
    local taken: {[number]: boolean} = {}
    while #trapIndices < trapCount do
        local idx = rng:NextInteger(1, count)
        if not taken[idx] then
            taken[idx] = true
            table.insert(trapIndices, idx)
        end
    end

    local trapSet: {[number]: boolean} = {}
    for _, idx in ipairs(trapIndices) do
        trapSet[idx] = true
    end

    local positions = generateChairPositions(count)
    for i = 1, count do
        local info = makeChair(positions[i], trapSet[i] == true)
        table.insert(roundContext.chairs, info)
    end

    broadcast("ChairsSpawned", count, trapCount)
end

local function seatBelongsToRound(seat: Seat): boolean
    for _, info in ipairs(roundContext.chairs) do
        if info.seat == seat then
            return true
        end
    end
    return false
end

local function seatedOnChair(player: Player): boolean
    local character = player.Character
    if not character then
        return false
    end
    local humanoid = getHumanoid(character)
    if not humanoid then
        return false
    end
    local seat = humanoid.SeatPart
    if not seat then
        return false
    end
    if not seat:IsA("Seat") then
        return false
    end
    return seatBelongsToRound(seat)
end

-- Hazards ---------------------------------------------------------------

local hazards: {HazardDefinition}

local function hazardChairShuffle(ctx: RoundContext)
    if #ctx.chairs == 0 then
        return
    end
    local newPositions = generateChairPositions(#ctx.chairs)
    for index, info in ipairs(ctx.chairs) do
        if info.seat and info.seat.Parent then
            local cf = newPositions[index]
            info.seat.CFrame = cf
        end
    end
end

local function hazardGust(ctx: RoundContext)
    local survivors = alivePlayers()
    if #survivors == 0 then
        return
    end

    for _, player in ipairs(survivors) do
        if not seatedOnChair(player) then
            local character = player.Character
            local root = getRootPart(character)
            if root then
                local direction = (root.Position - ARENA_CENTER).Unit
                local impulse = direction * rng:NextNumber(80, 110) + Vector3.new(0, 45, 0)
                local bodyVelocity = Instance.new("BodyVelocity")
                bodyVelocity.MaxForce = Vector3.new(1e5, 1e5, 1e5)
                bodyVelocity.Velocity = impulse
                bodyVelocity.Parent = root
                Debris:AddItem(bodyVelocity, 0.25)
            end
        end
    end
end

local function hazardMeteorRain(ctx: RoundContext)
    local dropCount = math.clamp(#ctx.chairs + 2, 3, 10)
    for _ = 1, dropCount do
        task.delay(rng:NextNumber(0, 2.2), function()
            local targetPos = ARENA_CENTER + Vector3.new(
                rng:NextNumber(-ARENA_RADIUS, ARENA_RADIUS),
                0,
                rng:NextNumber(-ARENA_RADIUS, ARENA_RADIUS)
            )
            local meteor = Instance.new("Part")
            meteor.Name = "ChairTagMeteor"
            meteor.Shape = Enum.PartType.Ball
            meteor.Size = Vector3.new(4, 4, 4)
            meteor.Material = Enum.Material.Neon
            meteor.Color = Color3.fromRGB(255, 95, 36)
            meteor.Anchored = true
            meteor.CanCollide = false
            meteor.CFrame = CFrame.new(targetPos + Vector3.new(0, 80, 0))
            meteor.Parent = Workspace

            local light = Instance.new("PointLight")
            light.Color = Color3.fromRGB(255, 160, 60)
            light.Range = 25
            light.Brightness = 4
            light.Parent = meteor

            local targetTime = 0.85
            local startTime = now()

            local connection
            connection = RunService.Heartbeat:Connect(function()
                local progress = math.clamp((now() - startTime) / targetTime, 0, 1)
                meteor.CFrame = CFrame.new(
                    targetPos + Vector3.new(0, (1 - progress) * 80, 0)
                )
                if progress >= 1 then
                    connection:Disconnect()
                    local explosion = Instance.new("Explosion")
                    explosion.Position = targetPos
                    explosion.BlastPressure = 0
                    explosion.BlastRadius = 10
                    explosion.DestroyJointRadiusPercent = 0
                    explosion.Parent = Workspace

                    explosion.Hit:Connect(function(part)
                        local hitCharacter = part:FindFirstAncestorOfClass("Model")
                        if hitCharacter then
                            local humanoid = hitCharacter:FindFirstChildOfClass("Humanoid")
                            if humanoid then
                                humanoid:TakeDamage(30)
                            end
                        end
                    end)

                    Debris:AddItem(explosion, 0.2)
                    Debris:AddItem(meteor, 0.05)
                end
            end)
        end)
    end
end

local function hazardTrapSurge(ctx: RoundContext)
    local available = {} :: {ChairInfo}
    for _, info in ipairs(ctx.chairs) do
        if info.seat and info.seat.Parent and not info.isFake then
            table.insert(available, info)
        end
    end
    if #available == 0 then
        return
    end
    local toConvert = math.max(1, math.floor(#available * 0.35))
    for i = 1, toConvert do
        local pickIndex = rng:NextInteger(1, #available)
        local chair = available[pickIndex]
        chair.isFake = true
        local indicator = chair.seat:FindFirstChildWhichIsA("SelectionBox")
        if not indicator then
            indicator = Instance.new("SelectionBox")
            indicator.Color3 = Color3.fromRGB(255, 120, 120)
            indicator.LineThickness = 0.1
            indicator.SurfaceTransparency = 1
            indicator.Adornee = chair.seat
            indicator.Parent = chair.seat
        end
        available[pickIndex] = available[#available]
        available[#available] = nil
    end
end

hazards = {
    {
        key = "CHAIR_SHUFFLE",
        name = "Chair Shuffle",
        description = "Every chair teleports to a new spot!",
        handler = hazardChairShuffle,
    },
    {
        key = "GUST_FRONTIER",
        name = "Gale Force Gust",
        description = "A violent gust tosses anyone not sitting!",
        handler = hazardGust,
    },
    {
        key = "METEOR_RAIN",
        name = "Meteor Rain",
        description = "Molten rocks crash into the arena!",
        handler = hazardMeteorRain,
    },
    {
        key = "TRAP_SURGE",
        name = "Trap Surge",
        description = "Some honest chairs were swapped for fakes...",
        handler = hazardTrapSurge,
    },
}

local function triggerHazard()
    if not roundContext.active then
        return
    end
    if #hazards == 0 then
        return
    end
    local index = rng:NextInteger(1, #hazards)
    local hazard = hazards[index]
    broadcast("Hazard", hazard.key, hazard.name, hazard.description)
    local success, err = pcall(function()
        hazard.handler(roundContext)
    end)
    if not success then
        warn(string.format("[ChairTag] Hazard '%s' failed: %s", hazard.key, err))
    end
end

-- Push handling ---------------------------------------------------------

local function applyPush(fromPlayer: Player)
    local state = playerStates[fromPlayer]
    if not state or not state.alive then
        return
    end
    if not roundContext.active then
        sendTo(fromPlayer, "PushFeedback", "Inactive", 0)
        return
    end

    local currentTime = now()
    if currentTime - state.lastPush < PUSH_COOLDOWN then
        local remaining = math.max(0, PUSH_COOLDOWN - (currentTime - state.lastPush))
        sendTo(fromPlayer, "PushFeedback", "Cooldown", remaining)
        return
    end

    local character = fromPlayer.Character
    local root = getRootPart(character)
    if not root then
        sendTo(fromPlayer, "PushFeedback", "NoCharacter", 0)
        return
    end

    local targets = {} :: {Player}
    for player, otherState in pairs(playerStates) do
        if player ~= fromPlayer and otherState.alive then
            local otherCharacter = player.Character
            local otherRoot = getRootPart(otherCharacter)
            if otherRoot then
                local distance = (otherRoot.Position - root.Position).Magnitude
                if distance <= PUSH_RADIUS then
                    table.insert(targets, player)
                end
            end
        end
    end

    if #targets == 0 then
        sendTo(fromPlayer, "PushFeedback", "NoTargets", 0)
        state.lastPush = currentTime
        return
    end

    state.lastPush = currentTime

    for _, target in ipairs(targets) do
        local targetCharacter = target.Character
        local targetRoot = getRootPart(targetCharacter)
        local targetHumanoid = getHumanoid(targetCharacter)
        if targetRoot and targetHumanoid then
            local direction = (targetRoot.Position - root.Position)
            if direction.Magnitude < 1e-3 then
                direction = Vector3.new(0, 0, 1)
            end
            direction = direction.Unit
            local impulse = direction * PUSH_FORCE + Vector3.new(0, 45, 0)
            local velocity = Instance.new("BodyVelocity")
            velocity.MaxForce = Vector3.new(1e5, 1e5, 1e5)
            velocity.Velocity = impulse
            velocity.Parent = targetRoot
            Debris:AddItem(velocity, 0.35)

            if targetHumanoid.SeatPart and targetHumanoid.SeatPart:IsA("Seat") then
                targetHumanoid.Sit = false
            end
        end
    end

    broadcast("PushActivated", fromPlayer.DisplayName)
    sendTo(fromPlayer, "PushFeedback", "Success", PUSH_COOLDOWN)
end

pushRequest.OnServerEvent:Connect(function(player: Player)
    local success, err = pcall(function()
        applyPush(player)
    end)
    if not success then
        warn(string.format("[ChairTag] Push handler error from %s: %s", player.Name, err))
    end
end)

-- Round loop ------------------------------------------------------------

local lastStatusBroadcast = 0

local function broadcastLobbyStatus(message: string)
    broadcast("Lobby", message, ROUND_MIN_PLAYERS)
end

local function performSweep()
    for player, state in pairs(playerStates) do
        if state.alive and not seatedOnChair(player) then
            killPlayer(player)
        end
    end
end

local function aliveCount(): number
    local count = 0
    for _, state in pairs(playerStates) do
        if state.alive then
            count += 1
        end
    end
    return count
end

local function determineWinner(): Player?
    local winner: Player? = nil
    for player, state in pairs(playerStates) do
        if state.alive then
            if winner then
                return nil
            end
            winner = player
        end
    end
    return winner
end

local function resetPlayersForRound(playersList: {Player})
    for _, player in ipairs(playersList) do
        ensureCharacter(player)
        setPlayerAlive(player, true)
        local humanoid = getHumanoid(player.Character)
        if humanoid then
            humanoid.Health = humanoid.MaxHealth
            humanoid.WalkSpeed = 16
            humanoid.JumpPower = 50
        end
        placeCharacterRandomly(player)
    end
end

local function runRoundLoop()
    while true do
        task.wait(0.25)

        local playersReady = #Players:GetPlayers()
        if roundContext.active then
            -- Already in-game; skip lobby logic.
            continue
        end

        if playersReady < ROUND_MIN_PLAYERS then
            if now() - lastStatusBroadcast >= 2 then
                broadcastLobbyStatus("Waiting for players")
                lastStatusBroadcast = now()
            end
            continue
        end

        local participants = {} :: {Player}
        for _, player in ipairs(Players:GetPlayers()) do
            table.insert(participants, player)
        end

        local roundStartTime = now() + ROUND_PREP_TIME
        broadcast("RoundStarting", roundStartTime, #participants)

        -- Prep countdown loop
        while now() < roundStartTime do
            if #Players:GetPlayers() < ROUND_MIN_PLAYERS then
                broadcastLobbyStatus("A player left - countdown cancelled")
                goto continue_lobby_loop
            end
            task.wait(0.5)
        end

        roundContext.roundId += 1
        roundContext.startTime = now()
        roundContext.endTime = roundContext.startTime + ROUND_DURATION
        roundContext.active = true

        resetPlayersForRound(participants)

        local chairCount = math.max(1, math.max(#participants - 1, 1))
        spawnChairs(chairCount)

        broadcast("RoundStarted", roundContext.roundId, roundContext.endTime, chairCount)

        local nextHazardTime = now() + rng:NextNumber(HAZARD_MIN_DELAY, HAZARD_MAX_DELAY)
        local lastRoundStatus = 0

        while roundContext.active do
            local currentTime = now()

            if currentTime >= roundContext.endTime then
                performSweep()
                local winnerAfterSweep = determineWinner()
                if winnerAfterSweep then
                    broadcast("Winner", winnerAfterSweep.DisplayName)
                else
                    broadcast("Winner", nil)
                end
                break
            end

            if currentTime >= nextHazardTime then
                triggerHazard()
                nextHazardTime = currentTime + rng:NextNumber(HAZARD_MIN_DELAY, HAZARD_MAX_DELAY)
            end

            local aliveTotal = aliveCount()
            if aliveTotal <= 1 then
                local winner = determineWinner()
                broadcast("Winner", winner and winner.DisplayName or nil)
                break
            end

            if currentTime - lastRoundStatus >= (1 / ROUND_STATUS_BROADCAST_HZ) then
                broadcast("RoundTick", roundContext.endTime, aliveTotal)
                lastRoundStatus = currentTime
            end

            task.wait(0.1)
        end

        roundContext.active = false
        broadcast("RoundEnded", roundContext.roundId)

        task.wait(ROUND_INTERMISSION)

        ::continue_lobby_loop::
        clearChairs()
        for player, state in pairs(playerStates) do
            state.alive = false
            player:SetAttribute("ChairTagAlive", false)
        end
    end
end

task.spawn(runRoundLoop)

-- Player management -----------------------------------------------------

local function onPlayerAdded(player: Player)
    playerStates[player] = {
        player = player,
        alive = false,
        lastPush = 0,
    }
    player:SetAttribute("ChairTagAlive", false)

    player.CharacterAdded:Connect(function(character)
        if not character then
            return
        end
        local humanoid = getHumanoid(character)
        if humanoid then
            humanoid.Died:Connect(function()
                local state = playerStates[player]
                if state and state.alive then
                    state.alive = false
                    player:SetAttribute("ChairTagAlive", false)
                    broadcast("PlayerEliminated", player.DisplayName)
                else
                    player:SetAttribute("ChairTagAlive", false)
                end
            end)
        end
    end)
end

local function onPlayerRemoving(player: Player)
    playerStates[player] = nil
    broadcast("PlayerLeft", player.DisplayName)
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)

for _, player in ipairs(Players:GetPlayers()) do
    onPlayerAdded(player)
end

print("[ChairTag] Chair Tag controller initialised.")
