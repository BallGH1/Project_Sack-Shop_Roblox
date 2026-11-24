-- FurnitureBuilder: สร้างโมเดลของตกแต่งร้าน (ใช้ทั้งบน server ของจริง และบน client เป็นเงาตอนเลือกที่วาง/รูปไอคอน)
--
-- โมเดลที่ได้: จุดกึ่งกลางอยู่ที่ (0,0,0) และ PrimaryPart = "Hitbox" (กล่องล่องหนขนาดเท่า def.Size)
--   หน้าของเฟอร์นิเจอร์ = -Z (ลูกค้ายืนดูด้านนี้)
--   Slot1..SlotN  = จุดแขวนเสื้อ (ด้านลายของเสื้อหันไปทาง -Z ของช่อง)
--   BrowsePoint   = จุดที่ลูกค้า NPC ยืนดู

local FurnitureBuilder = {}

local function material(name: string): Enum.Material
	local ok, result = pcall(function()
		return (Enum.Material :: any)[name]
	end)
	return if ok and result then result else Enum.Material.SmoothPlastic
end

local M = {
	Metal = material("Metal"),
	Wood = material("Wood"),
	Glass = material("Glass"),
	Neon = material("Neon"),
	Fabric = material("Fabric"),
	Plastic = Enum.Material.SmoothPlastic,
}

local C = {
	Chrome = Color3.fromRGB(190, 192, 198),
	DarkMetal = Color3.fromRGB(55, 57, 62),
	Wood = Color3.fromRGB(110, 74, 48),
	Gold = Color3.fromRGB(212, 168, 70),
	Glass = Color3.fromRGB(200, 230, 255),
	Felt = Color3.fromRGB(48, 34, 34),
	Light = Color3.fromRGB(255, 236, 200),
}

local function part(model: Model, name: string, size: Vector3, cframe: CFrame, color: Color3, mat: Enum.Material, collide: boolean?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = mat
	p.CanCollide = collide ~= false
	p.CanTouch = false
	p.Parent = model
	return p
end

local function hidden(model: Model, name: string, size: Vector3, cframe: CFrame): Part
	local p = part(model, name, size, cframe, C.Light, M.Plastic, false)
	p.Transparency = 1
	p.CanQuery = false
	return p
end

local function slot(model: Model, index: number, cframe: CFrame)
	local p = hidden(model, "Slot" .. index, Vector3.new(0.5, 2.4, 2.2), cframe)
	p:SetAttribute("SlotIndex", index)
end

---------------------------------------------------------------------
-- แต่ละแบบ
---------------------------------------------------------------------

local builders = {}

-- ราวเหล็กล้อเลื่อน: ราวยาวตามแกน X เสื้อแขวนตั้งฉากกับราว
function builders.ClothesRack(model: Model, size: Vector3)
	local bottom = -size.Y / 2
	for _, x in { -3, 3 } do
		part(model, "Foot", Vector3.new(0.35, 0.25, 2.4), CFrame.new(x, bottom + 0.35, 0), C.DarkMetal, M.Metal)
		for _, z in { -1.05, 1.05 } do
			part(model, "Wheel", Vector3.new(0.3, 0.3, 0.3), CFrame.new(x, bottom + 0.15, z), Color3.new(0.1, 0.1, 0.1), M.Plastic, false)
		end
		part(model, "Upright", Vector3.new(0.25, 6.5, 0.25), CFrame.new(x, bottom + 3.6, 0), C.Chrome, M.Metal)
	end
	part(model, "TopBar", Vector3.new(6.3, 0.22, 0.22), CFrame.new(0, 3, 0), C.Chrome, M.Metal)
	part(model, "LowBar", Vector3.new(6.1, 0.15, 0.15), CFrame.new(0, bottom + 1, 0), C.Chrome, M.Metal)
	for i, x in { -2.25, -0.75, 0.75, 2.25 } do
		-- หมุน 90° ให้ตัวเสื้อตั้งฉากกับราว (ด้านลายหันไปทาง -X ตามแนวราว)
		slot(model, i, CFrame.new(x, 3 - 0.11 - 1.55, 0) * CFrame.Angles(0, math.pi / 2, 0))
	end
	hidden(model, "BrowsePoint", Vector3.one, CFrame.new(0, bottom + 0.5, -3.4))
end

-- ตู้กระจกมีไฟ โชว์ 1 ตัวหันหน้าออก
function builders.DisplayCase(model: Model, size: Vector3)
	local bottom = -size.Y / 2
	part(model, "Plinth", Vector3.new(3.6, 1.2, 2.6), CFrame.new(0, bottom + 0.6, 0), C.Wood, M.Wood)
	part(model, "Plaque", Vector3.new(1.4, 0.35, 0.05), CFrame.new(0, bottom + 0.65, -1.32), C.Gold, M.Metal, false)
	local glass = part(model, "Glass", Vector3.new(3.4, 5.4, 2.4), CFrame.new(0, bottom + 3.9, 0), C.Glass, M.Glass)
	glass.Transparency = 0.75
	for _, x in { -1.62, 1.62 } do
		for _, z in { -1.12, 1.12 } do
			part(model, "Post", Vector3.new(0.15, 5.4, 0.15), CFrame.new(x, bottom + 3.9, z), C.Gold, M.Metal, false)
		end
	end
	part(model, "Cap", Vector3.new(3.6, 0.6, 2.6), CFrame.new(0, size.Y / 2 - 0.3, 0), C.Wood, M.Wood)
	local strip = part(model, "LightStrip", Vector3.new(3, 0.08, 0.3), CFrame.new(0, size.Y / 2 - 0.65, -0.6), C.Light, M.Neon, false)
	local light = Instance.new("SpotLight")
	light.Face = Enum.NormalId.Bottom
	light.Color = C.Light
	light.Brightness = 3
	light.Range = 9
	light.Angle = 70
	light.Parent = strip
	part(model, "Rod", Vector3.new(0.1, 0.9, 0.1), CFrame.new(0, size.Y / 2 - 1.05, 0), C.Gold, M.Metal, false)
	slot(model, 1, CFrame.new(0, 0.35, 0))
	hidden(model, "BrowsePoint", Vector3.one, CFrame.new(0, bottom + 0.5, -3.2))
end

-- กรอบรูปติดผนัง: ด้านหลัง (+Z) แนบผนัง
function builders.WallFrame(model: Model, size: Vector3)
	local w, h, d = size.X, size.Y, size.Z
	part(model, "Backboard", Vector3.new(w - 0.2, h - 0.2, 0.1), CFrame.new(0, 0, d / 2 - 0.05), C.Felt, M.Fabric)
	part(model, "BorderTop", Vector3.new(w, 0.25, d), CFrame.new(0, h / 2 - 0.125, 0), C.Gold, M.Metal)
	part(model, "BorderBottom", Vector3.new(w, 0.25, d), CFrame.new(0, -h / 2 + 0.125, 0), C.Gold, M.Metal)
	part(model, "BorderLeft", Vector3.new(0.25, h - 0.5, d), CFrame.new(-w / 2 + 0.125, 0, 0), C.Gold, M.Metal)
	part(model, "BorderRight", Vector3.new(0.25, h - 0.5, d), CFrame.new(w / 2 - 0.125, 0, 0), C.Gold, M.Metal)
	local glass = part(model, "Glass", Vector3.new(w - 0.5, h - 0.5, 0.05), CFrame.new(0, 0, -d / 2 + 0.05), C.Glass, M.Glass, false)
	glass.Transparency = 0.85
	slot(model, 1, CFrame.new(0, -0.12, 0.05))
	hidden(model, "BrowsePoint", Vector3.one, CFrame.new(0, 0, -4.2))
end

---------------------------------------------------------------------

function FurnitureBuilder.Build(def): Model
	local model = Instance.new("Model")
	model.Name = def.Id

	local hitbox = Instance.new("Part")
	hitbox.Name = "Hitbox"
	hitbox.Size = def.Size
	hitbox.CFrame = CFrame.new()
	hitbox.Transparency = 1
	hitbox.Anchored = true
	hitbox.CanCollide = false
	hitbox.CanTouch = false
	hitbox.CanQuery = true -- ใช้ตรวจการวางทับ + คลิกเลือก
	hitbox.Parent = model
	model.PrimaryPart = hitbox

	local builder = builders[def.Id]
	assert(builder, "FurnitureBuilder: no builder for " .. tostring(def.Id))
	builder(model, def.Size)

	model:SetAttribute("FurnitureType", def.Id)
	model:SetAttribute("PriceBonus", def.PriceBonus)
	return model
end

return FurnitureBuilder
