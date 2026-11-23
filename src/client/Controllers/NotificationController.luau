-- NotificationController: แสดงข้อความแจ้งเตือนสั้น ๆ กลางจอด้านบน (รับจาก Remotes.Notify)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local NotificationController = {}

local COLORS = {
	info = Color3.fromRGB(255, 255, 255),
	success = Color3.fromRGB(120, 235, 130),
	error = Color3.fromRGB(255, 115, 115),
}
local SHOW_TIME = 2.5
local MAX_VISIBLE = 4

local container: Frame
local order = 0

local function createGui()
	local gui = Instance.new("ScreenGui")
	gui.Name = "Notifications"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 10
	gui.IgnoreGuiInset = false

	container = Instance.new("Frame")
	container.Name = "Container"
	container.AnchorPoint = Vector2.new(0.5, 0)
	container.Position = UDim2.new(0.5, 0, 0, 70)
	container.Size = UDim2.fromOffset(560, 300)
	container.BackgroundTransparency = 1
	container.Parent = gui

	local layout = Instance.new("UIListLayout")
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 6)
	layout.Parent = container

	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

local function fadeOut(label: TextLabel)
	local tween = TweenService:Create(label, TweenInfo.new(0.35), {
		TextTransparency = 1,
		TextStrokeTransparency = 1,
		BackgroundTransparency = 1,
	})
	tween:Play()
	tween.Completed:Wait()
	label:Destroy()
end

function NotificationController:Show(message: string, kind: string?)
	order += 1

	local label = Instance.new("TextLabel")
	label.Name = "Toast"
	label.LayoutOrder = order
	label.AutomaticSize = Enum.AutomaticSize.XY
	label.Size = UDim2.fromOffset(0, 36)
	label.BackgroundColor3 = Color3.fromRGB(25, 22, 20)
	label.BackgroundTransparency = 0.2
	label.Font = Enum.Font.GothamBold
	label.TextSize = 20
	label.TextColor3 = COLORS[kind or "info"] or COLORS.info
	label.TextStrokeTransparency = 0.6
	label.Text = message

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = label
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 14)
	padding.PaddingRight = UDim.new(0, 14)
	padding.PaddingTop = UDim.new(0, 6)
	padding.PaddingBottom = UDim.new(0, 6)
	padding.Parent = label

	label.Parent = container

	-- เกินจำนวนที่กำหนด ลบอันเก่าสุดทิ้ง
	local toasts = {}
	for _, child in container:GetChildren() do
		if child:IsA("TextLabel") then
			table.insert(toasts, child)
		end
	end
	table.sort(toasts, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)
	for i = 1, #toasts - MAX_VISIBLE do
		toasts[i]:Destroy()
	end

	task.delay(SHOW_TIME, function()
		if label.Parent then
			fadeOut(label)
		end
	end)
end

function NotificationController:Start()
	createGui()
	local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Notify") :: RemoteEvent
	remote.OnClientEvent:Connect(function(message, kind)
		self:Show(tostring(message), kind)
	end)
end

return NotificationController
