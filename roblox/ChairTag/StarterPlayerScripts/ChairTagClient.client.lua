--!strict

--[[
    Chair Tag - Client HUD & Interaction Controller

    Place inside `StarterPlayerScripts/ChairTag` as a LocalScript. Coordinates with
    the server controller to render round status, hazard callouts, and push abilities.

    Features
      • Lobby + round countdown UI with alive counts.
      • Hazard & trap callouts with lightweight screen effects.
      • Push ability input binding (default key: Q / ButtonR1) with cooldown feedback.
      • Winner + elimination toast notifications.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ContextActionService = game:GetService("ContextActionService")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")

local localPlayer = Players.LocalPlayer

local REMOTE_FOLDER_NAME = "ChairTagRemotes"
local ROUND_EVENT_NAME = "RoundEvent"
local PUSH_EVENT_NAME = "PushRequest"

local remotesFolder = ReplicatedStorage:WaitForChild(REMOTE_FOLDER_NAME)
local roundEvent = remotesFolder:WaitForChild(ROUND_EVENT_NAME) :: RemoteEvent
local pushRequest = remotesFolder:WaitForChild(PUSH_EVENT_NAME) :: RemoteEvent

-- UI ---------------------------------------------------------------------

local gui = Instance.new("ScreenGui")
gui.Name = "ChairTagHUD"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = localPlayer:WaitForChild("PlayerGui")

local statusFrame = Instance.new("Frame")
statusFrame.Name = "StatusFrame"
statusFrame.AnchorPoint = Vector2.new(0.5, 0)
statusFrame.Position = UDim2.fromScale(0.5, 0.04)
statusFrame.Size = UDim2.fromOffset(420, 110)
statusFrame.BackgroundTransparency = 0.15
statusFrame.BackgroundColor3 = Color3.fromRGB(26, 28, 36)
statusFrame.BorderSizePixel = 0
statusFrame.Parent = gui

local statusCorner = Instance.new("UICorner")
statusCorner.CornerRadius = UDim.new(0, 14)
statusCorner.Parent = statusFrame

local statusStroke = Instance.new("UIStroke")
statusStroke.Color = Color3.fromRGB(255, 206, 103)
statusStroke.Thickness = 2
statusStroke.Transparency = 0.3
statusStroke.Parent = statusFrame

local statusLabel = Instance.new("TextLabel")
statusLabel.Name = "StatusLabel"
statusLabel.BackgroundTransparency = 1
statusLabel.Size = UDim2.fromScale(1, 0.5)
statusLabel.Position = UDim2.fromScale(0, 0)
statusLabel.Font = Enum.Font.GothamBlack
statusLabel.TextColor3 = Color3.fromRGB(255, 229, 173)
statusLabel.TextScaled = true
statusLabel.Text = "Waiting for players"
statusLabel.Parent = statusFrame

local timerLabel = Instance.new("TextLabel")
timerLabel.Name = "TimerLabel"
timerLabel.BackgroundTransparency = 1
timerLabel.Size = UDim2.fromScale(1, 0.35)
timerLabel.Position = UDim2.fromScale(0, 0.55)
timerLabel.Font = Enum.Font.GothamBold
timerLabel.TextColor3 = Color3.fromRGB(207, 214, 255)
timerLabel.TextScaled = true
timerLabel.Text = ""
timerLabel.Parent = statusFrame

local aliveLabel = Instance.new("TextLabel")
aliveLabel.Name = "AliveLabel"
aliveLabel.BackgroundTransparency = 1
aliveLabel.Size = UDim2.fromScale(1, 0.25)
aliveLabel.Position = UDim2.fromScale(0, 0.8)
aliveLabel.Font = Enum.Font.Gotham
aliveLabel.TextColor3 = Color3.fromRGB(165, 198, 255)
aliveLabel.TextScaled = true
aliveLabel.TextTransparency = 0.15
aliveLabel.Text = ""
aliveLabel.Parent = statusFrame

local hazardLabel = Instance.new("TextLabel")
hazardLabel.Name = "HazardLabel"
hazardLabel.BackgroundTransparency = 1
hazardLabel.AnchorPoint = Vector2.new(0.5, 0.5)
hazardLabel.Position = UDim2.fromScale(0.5, 0.36)
hazardLabel.Size = UDim2.fromScale(0.6, 0.14)
hazardLabel.Font = Enum.Font.GothamBlack
hazardLabel.TextColor3 = Color3.fromRGB(255, 241, 163)
hazardLabel.TextStrokeTransparency = 0.4
hazardLabel.TextStrokeColor3 = Color3.fromRGB(20, 20, 30)
hazardLabel.TextScaled = true
hazardLabel.TextTransparency = 1
hazardLabel.Visible = false
hazardLabel.Parent = gui

local hazardDesc = Instance.new("TextLabel")
hazardDesc.Name = "HazardDescription"
hazardDesc.BackgroundTransparency = 1
hazardDesc.AnchorPoint = Vector2.new(0.5, 0.5)
hazardDesc.Position = UDim2.fromScale(0.5, 0.45)
hazardDesc.Size = UDim2.fromScale(0.6, 0.12)
hazardDesc.Font = Enum.Font.GothamSemibold
hazardDesc.TextColor3 = Color3.fromRGB(230, 236, 255)
hazardDesc.TextStrokeTransparency = 0.6
hazardDesc.TextScaled = true
hazardDesc.TextTransparency = 1
hazardDesc.Visible = false
hazardDesc.Parent = gui

local toastFrame = Instance.new("Frame")
toastFrame.Name = "ToastFrame"
toastFrame.AnchorPoint = Vector2.new(0, 1)
toastFrame.Position = UDim2.fromScale(0.02, 0.95)
toastFrame.Size = UDim2.fromOffset(280, 72)
toastFrame.BackgroundTransparency = 0.3
toastFrame.BackgroundColor3 = Color3.fromRGB(20, 22, 28)
toastFrame.BorderSizePixel = 0
toastFrame.Visible = false
toastFrame.Parent = gui

local toastCorner = Instance.new("UICorner")
toastCorner.CornerRadius = UDim.new(0, 10)
toastCorner.Parent = toastFrame

local toastLabel = Instance.new("TextLabel")
toastLabel.Name = "ToastLabel"
toastLabel.BackgroundTransparency = 1
toastLabel.Size = UDim2.fromScale(1, 1)
toastLabel.Font = Enum.Font.GothamSemibold
toastLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
toastLabel.TextScaled = true
toastLabel.TextWrapped = true
toastLabel.Text = ""
toastLabel.Parent = toastFrame

local pushFrame = Instance.new("Frame")
pushFrame.Name = "PushFrame"
pushFrame.AnchorPoint = Vector2.new(0.5, 1)
pushFrame.Position = UDim2.fromScale(0.5, 0.96)
pushFrame.Size = UDim2.fromOffset(260, 70)
pushFrame.BackgroundTransparency = 0.15
pushFrame.BackgroundColor3 = Color3.fromRGB(28, 34, 45)
pushFrame.BorderSizePixel = 0
pushFrame.Parent = gui

local pushCorner = Instance.new("UICorner")
pushCorner.CornerRadius = UDim.new(0, 14)
pushCorner.Parent = pushFrame

local pushStroke = Instance.new("UIStroke")
pushStroke.Color = Color3.fromRGB(132, 197, 255)
pushStroke.Thickness = 2
pushStroke.Transparency = 0.45
pushStroke.Parent = pushFrame

local pushKeyLabel = Instance.new("TextLabel")
pushKeyLabel.Name = "PushKeyLabel"
pushKeyLabel.BackgroundTransparency = 1
pushKeyLabel.Size = UDim2.fromScale(0.4, 0.6)
pushKeyLabel.Position = UDim2.fromScale(0.05, 0.2)
pushKeyLabel.Font = Enum.Font.GothamBold
pushKeyLabel.TextColor3 = Color3.fromRGB(224, 238, 255)
pushKeyLabel.TextScaled = true
pushKeyLabel.Text = "[Q]"
pushKeyLabel.Parent = pushFrame

local pushStatusLabel = Instance.new("TextLabel")
pushStatusLabel.Name = "PushStatusLabel"
pushStatusLabel.BackgroundTransparency = 1
pushStatusLabel.Size = UDim2.fromScale(0.55, 0.8)
pushStatusLabel.Position = UDim2.fromScale(0.42, 0.1)
pushStatusLabel.Font = Enum.Font.GothamSemibold
pushStatusLabel.TextColor3 = Color3.fromRGB(195, 224, 255)
pushStatusLabel.TextScaled = true
pushStatusLabel.TextWrapped = true
pushStatusLabel.Text = "Push ready"
pushStatusLabel.Parent = pushFrame

-- State -----------------------------------------------------------------

type RoundStage = "Lobby" | "Starting" | "Active" | "Intermission"

local roundState = {
    stage = "Lobby" :: RoundStage,
    startTime = 0,
    endTime = 0,
    alive = 0,
    minPlayers = 0,
}

local pushState = {
    cooldownEndsAt = 0,
}

local function serverNow(): number
    return Workspace:GetServerTimeNow()
end

local function formatSeconds(seconds: number): string
    local value = math.max(0, math.floor(seconds + 0.5))
    local minutes = math.floor(value / 60)
    local secs = value % 60
    return string.format("%02d:%02d", minutes, secs)
end

local function showToast(message: string)
    toastLabel.Text = message
    toastFrame.Visible = true
    toastFrame.BackgroundTransparency = 0.3

    local reveal = TweenService:Create(toastFrame, TweenInfo.new(0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
        BackgroundTransparency = 0.1,
    })

    local hide = TweenService:Create(toastFrame, TweenInfo.new(0.35, Enum.EasingStyle.Sine, Enum.EasingDirection.In), {
        BackgroundTransparency = 1,
    })

    reveal.Completed:Connect(function()
        task.delay(2.2, function()
            if toastFrame.Visible then
                hide:Play()
            end
        end)
    end)

    hide.Completed:Connect(function()
        toastFrame.Visible = false
    end)

    reveal:Play()
end

local function showHazard(title: string, description: string)
    hazardLabel.Text = title
    hazardDesc.Text = description
    hazardLabel.Visible = true
    hazardDesc.Visible = true

    hazardLabel.TextTransparency = 1
    hazardDesc.TextTransparency = 1

    local reveal = TweenService:Create(hazardLabel, TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
        TextTransparency = 0.05,
    })
    local revealDesc = TweenService:Create(hazardDesc, TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
        TextTransparency = 0.1,
    })

    local hide = TweenService:Create(hazardLabel, TweenInfo.new(0.45, Enum.EasingStyle.Sine, Enum.EasingDirection.In), {
        TextTransparency = 1,
    })
    local hideDesc = TweenService:Create(hazardDesc, TweenInfo.new(0.45, Enum.EasingStyle.Sine, Enum.EasingDirection.In), {
        TextTransparency = 1,
    })

    reveal.Completed:Connect(function()
        task.delay(2.6, function()
            hide:Play()
            hideDesc:Play()
        end)
    end)

    hide.Completed:Connect(function()
        hazardLabel.Visible = false
        hazardDesc.Visible = false
    end)

    reveal:Play()
    revealDesc:Play()
end

local function spawnTrapEffect(position: Vector3)
    task.spawn(function()
        local part = Instance.new("Part")
        part.Anchored = true
        part.CanCollide = false
        part.Transparency = 1
        part.Size = Vector3.new(1, 1, 1)
        part.CFrame = CFrame.new(position)
        part.Parent = Workspace

        local particles = Instance.new("ParticleEmitter")
        particles.Texture = "rbxassetid://258128463"
        particles.Color = ColorSequence.new(Color3.fromRGB(255, 160, 160), Color3.fromRGB(255, 90, 90))
        particles.Speed = NumberRange.new(12, 18)
        particles.Lifetime = NumberRange.new(0.4, 0.65)
        particles.Rate = 0
        particles.Size = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 2.6),
            NumberSequenceKeypoint.new(1, 0.2),
        })
        particles.Parent = part
        particles:Emit(40)

        Debris:AddItem(part, 1.5)
    end)
end

local function updatePushUI()
    local remaining = math.max(0, pushState.cooldownEndsAt - serverNow())
    if remaining > 0 then
        pushStatusLabel.Text = string.format("Cooldown %.1fs", remaining)
        pushStroke.Color = Color3.fromRGB(255, 134, 134)
    else
        pushStatusLabel.Text = "Push ready"
        pushStroke.Color = Color3.fromRGB(132, 197, 255)
    end
end

local function updateStatusUI()
    if roundState.stage == "Lobby" then
        timerLabel.Text = ""
        if roundState.minPlayers > 0 then
            aliveLabel.Text = string.format("Players: %d / %d", Players.NumPlayers, roundState.minPlayers)
        else
            aliveLabel.Text = string.format("Players: %d", Players.NumPlayers)
        end
    elseif roundState.stage == "Starting" then
        local remaining = math.max(0, roundState.startTime - serverNow())
        timerLabel.Text = string.format("Round begins in %s", formatSeconds(remaining))
        aliveLabel.Text = string.format("Players: %d", roundState.alive)
    elseif roundState.stage == "Active" then
        local remaining = math.max(0, roundState.endTime - serverNow())
        timerLabel.Text = string.format("Time left: %s", formatSeconds(remaining))
        aliveLabel.Text = string.format("Alive: %d", roundState.alive)
    elseif roundState.stage == "Intermission" then
        timerLabel.Text = "Intermission"
        aliveLabel.Text = ""
    end
end

-- Input -----------------------------------------------------------------

local function pushAction(actionName: string, inputState: Enum.UserInputState)
    if inputState ~= Enum.UserInputState.Begin then
        return Enum.ContextActionResult.Pass
    end

    local nowTime = serverNow()
    if nowTime < pushState.cooldownEndsAt then
        return Enum.ContextActionResult.Sink
    end

    pushRequest:FireServer()
    return Enum.ContextActionResult.Sink
end

ContextActionService:BindAction("ChairTagPush", pushAction, false, Enum.KeyCode.Q, Enum.KeyCode.ButtonR1)

-- Remote handling -------------------------------------------------------

roundEvent.OnClientEvent:Connect(function(action: string, ...: any)
    local args = {...}
    if action == "Lobby" then
        roundState.stage = "Lobby"
        local message = args[1] :: string?
        local minPlayers = args[2] :: number?
        roundState.alive = Players.NumPlayers
        roundState.minPlayers = minPlayers or roundState.minPlayers
        statusLabel.Text = message or "Waiting for players"
        updateStatusUI()
    elseif action == "RoundStarting" then
        roundState.stage = "Starting"
        local startTime = args[1] :: number
        local playerCount = args[2] :: number
        roundState.startTime = startTime
        roundState.alive = playerCount
        statusLabel.Text = "Round starting!"
        updateStatusUI()
    elseif action == "RoundStarted" then
        roundState.stage = "Active"
        local roundId = args[1] :: number
        local endTime = args[2] :: number
        local chairs = args[3] :: number
        roundState.endTime = endTime
        statusLabel.Text = string.format("Round %d - Grab a chair!", roundId)
        aliveLabel.Text = string.format("Chairs: %d", chairs)
        updateStatusUI()
    elseif action == "RoundTick" then
        local endTime = args[1] :: number
        local aliveCount = args[2] :: number
        roundState.endTime = endTime
        roundState.alive = aliveCount
        if roundState.stage == "Active" then
            updateStatusUI()
        end
    elseif action == "RoundEnded" then
        roundState.stage = "Intermission"
        statusLabel.Text = "Intermission"
        updateStatusUI()
    elseif action == "Hazard" then
        local hazardName = args[2] :: string
        local description = args[3] :: string
        showHazard(hazardName, description)
    elseif action == "ChairTrap" then
        local position = args[1] :: Vector3
        spawnTrapEffect(position)
        showToast("Trap chair vanished!")
    elseif action == "PushActivated" then
        local playerName = args[1] :: string
        if playerName ~= localPlayer.DisplayName then
            showToast(playerName .. " shoved the crowd!")
        end
    elseif action == "PushFeedback" then
        local status = args[1] :: string
        local value = args[2]
        local nowTime = serverNow()
        if status == "Success" then
            pushState.cooldownEndsAt = nowTime + (value :: number)
            showToast("Push unleashed!")
        elseif status == "Cooldown" then
            pushState.cooldownEndsAt = math.max(pushState.cooldownEndsAt, nowTime + (value :: number))
            showToast("Push cooling down")
        elseif status == "NoTargets" then
            showToast("No one nearby to shove")
            pushState.cooldownEndsAt = nowTime + 0.5
        elseif status == "Inactive" then
            showToast("Wait for the round to start")
        elseif status == "NoCharacter" then
            showToast("Respawning...")
        end
        updatePushUI()
    elseif action == "PlayerEliminated" then
        local displayName = args[1] :: string
        showToast(displayName .. " eliminated!")
    elseif action == "PlayerLeft" then
        local displayName = args[1] :: string
        showToast(displayName .. " left the match")
    elseif action == "ChairsSpawned" then
        local total = args[1] :: number
        local traps = args[2] :: number
        showToast(string.format("%d chairs dropped (%d traps)", total, traps))
    elseif action == "Winner" then
        local winnerName = args[1] :: string?
        if winnerName then
            showToast(string.format("%s wins the round!", winnerName))
            statusLabel.Text = string.format("Winner: %s", winnerName)
        else
            showToast("No one survived!")
            statusLabel.Text = "Nobody won"
        end
        roundState.stage = "Intermission"
        updateStatusUI()
    end
end)

-- Heartbeat updates -----------------------------------------------------

RunService.RenderStepped:Connect(function()
    updateStatusUI()
    updatePushUI()
end)

print("[ChairTag] Client HUD initialised.")
