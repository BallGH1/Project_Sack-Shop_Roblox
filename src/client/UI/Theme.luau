-- Theme: สี ฟอนต์ และตัวช่วยสร้าง UI ให้ทุกหน้าต่างหน้าตาไปในทางเดียวกัน
-- โทนสี: ร้านเสื้อมือสองอบอุ่น (น้ำตาลเข้ม + ส้มทอง)

local TweenService = game:GetService("TweenService")

local Theme = {}

Theme.Colors = {
	Backdrop = Color3.fromRGB(16, 13, 11),
	Panel = Color3.fromRGB(33, 28, 25),
	PanelLight = Color3.fromRGB(47, 40, 35),
	PanelLighter = Color3.fromRGB(66, 56, 48),
	Stroke = Color3.fromRGB(96, 78, 60),
	Accent = Color3.fromRGB(246, 180, 68),
	AccentDark = Color3.fromRGB(176, 112, 34),
	Text = Color3.fromRGB(247, 239, 225),
	Muted = Color3.fromRGB(178, 166, 150),
	Success = Color3.fromRGB(98, 204, 112),
	Danger = Color3.fromRGB(228, 88, 80),
	Info = Color3.fromRGB(104, 170, 250),
	Money = Color3.fromRGB(255, 212, 88),
}

Theme.Fonts = {
	Title = Enum.Font.GothamBlack,
	Bold = Enum.Font.GothamBold,
	Body = Enum.Font.GothamMedium,
}

local QUICK = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local POP = TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

---------------------------------------------------------------------
-- ตัวช่วยพื้นฐาน
---------------------------------------------------------------------

function Theme.Corner(parent: Instance, radius: number?): UICorner
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or 10)
	c.Parent = parent
	return c
end

function Theme.Stroke(parent: Instance, color: Color3?, thickness: number?, transparency: number?): UIStroke
	local s = Instance.new("UIStroke")
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Color = color or Theme.Colors.Stroke
	s.Thickness = thickness or 1.5
	s.Transparency = transparency or 0
	s.Parent = parent
	return s
end

function Theme.Padding(parent: Instance, all: number, horizontal: number?)
	local p = Instance.new("UIPadding")
	p.PaddingTop = UDim.new(0, all)
	p.PaddingBottom = UDim.new(0, all)
	p.PaddingLeft = UDim.new(0, horizontal or all)
	p.PaddingRight = UDim.new(0, horizontal or all)
	p.Parent = parent
	return p
end

-- ไล่สีบน → ล่าง (ทำให้ปุ่ม/แผงดูมีมิติ)
function Theme.Gradient(parent: Instance, top: Color3, bottom: Color3): UIGradient
	local g = Instance.new("UIGradient")
	g.Rotation = 90
	g.Color = ColorSequence.new(top, bottom)
	g.Parent = parent
	return g
end

function Theme.Text(parent: Instance, props: { [string]: any }): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = Theme.Fonts.Bold
	l.TextColor3 = Theme.Colors.Text
	l.TextSize = 18
	l.TextXAlignment = Enum.TextXAlignment.Left
	for key, value in props do
		(l :: any)[key] = value
	end
	l.Parent = parent
	return l
end

function Theme.FormatMoney(amount: number): string
	local text = tostring(math.floor(amount))
	local formatted = text:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return "฿" .. (formatted:gsub("^,", ""))
end

---------------------------------------------------------------------
-- ปุ่ม: ขยายนิดตอนชี้ ยุบตอนกด
---------------------------------------------------------------------

function Theme.AttachHover(button: GuiButton)
	local scale = button:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
	scale.Parent = button
	button.MouseEnter:Connect(function()
		TweenService:Create(scale, QUICK, { Scale = 1.04 }):Play()
	end)
	button.MouseLeave:Connect(function()
		TweenService:Create(scale, QUICK, { Scale = 1 }):Play()
	end)
	button.MouseButton1Down:Connect(function()
		TweenService:Create(scale, QUICK, { Scale = 0.95 }):Play()
	end)
	button.MouseButton1Up:Connect(function()
		TweenService:Create(scale, QUICK, { Scale = 1.04 }):Play()
	end)
end

-- หมายเหตุ: UIGradient ย้อมทั้งพื้นและตัวหนังสือของปุ่ม จึงใช้ gradient แค่ "ขาว → เทาอ่อน" (ทำให้มีมิติ)
-- แล้วใส่สีจริงที่ BackgroundColor3 ตัวหนังสือจะไม่ถูกย้อมจนกลืนกับพื้น
local VARIANTS = {
	primary = { Color = Color3.fromRGB(246, 176, 64), Text = Color3.fromRGB(46, 28, 8), Stroke = Color3.fromRGB(140, 86, 20) },
	secondary = { Color = Color3.fromRGB(78, 67, 58), Text = Theme.Colors.Text, Stroke = Theme.Colors.Stroke },
	success = { Color = Color3.fromRGB(92, 196, 106), Text = Color3.fromRGB(12, 40, 16), Stroke = Color3.fromRGB(40, 110, 52) },
	danger = { Color = Color3.fromRGB(214, 78, 70), Text = Color3.new(1, 1, 1), Stroke = Color3.fromRGB(120, 32, 28) },
}
local BUTTON_SHADE = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(215, 215, 215))

function Theme.Button(parent: Instance?, text: string, variant: string?, size: UDim2?): TextButton
	local style = VARIANTS[variant or "secondary"] or VARIANTS.secondary
	local b = Instance.new("TextButton")
	b.AutoButtonColor = false
	b.Size = size or UDim2.new(1, 0, 0, 42)
	b.BackgroundColor3 = style.Color
	b.Font = Theme.Fonts.Bold
	b.TextSize = 18
	b.TextColor3 = style.Text
	b.Text = text
	Theme.Corner(b, 10)
	local shade = Instance.new("UIGradient")
	shade.Rotation = 90
	shade.Color = BUTTON_SHADE
	shade.Parent = b
	Theme.Stroke(b, style.Stroke, 2)
	Theme.AttachHover(b)
	if parent then
		b.Parent = parent
	end
	return b
end

-- เปลี่ยนสีปุ่ม (เช่น เปลี่ยนเป็นสีแดงตอนเงินไม่พอ)
function Theme.SetButtonVariant(button: TextButton, variant: string)
	local style = VARIANTS[variant] or VARIANTS.secondary
	local stroke = button:FindFirstChildOfClass("UIStroke")
	button.BackgroundColor3 = style.Color
	if stroke then
		stroke.Color = style.Stroke
	end
	button.TextColor3 = style.Text
end

-- ป้ายเล็ก ๆ (badge) เช่น "พื้น", "+10%"
function Theme.Badge(parent: Instance, text: string, color: Color3): TextLabel
	local badge = Theme.Text(parent, {
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 20),
		BackgroundTransparency = 0.2,
		BackgroundColor3 = color,
		TextColor3 = Color3.new(1, 1, 1),
		TextSize = 13,
		Font = Theme.Fonts.Bold,
		Text = text,
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	Theme.Corner(badge, 6)
	Theme.Padding(badge, 0, 7)
	return badge
end

---------------------------------------------------------------------
-- หน้าต่าง (เปิดได้ทีละหน้าต่าง)
---------------------------------------------------------------------

export type Window = {
	Frame: Frame,
	Body: Frame,
	TitleLabel: TextLabel,
	SubtitleLabel: TextLabel,
	Open: (self: Window) -> (),
	Close: (self: Window) -> (),
	Toggle: (self: Window) -> (),
	IsOpen: (self: Window) -> boolean,
	Closed: RBXScriptSignal,
	Opened: RBXScriptSignal,
}

local currentWindow = nil

function Theme.Window(screenGui: ScreenGui, options: { [string]: any }): Window
	local frame = Instance.new("Frame")
	frame.Name = options.Name or "Window"
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.52)
	frame.Size = options.Size or UDim2.fromScale(0.62, 0.7)
	frame.BackgroundColor3 = Theme.Colors.Panel
	frame.Visible = false
	frame.Parent = screenGui
	Theme.Corner(frame, 16)
	Theme.Stroke(frame, Theme.Colors.Stroke, 2)
	Theme.Gradient(frame, Color3.fromRGB(255, 255, 255), Color3.fromRGB(205, 200, 195))
	local constraint = Instance.new("UISizeConstraint")
	constraint.MinSize = options.MinSize or Vector2.new(460, 320)
	constraint.MaxSize = options.MaxSize or Vector2.new(900, 620)
	constraint.Parent = frame
	local scale = Instance.new("UIScale")
	scale.Parent = frame

	-- หัวหน้าต่าง
	local header = Instance.new("Frame")
	header.Name = "Header"
	header.Size = UDim2.new(1, 0, 0, 58)
	header.BackgroundColor3 = Theme.Colors.PanelLight
	header.Parent = frame
	Theme.Corner(header, 16)
	-- ปิดมุมล่างของหัวให้ตรง (ทับด้วยแถบสี่เหลี่ยม)
	local headerFill = Instance.new("Frame")
	headerFill.Size = UDim2.new(1, 0, 0, 16)
	headerFill.Position = UDim2.new(0, 0, 1, -16)
	headerFill.BorderSizePixel = 0
	headerFill.BackgroundColor3 = Theme.Colors.PanelLight
	headerFill.Parent = header
	local accentLine = Instance.new("Frame")
	accentLine.Size = UDim2.new(1, 0, 0, 2)
	accentLine.Position = UDim2.new(0, 0, 1, 0)
	accentLine.BorderSizePixel = 0
	accentLine.BackgroundColor3 = Theme.Colors.AccentDark
	accentLine.Parent = header

	local icon = Theme.Text(header, {
		Size = UDim2.fromOffset(40, 40),
		Position = UDim2.fromOffset(14, 9),
		Text = options.Icon or "",
		TextSize = 28,
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	icon.Name = "Icon"
	local title = Theme.Text(header, {
		Size = UDim2.new(1, -200, 0, 30),
		Position = UDim2.fromOffset(58, 6),
		Font = Theme.Fonts.Title,
		TextSize = 24,
		TextColor3 = Theme.Colors.Accent,
		Text = options.Title or "",
	})
	title.Name = "Title"
	local subtitle = Theme.Text(header, {
		Size = UDim2.new(1, -200, 0, 18),
		Position = UDim2.fromOffset(58, 34),
		Font = Theme.Fonts.Body,
		TextSize = 14,
		TextColor3 = Theme.Colors.Muted,
		Text = options.Subtitle or "",
	})
	subtitle.Name = "Subtitle"

	local close = Theme.Button(header, "X", "danger", UDim2.fromOffset(38, 38))
	close.Name = "Close"
	close.AnchorPoint = Vector2.new(1, 0.5)
	close.Position = UDim2.new(1, -12, 0.5, 0)
	close.TextSize = 20
	close.Font = Theme.Fonts.Title

	local body = Instance.new("Frame")
	body.Name = "Body"
	body.Position = UDim2.fromOffset(16, 72)
	body.Size = UDim2.new(1, -32, 1, -88)
	body.BackgroundTransparency = 1
	body.Parent = frame

	local openedEvent = Instance.new("BindableEvent")
	local closedEvent = Instance.new("BindableEvent")

	local window = {
		Frame = frame,
		Body = body,
		TitleLabel = title,
		SubtitleLabel = subtitle,
		Opened = openedEvent.Event,
		Closed = closedEvent.Event,
	}

	function window:IsOpen(): boolean
		return frame.Visible
	end

	function window:Close()
		if not frame.Visible then
			return
		end
		frame.Visible = false
		if currentWindow == window then
			currentWindow = nil
		end
		closedEvent:Fire()
	end

	function window:Open()
		if currentWindow and currentWindow ~= window then
			currentWindow:Close()
		end
		currentWindow = window
		local wasOpen = frame.Visible
		frame.Visible = true
		if not wasOpen then
			scale.Scale = 0.9
			TweenService:Create(scale, POP, { Scale = 1 }):Play()
			openedEvent:Fire()
		end
	end

	function window:Toggle()
		if frame.Visible then
			window:Close()
		else
			window:Open()
		end
	end

	close.Activated:Connect(function()
		window:Close()
	end)

	return window :: any
end

-- ปิดหน้าต่างที่เปิดอยู่ (เช่น ตอนเข้าโหมดตกแต่ง)
function Theme.CloseAllWindows()
	if currentWindow then
		currentWindow:Close()
	end
end

-- ScrollingFrame ที่ใช้บ่อย
function Theme.Scroll(parent: Instance): ScrollingFrame
	local scroll = Instance.new("ScrollingFrame")
	scroll.Size = UDim2.fromScale(1, 1)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 6
	scroll.ScrollBarImageColor3 = Theme.Colors.AccentDark
	scroll.CanvasSize = UDim2.new()
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.Parent = parent
	return scroll
end

return Theme
