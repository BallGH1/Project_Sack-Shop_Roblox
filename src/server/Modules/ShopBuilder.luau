-- ShopBuilder: สร้าง "ร้านเริ่มต้น" แบบเพิงสังกะสีโทรม ๆ ด้วยโค้ด (ทุกล็อตหน้าตาเหมือนกัน)
--
-- พิกัดทั้งหมดเป็นแบบ local ของล็อต:
--   ล็อตขนาด 70 x 70, พื้น Base สูงถึง y = 1
--   -Z = หน้าร้าน (หันเข้าหาโรงงานกลางแมพ), +Z = หลังร้าน, X = ซ้าย/ขวา
--   ตัวร้าน (ข้างใน) กว้าง 40 ลึก 30 อยู่ที่ z = -5 ถึง 25, หน้าลานว่างไว้ที่ z = -35 ถึง -5
--
-- อยากแก้มือใน Studio: กด Play → copy Workspace.Plots → Stop → paste ลง Workspace → Ctrl+S
-- ถ้ามี Workspace.Plots อยู่แล้ว PlotService จะใช้ของคุณแทนการสร้างด้วยโค้ด

local ShopBuilder = {}

-- Material บางตัวใหม่ ถ้า Studio รุ่นนั้นไม่มีจะใช้ตัวสำรองแทน
local function material(name: string, fallback: Enum.Material): Enum.Material
	local ok, result = pcall(function()
		return (Enum.Material :: any)[name]
	end)
	return if ok and result then result else fallback
end

-- ทุกตัวผ่าน material() เพื่อกันชื่อผิดทำให้ทั้งเกมพัง
local M = {
	Concrete = material("Concrete", Enum.Material.SmoothPlastic),
	Corrugated = material("Metal", Enum.Material.SmoothPlastic), -- สังกะสี
	Wood = material("Wood", Enum.Material.SmoothPlastic),
	Planks = material("WoodPlanks", Enum.Material.SmoothPlastic),
	Metal = material("Metal", Enum.Material.SmoothPlastic),
	Rust = material("CorrodedMetal", Enum.Material.SmoothPlastic), -- เหล็กขึ้นสนิม
	Fabric = material("Fabric", Enum.Material.SmoothPlastic),
	Plastic = Enum.Material.SmoothPlastic,
	Ground = material("Ground", Enum.Material.SmoothPlastic),
	Neon = material("Neon", Enum.Material.SmoothPlastic),
	Cardboard = material("Cardboard", Enum.Material.SmoothPlastic),
	Rubber = material("Rubber", Enum.Material.SmoothPlastic),
}

local C = {
	Yard = Color3.fromRGB(112, 106, 97), -- ลานปูนเก่า
	Floor = Color3.fromRGB(138, 128, 112), -- พื้นในร้าน
	Stain = Color3.fromRGB(70, 64, 56), -- คราบ / รอยร้าว
	Path = Color3.fromRGB(125, 118, 104),
	WallRust = Color3.fromRGB(140, 86, 55),
	WallBlue = Color3.fromRGB(96, 116, 130),
	WallGreen = Color3.fromRGB(108, 118, 98),
	Roof = Color3.fromRGB(118, 94, 74),
	RoofPatch = Color3.fromRGB(165, 165, 155),
	Shutter = Color3.fromRGB(128, 128, 122),
	Tarp = Color3.fromRGB(70, 115, 160), -- ผ้าใบฟ้าซีด
	Wood = Color3.fromRGB(150, 115, 80),
	Plywood = Color3.fromRGB(205, 180, 135),
	Pipe = Color3.fromRGB(105, 100, 95),
	Cardboard = Color3.fromRGB(170, 130, 85),
	Tire = Color3.fromRGB(30, 30, 30),
	Trash = Color3.fromRGB(25, 25, 28),
	Chair = Color3.fromRGB(215, 210, 195),
	Tape = Color3.fromRGB(230, 190, 40),
	Bulb = Color3.fromRGB(255, 214, 150),
}

local rad = math.rad

-- สร้าง Part ที่ตำแหน่ง local (เทียบกับ origin ของล็อต)
local function part(
	parent: Instance,
	origin: CFrame,
	name: string,
	size: Vector3,
	localCFrame: CFrame,
	color: Color3,
	mat: Enum.Material,
	extra: { [string]: any }?
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Size = size
	p.CFrame = origin * localCFrame
	p.Color = color
	p.Material = mat
	if extra then
		for key, value in extra do
			(p :: any)[key] = value
		end
	end
	p.Parent = parent
	return p
end

local function at(x: number, y: number, z: number): CFrame
	return CFrame.new(x, y, z)
end

local function rot(x: number, y: number, z: number, rx: number?, ry: number?, rz: number?): CFrame
	return CFrame.new(x, y, z) * CFrame.Angles(rad(rx or 0), rad(ry or 0), rad(rz or 0))
end

local NO_COLLIDE = { CanCollide = false, CanQuery = false, CanTouch = false }

---------------------------------------------------------------------
-- ส่วนต่าง ๆ ของร้าน
---------------------------------------------------------------------

local function buildGround(model: Model, o: CFrame, size: number): Part
	local base = part(model, o, "Base", Vector3.new(size, 1, size), at(0, 0.5, 0), C.Yard, M.Concrete)

	local decor = Instance.new("Model")
	decor.Name = "GroundDecor"
	decor.Parent = model

	-- ทางเดินสึก ๆ จากหน้าลานเข้าร้าน
	part(decor, o, "WornPath", Vector3.new(10, 0.05, 30), at(0, 1.03, -20), C.Path, M.Ground, NO_COLLIDE)
	-- คราบน้ำมัน / คราบดิน
	part(decor, o, "Stain", Vector3.new(6, 0.05, 4), rot(-16, 1.03, -22, 0, 25, 0), C.Stain, M.Ground, NO_COLLIDE)
	part(decor, o, "Stain", Vector3.new(4, 0.05, 3), rot(18, 1.03, -14, 0, -40, 0), C.Stain, M.Ground, NO_COLLIDE)
	-- รอยร้าวพื้น
	part(decor, o, "Crack", Vector3.new(0.2, 0.05, 9), rot(-6, 1.04, -28, 0, 30, 0), C.Stain, M.Concrete, NO_COLLIDE)
	part(decor, o, "Crack", Vector3.new(0.2, 0.05, 6), rot(10, 1.04, -9, 0, -55, 0), C.Stain, M.Concrete, NO_COLLIDE)
	part(decor, o, "Crack", Vector3.new(0.15, 0.05, 5), rot(26, 1.04, 2, 0, 10, 0), C.Stain, M.Concrete, NO_COLLIDE)

	return base
end

local function buildBuilding(model: Model, o: CFrame)
	local b = Instance.new("Model")
	b.Name = "Building"
	b.Parent = model

	-- พื้นในร้าน (top y = 1.4)
	part(b, o, "Floor", Vector3.new(40, 0.4, 30), at(0, 1.2, 10), C.Floor, M.Concrete)
	part(b, o, "FloorStain", Vector3.new(5, 0.03, 3), rot(8, 1.42, 4, 0, 15, 0), C.Stain, M.Concrete, NO_COLLIDE)

	-- ผนังสังกะสีหลายสี เหมือนเอามาต่อ ๆ กัน (สูงถึง y = 13.4)
	part(b, o, "WallBack", Vector3.new(40, 12, 1), at(0, 7.4, 25.5), C.WallRust, M.Corrugated)
	part(b, o, "WallLeftA", Vector3.new(1, 12, 17), at(-20.5, 7.4, 3.5), C.WallRust, M.Corrugated)
	part(b, o, "WallLeftB", Vector3.new(1, 11.4, 14), at(-20.5, 7.1, 19), C.WallBlue, M.Corrugated)
	part(b, o, "WallRight", Vector3.new(1, 12, 31), at(20.5, 7.4, 10.5), C.WallGreen, M.Corrugated)
	-- แผ่นปะสนิมบนผนัง
	part(b, o, "WallPatch", Vector3.new(0.2, 4, 5), rot(21.1, 5, 14, 0, 0, 4), C.WallRust, M.Rust, NO_COLLIDE)
	part(b, o, "WallPatch", Vector3.new(6, 3.5, 0.2), rot(-8, 9, 26.1, 0, 0, -6), C.WallBlue, M.Rust, NO_COLLIDE)

	-- เสาหน้าร้าน
	part(b, o, "PostLeft", Vector3.new(1, 13.2, 1), at(-20.5, 8, -5.5), C.Pipe, M.Rust)
	part(b, o, "PostRight", Vector3.new(1, 13.2, 1), at(20.5, 8, -5.5), C.Pipe, M.Rust)

	-- กล่องม้วนประตูเหล็ก + ประตูม้วนที่ดึงลงมาค้างครึ่ง ๆ (ช่องเข้าสูง ~6.7 studs)
	part(b, o, "ShutterBox", Vector3.new(41, 2, 1.6), at(0, 12.6, -5.6), C.Shutter, M.Rust)
	part(b, o, "Shutter", Vector3.new(39, 3.5, 0.2), rot(0, 9.85, -5.2, 0, 0, 0.8), C.Shutter, M.Corrugated)

	-- หลังคาสังกะสีลาดไปด้านหลัง + แผ่นปะ
	part(b, o, "Roof", Vector3.new(44, 0.3, 34), rot(0, 13.9, 10.5, 3, 0, 0), C.Roof, M.Corrugated)
	part(b, o, "RoofPatch", Vector3.new(10, 0.1, 8), rot(-9, 14.56, 2, 3, 8, 0), C.RoofPatch, M.Corrugated)
	part(b, o, "RoofPatch", Vector3.new(7, 0.1, 6), rot(12, 13.72, 18, 3, -5, 0), C.WallRust, M.Rust)

	-- กันสาดผ้าใบหน้าร้าน + เสาไม้ (เสาขวาเอียงนิด ๆ)
	part(b, o, "Awning", Vector3.new(30, 0.15, 7.9), rot(0, 11, -10.2, -14.7, 0, 0.6), C.Tarp, M.Fabric, NO_COLLIDE)
	part(b, o, "AwningPoleL", Vector3.new(0.4, 9, 0.4), at(-14.5, 5.5, -14), C.Wood, M.Wood)
	part(b, o, "AwningPoleR", Vector3.new(0.4, 9, 0.4), rot(14.5, 5.5, -14, 0, 0, 4), C.Wood, M.Wood)
end

local function buildSign(model: Model, o: CFrame)
	-- ป้ายไม้อัดเขียนมือ ตั้งอยู่บนหลังคาด้านหน้า เอียงนิดหน่อย
	local sign = part(model, o, "Sign", Vector3.new(20, 4.5, 0.4), rot(0, 17.3, -5.8, 0, 0, 2.5), C.Plywood, M.Wood)
	part(model, o, "SignLeg", Vector3.new(0.3, 3, 0.3), at(-7, 15.3, -5.4), C.Wood, M.Wood)
	part(model, o, "SignLeg", Vector3.new(0.3, 3, 0.3), at(7, 15.6, -5.4), C.Wood, M.Wood)

	local gui = Instance.new("SurfaceGui")
	gui.Name = "SignGui"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.Parent = sign

	local label = Instance.new("TextLabel")
	label.Name = "OwnerLabel"
	label.Size = UDim2.fromScale(0.92, 0.85)
	label.Position = UDim2.fromScale(0.04, 0.075)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(140, 30, 30) -- สีแดงเหมือนทาสีมือ
	local fontOk = pcall(function()
		label.Font = Enum.Font.PermanentMarker
	end)
	if not fontOk then
		label.Font = Enum.Font.Cartoon
	end
	label.Parent = gui
end

local function buildInterior(model: Model, o: CFrame)
	local props = Instance.new("Model")
	props.Name = "Props"
	props.Parent = model

	-- หลอดไฟดวงเดียวห้อยกลางร้าน
	part(props, o, "BulbCord", Vector3.new(0.1, 3.6, 0.1), at(0, 12.2, 8), Color3.new(0, 0, 0), M.Plastic, NO_COLLIDE)
	local bulb = part(props, o, "Bulb", Vector3.new(0.8, 0.8, 0.8), at(0, 10.2, 8), C.Bulb, M.Neon, NO_COLLIDE)
	bulb.Shape = Enum.PartType.Ball
	local light = Instance.new("PointLight")
	light.Color = C.Bulb
	light.Range = 28
	light.Brightness = 1.5
	light.Shadows = true
	light.Parent = bulb

	-- เคาน์เตอร์ทำจากพาเลทซ้อนกัน + ไม้อัดแผ่นบน + กล่องเก็บเงินสังกะสี
	part(props, o, "PalletLow", Vector3.new(6, 1, 4), at(-14, 1.9, 19), C.Wood, M.Planks)
	part(props, o, "PalletHigh", Vector3.new(6, 1, 4), rot(-14, 2.9, 19, 0, 4, 0), C.Wood, M.Planks)
	part(props, o, "CounterTop", Vector3.new(6.5, 0.2, 4.5), rot(-14, 3.5, 19, 0, 2, 0), C.Plywood, M.Wood)
	part(props, o, "CashBox", Vector3.new(1.5, 0.8, 1), rot(-13, 4, 19, 0, -10, 0), Color3.fromRGB(60, 90, 70), M.Rust)

	-- เก้าอี้พลาสติกเก่า ๆ (หันเอียง)
	local chair = o * rot(-10, 1.4, 14.5, 0, 20, 0)
	part(props, chair, "ChairSeat", Vector3.new(2, 0.3, 2), at(0, 1.8, 0), C.Chair, M.Plastic)
	part(props, chair, "ChairBack", Vector3.new(2, 2, 0.3), at(0, 2.9, 0.9), C.Chair, M.Plastic)
	for _, offset in { Vector2.new(-0.85, -0.85), Vector2.new(0.85, -0.85), Vector2.new(-0.85, 0.85), Vector2.new(0.85, 0.85) } do
		part(props, chair, "ChairLeg", Vector3.new(0.2, 1.7, 0.2), at(offset.X, 0.85, offset.Y), C.Chair, M.Plastic)
	end

	-- กองลังกระดาษมุมหลังขวา
	part(props, o, "Box", Vector3.new(3, 2.5, 3), at(16, 2.65, 22), C.Cardboard, M.Cardboard)
	part(props, o, "Box", Vector3.new(2.6, 2.2, 2.6), rot(16.3, 5, 21.8, 0, 12, 0), C.Cardboard, M.Cardboard)
	part(props, o, "Box", Vector3.new(3, 2, 2.5), rot(12.3, 2.4, 22.3, 0, 30, 0), C.Cardboard, M.Cardboard)

	-- ราวท่อเหล็กเก่าชิดผนังขวา (ยังว่าง ไว้แขวนเสื้อขายใน Phase 1 ข้อ 6)
	local rack = Instance.new("Model")
	rack.Name = "OldRack"
	rack.Parent = props
	part(rack, o, "RackPole", Vector3.new(0.3, 6, 0.3), at(17.5, 4.4, 4), C.Pipe, M.Rust)
	part(rack, o, "RackPole", Vector3.new(0.3, 6, 0.3), at(17.5, 4.4, 14), C.Pipe, M.Rust)
	part(rack, o, "RackBar", Vector3.new(0.3, 0.3, 10.3), at(17.5, 7.4, 9), C.Pipe, M.Rust)

	-- ของรก ๆ ที่ลานหน้าร้าน: ยางรถเก่า ถุงขยะ พาเลทพิงผนัง
	local tireUpright = CFrame.Angles(0, 0, rad(90)) -- Cylinder แกนอยู่ที่ X ต้องหมุนให้ตั้ง
	part(props, o, "Tire", Vector3.new(1.2, 3, 3), at(-26, 1.6, -10) * tireUpright, C.Tire, M.Rubber, { Shape = Enum.PartType.Cylinder })
	part(props, o, "Tire", Vector3.new(1.2, 3, 3), at(-25.7, 2.8, -10.3) * tireUpright, C.Tire, M.Rubber, { Shape = Enum.PartType.Cylinder })
	part(props, o, "TrashBag", Vector3.new(2.2, 2.2, 2.2), at(24, 2, -3), C.Trash, M.Plastic, { Shape = Enum.PartType.Ball })
	part(props, o, "TrashBag", Vector3.new(1.8, 1.8, 1.8), at(23, 1.8, -1.2), C.Trash, M.Plastic, { Shape = Enum.PartType.Ball })
	part(props, o, "LeaningPallet", Vector3.new(4, 0.5, 5), rot(-22.4, 3.3, 15, 0, 0, -70), C.Wood, M.Planks)
end

local function buildFixtures(model: Model, o: CFrame)
	-- จุดคงที่ที่ระบบอื่นจะใช้ (ระบบค้นหาด้วยชื่อ ห้ามเปลี่ยนชื่อ)
	local fixtures = Instance.new("Folder")
	fixtures.Name = "Fixtures"
	fixtures.Parent = model

	-- โซนเปิดกระสอบ (Phase 1 ข้อ 5): กรอบเทปเหลืองบนพื้น
	local zoneCenter = at(0, 1.5, 17)
	part(fixtures, o, "SackOpenZone", Vector3.new(8, 0.2, 8), zoneCenter, C.Tape, M.Plastic, {
		Transparency = 1,
		CanCollide = false,
		CanTouch = false,
	})
	local tape = { CanCollide = false, CanQuery = false, CanTouch = false }
	part(fixtures, o, "Tape", Vector3.new(8, 0.05, 0.5), at(0, 1.43, 13.25), C.Tape, M.Plastic, tape)
	part(fixtures, o, "Tape", Vector3.new(8, 0.05, 0.5), rot(0.2, 1.43, 20.75, 0, 1.5, 0), C.Tape, M.Plastic, tape)
	part(fixtures, o, "Tape", Vector3.new(0.5, 0.05, 7), at(-3.75, 1.43, 17), C.Tape, M.Plastic, tape)
	part(fixtures, o, "Tape", Vector3.new(0.5, 0.05, 6), at(3.75, 1.43, 16.5), C.Tape, M.Plastic, tape) -- เทปลอกไปนิดนึง
end

---------------------------------------------------------------------
-- Public
---------------------------------------------------------------------

-- สร้างล็อต 1 ล็อต: origin = ตำแหน่ง/ทิศของล็อต (-Z หันหาโรงงาน)
function ShopBuilder.Build(plotId: number, origin: CFrame, size: number): Model
	local model = Instance.new("Model")
	model.Name = "Plot" .. plotId

	local base = buildGround(model, origin, size)
	buildBuilding(model, origin)
	buildSign(model, origin)
	buildInterior(model, origin)
	buildFixtures(model, origin)

	-- จุดเกิด: หน้าลาน หันหน้าเข้าหาร้านตัวเอง
	part(model, origin, "SpawnPoint", Vector3.new(4, 1, 4), rot(0, 1.5, -(size / 2 - 9), 0, 180, 0), C.Yard, M.Plastic, {
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
	})

	model.PrimaryPart = base
	model:SetAttribute("PlotId", plotId)
	return model
end

return ShopBuilder
