-- NotificationController: แจ้งเตือนสั้น ๆ กลางจอด้านบน (รับจาก Remotes.Notify หรือเรียก :Show() ตรง ๆ)
-- แต่ละแบบมีสี + ไอคอน: success ✔ / error ✖ / info ℹ

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("Theme"))

local NotificationController = {}

local STYLES = {
	info = { Color = Theme.Colors.Info, Icon = "i" },
	success = { Color = Theme.Colors.Success, Icon = "✓" },
	error = { Color = Theme.Colors.Danger, Icon = "!" },
}
local SHOW_TIME = 2.8
local MAX_VISIBLE = 4

local container: Frame
local order = 0

local function createGui()
	local gui = Instance.new("ScreenGui")
	gui.Name = "Notifications"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 30
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	container = Instance.new("Frame")
	container.Name = "Container"
	container.AnchorPoint = Vector2.new(0.5, 0)
	container.Position = UDim2.new(0.5, 0, 0, 64)
	container.Size = UDim2.fromOffset(620, 320)
	container.BackgroundTransparency = 1
	container.Parent = gui

	local layout = Instance.new("UIListLayout")
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 8)
	layout.Parent = container
end

local function fadeOut(toast: Frame)
	local info = TweenInfo.new(0.3)
	for _, d in toast:GetDescendants() do
		if d:IsA("TextLabel") then
			TweenService:Create(d, info, { TextTransparency = 1, BackgroundTransparency = 1 }):Play()
		elseif d:IsA("Frame") then
			TweenService:Create(d, info, { BackgroundTransparency = 1 }):Play()
		elseif d:IsA("UIStroke") then
			TweenService:Create(d, info, { Transparency = 1 }):Play()
		end
	end
	local tween = TweenService:Create(toast, info, { BackgroundTransparency = 1 })
	tween:Play()
	tween.Completed:Wait()
	toast:Destroy()
end

function NotificationController:Show(message: string, kind: string?)
	local style = STYLES[kind or "info"] or STYLES.info
	order += 1

	local toast = Instance.new("Frame")
	toast.Name = "Toast"
	toast.LayoutOrder = order
	toast.AutomaticSize = Enum.AutomaticSize.X
	toast.Size = UDim2.fromOffset(0, 44)
	toast.BackgroundColor3 = Theme.Colors.Panel
	toast.BackgroundTransparency = 0.05
	toast.Parent = container
	Theme.Corner(toast, 12)
	Theme.Stroke(toast, style.Color, 2, 0.2)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 8)
	pad.PaddingRight = UDim.new(0, 16)
	pad.Parent = toast
	local row = Instance.new("UIListLayout")
	row.FillDirection = Enum.FillDirection.Horizontal
	row.VerticalAlignment = Enum.VerticalAlignment.Center
	row.Padding = UDim.new(0, 10)
	row.SortOrder = Enum.SortOrder.LayoutOrder
	row.Parent = toast

	local icon = Theme.Text(toast, {
		LayoutOrder = 1,
		Size = UDim2.fromOffset(28, 28),
		BackgroundTransparency = 0,
		BackgroundColor3 = style.Color,
		TextColor3 = Theme.Colors.Backdrop,
		Font = Theme.Fonts.Title,
		TextSize = 16,
		Text = style.Icon,
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	Theme.Corner(icon, 14)

	Theme.Text(toast, {
		LayoutOrder = 2,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 44),
		Font = Theme.Fonts.Bold,
		TextSize = 18,
		TextColor3 = Theme.Colors.Text,
		Text = message,
	})

	-- เด้งเข้า
	local scale = Instance.new("UIScale")
	scale.Scale = 0.85
	scale.Parent = toast
	TweenService:Create(scale, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()

	-- เกินจำนวน ลบอันเก่าสุด
	local toasts = {}
	for _, child in container:GetChildren() do
		if child:IsA("Frame") then
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
		if toast.Parent then
			fadeOut(toast)
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
