-- DecorController: โหมดตกแต่งร้าน (ปุ่ม "ตกแต่ง" แถบซ้าย หรือกด B)
--
--   แถบร้านค้าด้านล่าง  : เลือกของ → เข้าโหมดวาง
--   โหมดวาง           : เงาของตามเมาส์ (เขียว = วางได้ / แดง = วางไม่ได้)
--                       คลิกซ้าย = วาง · R = หมุน (ของวางพื้น) · Q = ยกเลิก
--   คลิกของที่วางแล้ว   : ย้าย / ขายคืน
--
-- client แค่แสดงผล + ส่งตำแหน่ง ส่วนการตัดสิน (เงิน, อยู่ในร้าน, ทับของอื่น) ทำซ้ำบน server เสมอ

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("Config"):WaitForChild("GameConfig"))
local Furniture = require(Shared.Config:WaitForChild("Furniture"))
local FurnitureBuilder = require(Shared:WaitForChild("Building"):WaitForChild("FurnitureBuilder"))
local PlacementRules = require(Shared.Building:WaitForChild("PlacementRules"))
local Theme = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("Theme"))
local HudController = require(script.Parent:WaitForChild("HudController"))
local NotificationController = require(script.Parent:WaitForChild("NotificationController"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local DECOR = GameConfig.Decor

local DecorController = {}

local player = Players.LocalPlayer

type Placing = {
	Def: any,
	Ghost: Model,
	Highlight: Highlight,
	Rot: number,
	MoveId: string?,
	Original: Model?,
	Payload: any,
	Valid: boolean,
	Busy: boolean,
}

local gui: ScreenGui
local dock: Frame
local countLabel: TextLabel
local hintBar: Frame
local hintStatus: TextLabel
local contextPanel: Frame
local contextTitle: TextLabel
local removeButton: TextButton
local priceLabels: { [string]: TextLabel } = {}
local setHudActive: (boolean) -> ()

local decorMode = false
local placing: Placing? = nil
local selected: { Model: Model, Id: string, Def: any, Box: SelectionBox }? = nil
local renderConnection: RBXScriptConnection? = nil
local removeConfirmUntil = 0

---------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------

local function getMyPlot(): Model?
	local plots = workspace:FindFirstChild("Plots")
	if not plots then
		return nil
	end
	for _, plot in plots:GetChildren() do
		if plot:GetAttribute("OwnerUserId") == player.UserId then
			return plot
		end
	end
	return nil
end

local function furnitureCount(plot: Model?): number
	local folder = plot and plot:FindFirstChild("Furniture")
	return if folder then #folder:GetChildren() else 0
end

local function money(): number
	return player:GetAttribute("Money") or 0
end

local function updateCount()
	if countLabel then
		countLabel.Text = ("วางแล้ว %d / %d ชิ้น"):format(furnitureCount(getMyPlot()), DECOR.MaxFurniture)
	end
end

local function updatePriceColors()
	for id, label in priceLabels do
		local def = Furniture.Get(id)
		label.TextColor3 = if def and money() >= def.Price then Theme.Colors.Money else Theme.Colors.Danger
	end
end

local function invoke(...): (boolean, string)
	local remote = Remotes:WaitForChild("DecorAction") :: RemoteFunction
	local okCall, ok, message = pcall(remote.InvokeServer, remote, ...)
	if not okCall then
		return false, "เชื่อมต่อ server ไม่สำเร็จ ลองใหม่"
	end
	return ok == true, tostring(message)
end

local function mouseRay(): Ray
	local position = UserInputService:GetMouseLocation()
	return workspace.CurrentCamera:ViewportPointToRay(position.X, position.Y)
end

local function setModelFaded(model: Model?, faded: boolean)
	if not model then
		return
	end
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.LocalTransparencyModifier = if faded then 0.75 else 0
		end
	end
end

---------------------------------------------------------------------
-- โหมดวาง
---------------------------------------------------------------------

local function makeGhost(def): (Model, Highlight)
	local ghost = FurnitureBuilder.Build(def)
	ghost.Name = "DecorGhost"
	for _, d in ghost:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.CastShadow = false
			if d.Transparency < 1 then
				d.Transparency = math.max(d.Transparency, 0.35)
			end
		elseif d:IsA("Light") then
			d.Enabled = false
		end
	end
	local highlight = Instance.new("Highlight")
	highlight.FillTransparency = 0.65
	highlight.OutlineTransparency = 0
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Adornee = ghost
	highlight.Parent = ghost
	ghost.Parent = workspace
	return ghost, highlight
end

-- คำนวณตำแหน่งจากเมาส์ คืน (CFrame, payload, wall) หรือ nil
local function computePlacement(plot: Model, def, rot: number): (CFrame?, any, BasePart?)
	local ray = mouseRay()
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	if def.Surface == "Floor" then
		local area = PlacementRules.GetBuildArea(plot)
		if not area then
			return nil
		end
		params.FilterDescendantsInstances = { area }
		local result = workspace:Raycast(ray.Origin, ray.Direction * 600, params)
		if not result then
			return nil
		end
		local localPos = area.CFrame:PointToObjectSpace(result.Position)
		local payload = { X = PlacementRules.Snap(localPos.X), Z = PlacementRules.Snap(localPos.Z), Rot = rot }
		return PlacementRules.FloorCFrame(area, def, payload.X, payload.Z, rot), payload, nil
	end

	params.FilterDescendantsInstances = PlacementRules.GetWalls(plot)
	local result = workspace:Raycast(ray.Origin, ray.Direction * 600, params)
	if not result then
		return nil
	end
	local wall = result.Instance :: BasePart
	local localPos = wall.CFrame:PointToObjectSpace(result.Position)
	-- ดันให้อยู่ในขอบผนัง จะได้เลื่อนไปชิดมุมง่าย
	local maxU = wall.Size.X / 2 - def.Size.X / 2
	local maxV = wall.Size.Y / 2 - def.Size.Y / 2
	local u = math.clamp(localPos.X, -maxU, maxU)
	local v = math.clamp(localPos.Y, -maxV, maxV)
	local payload = { Wall = wall.Name, U = PlacementRules.Snap(u), V = PlacementRules.Snap(v) }
	return PlacementRules.WallCFrame(wall, def, payload.U, payload.V), payload, wall
end

local function setHint(text: string, ok: boolean)
	hintStatus.Text = text
	hintStatus.TextColor3 = if ok then Theme.Colors.Success else Theme.Colors.Danger
end

local function updatePlacing()
	local state = placing
	if not state then
		return
	end
	local plot = getMyPlot()
	if not plot then
		return
	end
	local cframe, payload, wall = computePlacement(plot, state.Def, state.Rot)
	if not cframe then
		state.Ghost:PivotTo(CFrame.new(0, -500, 0))
		state.Valid = false
		setHint(if state.Def.Surface == "Floor" then "ชี้เมาส์ไปที่พื้นในร้านของคุณ" else "ชี้เมาส์ไปที่ผนังในร้านของคุณ", false)
		return
	end
	state.Ghost:PivotTo(cframe)
	state.Payload = payload

	local ok, reason = PlacementRules.Validate(plot, state.Def, cframe, state.Original, wall)
	if ok and not state.MoveId then
		if money() < state.Def.Price then
			ok, reason = false, "เงินไม่พอ (" .. Theme.FormatMoney(state.Def.Price) .. ")"
		elseif furnitureCount(plot) >= DECOR.MaxFurniture then
			ok, reason = false, ("วางครบ %d ชิ้นแล้ว"):format(DECOR.MaxFurniture)
		end
	end
	state.Valid = ok
	state.Highlight.FillColor = if ok then Theme.Colors.Success else Theme.Colors.Danger
	state.Highlight.OutlineColor = state.Highlight.FillColor
	if ok then
		setHint(if state.MoveId then "ย้ายมาตรงนี้ได้" else "วางได้ · " .. Theme.FormatMoney(state.Def.Price), true)
	else
		setHint("วางไม่ได้: " .. (reason or "ตำแหน่งนี้"), false)
	end
end

local function stopPlacing()
	local state = placing
	if not state then
		return
	end
	placing = nil
	state.Ghost:Destroy()
	setModelFaded(state.Original, false)
	hintBar.Visible = false
	dock.Visible = decorMode
end

local function startPlacing(def, moveId: string?, original: Model?)
	stopPlacing()
	local ghost, highlight = makeGhost(def)
	placing = {
		Def = def,
		Ghost = ghost,
		Highlight = highlight,
		Rot = 0,
		MoveId = moveId,
		Original = original,
		Payload = nil,
		Valid = false,
		Busy = false,
	}
	setModelFaded(original, true)
	dock.Visible = false
	contextPanel.Visible = false
	hintBar.Visible = true
	local rotateButton = hintBar:FindFirstChild("Rotate", true) :: TextButton
	rotateButton.Visible = def.Surface == "Floor"
end

local function confirmPlacement()
	local state = placing
	if not state or not state.Valid or state.Busy or not state.Payload then
		return
	end
	state.Busy = true
	local ok, message
	if state.MoveId then
		ok, message = invoke("Move", state.MoveId, state.Payload)
	else
		ok, message = invoke("Place", state.Def.Id, state.Payload)
	end
	state.Busy = false
	NotificationController:Show(message, if ok then "success" else "error")
	if ok and placing == state then
		stopPlacing()
		task.delay(0.2, updateCount)
	end
end

---------------------------------------------------------------------
-- เลือกของที่วางแล้ว (ย้าย / ขายคืน)
---------------------------------------------------------------------

local function clearSelection()
	if selected then
		selected.Box:Destroy()
		selected = nil
	end
	contextPanel.Visible = false
end

local function selectModel(model: Model)
	clearSelection()
	local def = Furniture.Get(model:GetAttribute("FurnitureType") or "")
	local id = model:GetAttribute("FurnitureId")
	if not def or not id then
		return
	end
	local box = Instance.new("SelectionBox")
	box.Adornee = model
	box.Color3 = Theme.Colors.Accent
	box.LineThickness = 0.06
	box.SurfaceTransparency = 0.85
	box.SurfaceColor3 = Theme.Colors.Accent
	box.Parent = gui
	selected = { Model = model, Id = id, Def = def, Box = box }

	contextTitle.Text = def.Icon .. "  " .. def.DisplayName
	removeButton.Text = "ขายคืน " .. Theme.FormatMoney(math.floor(def.Price * DECOR.RefundRate))
	Theme.SetButtonVariant(removeButton, "danger")
	removeConfirmUntil = 0
	contextPanel.Visible = true
end

local function trySelectUnderMouse()
	local plot = getMyPlot()
	local folder = plot and plot:FindFirstChild("Furniture")
	if not folder then
		return
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { folder }
	local ray = mouseRay()
	local result = workspace:Raycast(ray.Origin, ray.Direction * 600, params)
	if not result then
		clearSelection()
		return
	end
	local instance: Instance = result.Instance
	while instance.Parent and instance.Parent ~= folder do
		instance = instance.Parent
	end
	if instance:IsA("Model") then
		selectModel(instance)
	end
end

---------------------------------------------------------------------
-- เปิด/ปิดโหมดตกแต่ง
---------------------------------------------------------------------

local function setDecorMode(on: boolean)
	if decorMode == on then
		return
	end
	decorMode = on
	if on then
		Theme.CloseAllWindows()
		updateCount()
		updatePriceColors()
		dock.Visible = true
		renderConnection = RunService.RenderStepped:Connect(updatePlacing)
	else
		stopPlacing()
		clearSelection()
		dock.Visible = false
		if renderConnection then
			renderConnection:Disconnect()
			renderConnection = nil
		end
	end
	setHudActive(on)
end

---------------------------------------------------------------------
-- UI
---------------------------------------------------------------------

local function makePreview(def, parent: GuiObject)
	local viewport = Instance.new("ViewportFrame")
	viewport.Size = UDim2.new(1, -12, 0, 86)
	viewport.Position = UDim2.fromOffset(6, 6)
	viewport.BackgroundColor3 = Theme.Colors.Backdrop
	viewport.BackgroundTransparency = 0.3
	viewport.Ambient = Color3.fromRGB(190, 185, 180)
	viewport.LightColor = Color3.fromRGB(255, 240, 220)
	viewport.LightDirection = Vector3.new(-1, -1.5, 1)
	viewport.Parent = parent
	Theme.Corner(viewport, 8)

	local model = FurnitureBuilder.Build(def)
	model.Parent = viewport
	local camera = Instance.new("Camera")
	camera.FieldOfView = 35
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	local radius = def.Size.Magnitude / 2
	local distance = radius / math.tan(math.rad(17.5)) * 1.05
	local direction = Vector3.new(0.55, 0.3, -1).Unit -- มองจากด้านหน้า (-Z) เฉียง ๆ
	camera.CFrame = CFrame.lookAt(direction * distance, Vector3.zero)
end

local function buildDock()
	dock = Instance.new("Frame")
	dock.Name = "DecorDock"
	dock.AnchorPoint = Vector2.new(0.5, 1)
	dock.Position = UDim2.new(0.5, 0, 1, -18)
	dock.Size = UDim2.fromOffset(#Furniture.List * 196 + 32, 262)
	dock.BackgroundColor3 = Theme.Colors.Panel
	dock.Visible = false
	dock.Parent = gui
	Theme.Corner(dock, 16)
	Theme.Stroke(dock, Theme.Colors.Stroke, 2)
	Theme.Gradient(dock, Color3.fromRGB(255, 255, 255), Color3.fromRGB(205, 200, 195))

	Theme.Text(dock, {
		Position = UDim2.fromOffset(16, 10),
		Size = UDim2.new(0.6, 0, 0, 28),
		Font = Theme.Fonts.Title,
		TextSize = 22,
		TextColor3 = Theme.Colors.Accent,
		Text = "🔨 ตกแต่งร้าน",
	})
	countLabel = Theme.Text(dock, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -60, 0, 14),
		Size = UDim2.new(0.4, 0, 0, 22),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = Theme.Colors.Muted,
		TextSize = 15,
		Text = "",
	})
	local close = Theme.Button(dock, "X", "danger", UDim2.fromOffset(34, 34))
	close.Font = Theme.Fonts.Title
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -12, 0, 8)
	close.Activated:Connect(function()
		setDecorMode(false)
	end)

	local row = Instance.new("Frame")
	row.Position = UDim2.fromOffset(16, 48)
	row.Size = UDim2.new(1, -32, 0, 178)
	row.BackgroundTransparency = 1
	row.Parent = dock
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, 12)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = row

	for index, def in Furniture.List do
		local card = Instance.new("TextButton")
		card.Name = def.Id
		card.LayoutOrder = index
		card.AutoButtonColor = false
		card.Text = ""
		card.Size = UDim2.fromOffset(184, 178)
		card.BackgroundColor3 = Theme.Colors.PanelLight
		card.Parent = row
		Theme.Corner(card, 12)
		Theme.Stroke(card, Theme.Colors.Stroke, 1.5)
		Theme.AttachHover(card)
		makePreview(def, card)

		Theme.Text(card, {
			Position = UDim2.fromOffset(10, 96),
			Size = UDim2.new(1, -20, 0, 22),
			TextSize = 16,
			Text = def.Icon .. " " .. def.DisplayName,
		})
		local badges = Instance.new("Frame")
		badges.Position = UDim2.fromOffset(10, 120)
		badges.Size = UDim2.new(1, -20, 0, 20)
		badges.BackgroundTransparency = 1
		badges.Parent = card
		local badgeRow = Instance.new("UIListLayout")
		badgeRow.FillDirection = Enum.FillDirection.Horizontal
		badgeRow.Padding = UDim.new(0, 4)
		badgeRow.SortOrder = Enum.SortOrder.LayoutOrder
		badgeRow.Parent = badges
		Theme.Badge(badges, if def.Surface == "Floor" then "วางพื้น" else "ติดผนัง", Color3.fromRGB(90, 110, 150)).LayoutOrder = 1
		Theme.Badge(badges, def.Slots .. " ช่อง", Color3.fromRGB(110, 90, 70)).LayoutOrder = 2
		if def.PriceBonus > 0 then
			Theme.Badge(badges, ("+%d%% ราคา"):format(math.floor(def.PriceBonus * 100 + 0.5)), Color3.fromRGB(60, 140, 80)).LayoutOrder = 3
		end
		priceLabels[def.Id] = Theme.Text(card, {
			Position = UDim2.fromOffset(10, 146),
			Size = UDim2.new(1, -20, 0, 24),
			Font = Theme.Fonts.Title,
			TextSize = 20,
			TextColor3 = Theme.Colors.Money,
			Text = Theme.FormatMoney(def.Price),
		})

		card.Activated:Connect(function()
			clearSelection()
			startPlacing(def)
		end)
	end

	Theme.Text(dock, {
		Position = UDim2.fromOffset(16, 232),
		Size = UDim2.new(1, -32, 0, 20),
		TextSize = 13,
		Font = Theme.Fonts.Body,
		TextColor3 = Theme.Colors.Muted,
		Text = "💡 คลิกของที่วางไว้แล้วในร้าน เพื่อย้ายหรือขายคืน",
	})
end

local function buildHintBar()
	hintBar = Instance.new("Frame")
	hintBar.Name = "PlacementHint"
	hintBar.AnchorPoint = Vector2.new(0.5, 1)
	hintBar.Position = UDim2.new(0.5, 0, 1, -18)
	hintBar.Size = UDim2.fromOffset(560, 96)
	hintBar.BackgroundColor3 = Theme.Colors.Panel
	hintBar.Visible = false
	hintBar.Parent = gui
	Theme.Corner(hintBar, 14)
	Theme.Stroke(hintBar, Theme.Colors.Stroke, 2)

	hintStatus = Theme.Text(hintBar, {
		Position = UDim2.fromOffset(16, 10),
		Size = UDim2.new(1, -32, 0, 24),
		Font = Theme.Fonts.Title,
		TextSize = 18,
		Text = "",
	})
	Theme.Text(hintBar, {
		Position = UDim2.fromOffset(16, 36),
		Size = UDim2.new(1, -32, 0, 18),
		Font = Theme.Fonts.Body,
		TextSize = 14,
		TextColor3 = Theme.Colors.Muted,
		Text = "คลิกซ้าย: วาง   ·   R: หมุน   ·   Q: ยกเลิก",
	})

	local buttons = Instance.new("Frame")
	buttons.Position = UDim2.fromOffset(16, 58)
	buttons.Size = UDim2.new(1, -32, 0, 30)
	buttons.BackgroundTransparency = 1
	buttons.Parent = hintBar
	local row = Instance.new("UIListLayout")
	row.FillDirection = Enum.FillDirection.Horizontal
	row.HorizontalAlignment = Enum.HorizontalAlignment.Right
	row.Padding = UDim.new(0, 8)
	row.Parent = buttons

	local rotate = Theme.Button(buttons, "🔄 หมุน (R)", "secondary", UDim2.fromOffset(120, 30))
	rotate.Name = "Rotate"
	rotate.TextSize = 15
	rotate.Activated:Connect(function()
		if placing then
			placing.Rot = (placing.Rot + 1) % 4
		end
	end)
	local cancel = Theme.Button(buttons, "ยกเลิก (Q)", "danger", UDim2.fromOffset(120, 30))
	cancel.TextSize = 15
	cancel.Activated:Connect(stopPlacing)
end

local function buildContextPanel()
	contextPanel = Instance.new("Frame")
	contextPanel.Name = "FurnitureActions"
	contextPanel.AnchorPoint = Vector2.new(0.5, 1)
	contextPanel.Position = UDim2.new(0.5, 0, 1, -296)
	contextPanel.Size = UDim2.fromOffset(440, 104)
	contextPanel.BackgroundColor3 = Theme.Colors.Panel
	contextPanel.Visible = false
	contextPanel.Parent = gui
	Theme.Corner(contextPanel, 14)
	Theme.Stroke(contextPanel, Theme.Colors.Accent, 2)

	contextTitle = Theme.Text(contextPanel, {
		Position = UDim2.fromOffset(16, 10),
		Size = UDim2.new(1, -32, 0, 26),
		Font = Theme.Fonts.Title,
		TextSize = 20,
		TextColor3 = Theme.Colors.Accent,
		Text = "",
	})

	local buttons = Instance.new("Frame")
	buttons.Position = UDim2.fromOffset(16, 52)
	buttons.Size = UDim2.new(1, -32, 0, 40)
	buttons.BackgroundTransparency = 1
	buttons.Parent = contextPanel
	local row = Instance.new("UIListLayout")
	row.FillDirection = Enum.FillDirection.Horizontal
	row.Padding = UDim.new(0, 8)
	row.Parent = buttons

	local moveButton = Theme.Button(buttons, "✋ ย้าย", "primary", UDim2.fromOffset(120, 40))
	moveButton.Activated:Connect(function()
		if selected then
			local s = selected
			clearSelection()
			startPlacing(s.Def, s.Id, s.Model)
		end
	end)

	removeButton = Theme.Button(buttons, "ขายคืน", "danger", UDim2.fromOffset(170, 40))
	removeButton.Activated:Connect(function()
		if not selected then
			return
		end
		-- กดสองครั้งเพื่อยืนยัน
		if os.clock() > removeConfirmUntil then
			removeConfirmUntil = os.clock() + 3
			removeButton.Text = "กดอีกครั้งเพื่อยืนยัน"
			return
		end
		local id = selected.Id
		clearSelection()
		local ok, message = invoke("Remove", id)
		NotificationController:Show(message, if ok then "success" else "error")
		task.delay(0.2, updateCount)
	end)

	local cancel = Theme.Button(buttons, "ยกเลิก", "secondary", UDim2.fromOffset(100, 40))
	cancel.Activated:Connect(clearSelection)
end

---------------------------------------------------------------------
-- Start
---------------------------------------------------------------------

function DecorController:Start()
	gui = Instance.new("ScreenGui")
	gui.Name = "DecorGui"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 8
	gui.Parent = player:WaitForChild("PlayerGui")

	buildDock()
	buildHintBar()
	buildContextPanel()

	local _, setActive = HudController:AddButton(2, "🔨", "ตกแต่ง", Enum.KeyCode.B, function()
		setDecorMode(not decorMode)
	end)
	setHudActive = setActive

	player:GetAttributeChangedSignal("Money"):Connect(updatePriceColors)

	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if not decorMode then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			if gameProcessed then
				return -- คลิกโดน UI
			end
			if placing then
				confirmPlacement()
			else
				trySelectUnderMouse()
			end
		elseif not gameProcessed and placing then
			if input.KeyCode == Enum.KeyCode.R and placing.Def.Surface == "Floor" then
				placing.Rot = (placing.Rot + 1) % 4
			elseif input.KeyCode == Enum.KeyCode.Q or input.KeyCode == Enum.KeyCode.X then
				stopPlacing()
			end
		end
	end)

	-- ตายแล้วเกิดใหม่: ยกเลิกการวางค้าง
	player.CharacterAdded:Connect(function()
		stopPlacing()
	end)
end

return DecorController
