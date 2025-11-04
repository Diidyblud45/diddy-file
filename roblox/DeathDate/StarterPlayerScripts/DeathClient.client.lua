--[[
    Death Date - Countdown & Event Client
    Place this LocalScript in `StarterPlayerScripts` within the `DeathDate` folder.

    Responsibilities:
      • Renders the personal countdown UI on the player's screen.
      • Updates overhead BillboardGui text for all players using replicated attributes.
      • Handles event notifications when a cinematic death is triggered.
      • Keeps client timing synchronized with the server via `Workspace:GetServerTimeNow()`.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local localPlayer = Players.LocalPlayer

local REMOTE_FOLDER_NAME = "DeathDateRemotes"
local REMOTE_EVENT_NAME = "CountdownEvent"
local OVERHEAD_GUI_NAME = "DeathBillboard"
local OVERHEAD_LABEL_NAME = "TimerLabel"

local remotesFolder = ReplicatedStorage:WaitForChild(REMOTE_FOLDER_NAME)
local countdownEvent = remotesFolder:WaitForChild(REMOTE_EVENT_NAME)

local DEFAULT_OVERHEAD_TEXT = "Awaiting your fate"

local ui = Instance.new("ScreenGui")
ui.Name = "DeathDateHUD"
ui.ResetOnSpawn = false
ui.IgnoreGuiInset = true
ui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ui.Parent = localPlayer:WaitForChild("PlayerGui")

local countdownFrame = Instance.new("Frame")
countdownFrame.AnchorPoint = Vector2.new(0.5, 0)
countdownFrame.Position = UDim2.fromScale(0.5, 0.05)
countdownFrame.Size = UDim2.fromOffset(340, 80)
countdownFrame.BackgroundTransparency = 0.35
countdownFrame.BackgroundColor3 = Color3.fromRGB(15, 15, 25)
countdownFrame.BorderSizePixel = 0
countdownFrame.Visible = false
countdownFrame.Parent = ui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 12)
corner.Parent = countdownFrame

local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(255, 215, 95)
stroke.Thickness = 2
stroke.Transparency = 0.25
stroke.Parent = countdownFrame

local countdownLabel = Instance.new("TextLabel")
countdownLabel.BackgroundTransparency = 1
countdownLabel.Size = UDim2.fromScale(1, 0.6)
countdownLabel.Position = UDim2.fromScale(0, 0)
countdownLabel.Font = Enum.Font.GothamSemibold
countdownLabel.TextColor3 = Color3.fromRGB(255, 221, 141)
countdownLabel.TextScaled = true
countdownLabel.TextStrokeTransparency = 0.4
countdownLabel.Text = ""
countdownLabel.Parent = countdownFrame

local subtitleLabel = Instance.new("TextLabel")
subtitleLabel.BackgroundTransparency = 1
subtitleLabel.Size = UDim2.fromScale(1, 0.35)
subtitleLabel.Position = UDim2.fromScale(0, 0.62)
subtitleLabel.Font = Enum.Font.Gotham
subtitleLabel.TextColor3 = Color3.fromRGB(210, 210, 220)
subtitleLabel.TextScaled = true
subtitleLabel.TextTransparency = 0.2
subtitleLabel.TextStrokeTransparency = 0.5
subtitleLabel.Text = ""
subtitleLabel.Parent = countdownFrame

local eventPopup = Instance.new("TextLabel")
eventPopup.Name = "EventPopup"
eventPopup.BackgroundTransparency = 1
eventPopup.Size = UDim2.fromScale(1, 0.12)
eventPopup.Position = UDim2.fromScale(0.5, 0.22)
eventPopup.AnchorPoint = Vector2.new(0.5, 0.5)
eventPopup.Font = Enum.Font.GothamBlack
eventPopup.TextColor3 = Color3.new(1, 1, 1)
eventPopup.TextStrokeTransparency = 0.4
eventPopup.TextStrokeColor3 = Color3.fromRGB(30, 30, 35)
eventPopup.TextTransparency = 1
eventPopup.TextScaled = true
eventPopup.Visible = false
eventPopup.Parent = ui

local countdownState = {
    deadline = 0,
    duration = 0,
    active = false,
}

local function formatTime(secondsRemaining: number): string
    local seconds = math.max(0, math.floor(secondsRemaining + 0.5))
    local minutes = math.floor(seconds / 60)
    local secs = seconds % 60
    return string.format("%02d:%02d", minutes, secs)
end

local function easeCountdownFrame(visible: boolean)
    if visible == countdownFrame.Visible then
        return
    end
    countdownFrame.Visible = true
    countdownFrame.BackgroundTransparency = visible and 0.35 or 1
    countdownFrame.Position = UDim2.fromScale(0.5, visible and 0.05 or -0.1)

    local tween = TweenService:Create(
        countdownFrame,
        TweenInfo.new(0.45, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
        {
            BackgroundTransparency = visible and 0.35 or 1,
            Position = UDim2.fromScale(0.5, visible and 0.05 or -0.1),
        }
    )
    if not visible then
        tween.Completed:Connect(function()
            countdownFrame.Visible = false
        end)
    end
    tween:Play()
end

local function showEventMessage(description: string)
    eventPopup.Text = description
    eventPopup.TextTransparency = 1
    eventPopup.Visible = true

    local reveal = TweenService:Create(
        eventPopup,
        TweenInfo.new(0.35, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
        {TextTransparency = 0.05}
    )
    local hide = TweenService:Create(
        eventPopup,
        TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.In),
        {TextTransparency = 1}
    )

    reveal.Completed:Connect(function()
        task.delay(2, function()
            if eventPopup.Visible then
                hide:Play()
            end
        end)
    end)

    hide.Completed:Connect(function()
        eventPopup.Visible = false
    end)

    reveal:Play()
end

local function updateOverheadText()
    local serverTime = workspace:GetServerTimeNow()
    for _, player in ipairs(Players:GetPlayers()) do
        local deadline = player:GetAttribute("DeathDeadline")
        local character = player.Character
        if character then
            local head = character:FindFirstChild("Head")
            local billboard = head and head:FindFirstChild(OVERHEAD_GUI_NAME)
            local label = billboard and billboard:FindFirstChild(OVERHEAD_LABEL_NAME)
            if label and label:IsA("TextLabel") then
                if deadline then
                    local remaining = math.max(0, deadline - serverTime)
                    label.Text = string.format("You will die in %s", formatTime(remaining))
                else
                    label.Text = DEFAULT_OVERHEAD_TEXT
                end
            end
        end
    end
end

local function connectPlayerSignals(player: Player)
    player:GetAttributeChangedSignal("DeathDeadline"):Connect(function()
        updateOverheadText()
    end)
    player.CharacterAdded:Connect(function()
        task.wait(0.1)
        updateOverheadText()
    end)
end

countdownEvent.OnClientEvent:Connect(function(action, ...)
    if action == "Start" then
        local duration, deadline = ...
        countdownState.deadline = deadline
        countdownState.duration = duration
        countdownState.active = true
        countdownLabel.Text = string.format("You will die in %s", formatTime(duration))
        subtitleLabel.Text = "Await your fate"
        easeCountdownFrame(true)
    elseif action == "Reset" then
        countdownState.active = false
        countdownState.deadline = 0
        countdownState.duration = 0
        subtitleLabel.Text = ""
        countdownLabel.Text = ""
        easeCountdownFrame(false)
    elseif action == "Event" then
        local eventKey, description = ...
        countdownState.active = false
        countdownState.deadline = 0
        countdownState.duration = 0
        subtitleLabel.Text = ""
        easeCountdownFrame(false)
        showEventMessage(description)
    end
end)

RunService.RenderStepped:Connect(function()
    if countdownState.active then
        local remaining = math.max(0, countdownState.deadline - workspace:GetServerTimeNow())
        countdownLabel.Text = string.format("You will die in %s", formatTime(remaining))
        if remaining <= 0 then
            countdownState.active = false
        end
    end
end)

task.spawn(function()
    while true do
        updateOverheadText()
        task.wait(0.2)
    end
end)

Players.PlayerAdded:Connect(connectPlayerSignals)

for _, player in ipairs(Players:GetPlayers()) do
    connectPlayerSignals(player)
end

-- Initialize in case players are already in the server when we join.
updateOverheadText()
