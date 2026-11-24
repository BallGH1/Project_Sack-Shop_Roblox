-- CityBuilder: สร้างฉากเมืองรอบโรงงานด้วยโค้ด (ทุกเซิร์ฟเวอร์ได้เมืองหน้าตาเดียวกันเพราะใช้ seed คงที่)
--
-- ผังเมือง (มองจากด้านบน, โรงงานอยู่ตรงกลาง 0,0)
--   ลานปูนรอบโรงงาน → ถนนวงแหวนใน → ถนนหลัก 6 เส้นวิ่งออกไปหาหน้าร้านแต่ละร้าน
--   → ถนนวงแหวนนอกเชื่อมทุกร้าน → ร้าน 6 ร้าน → ตึกสูงรอบนอกเป็นฉากหลัง
--   ระหว่างถนนหลักแต่ละคู่ = 1 โซน สลับกันระหว่าง "สวน" กับ "ย่านตึก"
--
-- ถ้าอยากแก้มือ: Play → copy Workspace.City → Stop → paste ลง Workspace → Ctrl+S
-- (ถ้ามี Workspace.City อยู่แล้ว WorldService จะไม่สร้างใหม่)

local CityBuilder = {}

export type Options = {
	GroundY: number,
	PlotRadius: number,
	PlotSize: number,
	PlotCount: number,
	Seed: number?,
}

local TAU = math.pi * 2

---------------------------------------------------------------------
-- วัสดุ / สี
---------------------------------------------------------------------

local function material(name: string): Enum.Material
	local ok, result = pcall(function()
		return (Enum.Material :: any)[name]
	end)
	return if ok and result then result else Enum.Material.SmoothPlastic
end

local M = {
	Asphalt = material("Asphalt"),
	Pavement = material("Pavement"),
	Concrete = material("Concrete"),
	Glass = material("Glass"),
	Grass = material("Grass"),
	Sand = material("Sand"),
	Wood = material("Wood"),
	Planks = material("WoodPlanks"),
	Metal = material("Metal"),
	Neon = material("Neon"),
	Brick = material("Brick"),
	Plastic = Enum.Material.SmoothPlastic,
}

local C = {
	Road = Color3.fromRGB(55, 55, 60),
	Line = Color3.fromRGB(235, 200, 60),
	Sidewalk = Color3.fromRGB(175, 172, 165),
	Plaza = Color3.fromRGB(160, 150, 135),
	Path = Color3.fromRGB(205, 185, 145),
	Trunk = Color3.fromRGB(105, 75, 50),
	Leaves = { Color3.fromRGB(70, 130, 60), Color3.fromRGB(85, 145, 70), Color3.fromRGB(60, 115, 55), Color3.fromRGB(100, 150, 75) },
	Flowers = { Color3.fromRGB(235, 80, 90), Color3.fromRGB(250, 200, 60), Color3.fromRGB(190, 110, 220), Color3.fromRGB(250, 250, 245) },
	Soil = Color3.fromRGB(90, 65, 45),
	Stone = Color3.fromRGB(165, 160, 150),
	Water = Color3.fromRGB(80, 150, 215),
	Bench = Color3.fromRGB(140, 100, 65),
	Pole = Color3.fromRGB(60, 62, 66),
	Lamp = Color3.fromRGB(255, 220, 160),
	Window = Color3.fromRGB(45, 65, 90),
	Buildings = {
		Color3.fromRGB(205, 190, 160),
		Color3.fromRGB(150, 150, 155),
		Color3.fromRGB(160, 95, 75),
		Color3.fromRGB(170, 180, 190),
		Color3.fromRGB(225, 215, 190),
		Color3.fromRGB(140, 140, 115),
		Color3.fromRGB(120, 125, 140),
	},
}

---------------------------------------------------------------------
-- ตัวช่วยสร้าง Part
---------------------------------------------------------------------

local function newPart(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, mat: Enum.Material, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if shape then
		p.Shape = shape
	end
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = mat
	p.Parent = parent
	return p
end

-- ของแต่งเล็ก ๆ ที่ไม่ต้องชน/ไม่ต้องมีเงา (ประหยัดเครื่อง)
local function decor(p: Part): Part
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	return p
end

-- ทรงกระบอกตั้งตรง: center = จุดกึ่งกลาง
local function cylinder(parent: Instance, name: string, height: number, diameter: number, center: Vector3, color: Color3, mat: Enum.Material): Part
	return newPart(
		parent,
		name,
		Vector3.new(height, diameter, diameter),
		CFrame.new(center) * CFrame.Angles(0, 0, math.pi / 2),
		color,
		mat,
		Enum.PartType.Cylinder
	)
end

local function ball(parent: Instance, name: string, diameter: number, center: Vector3, color: Color3, mat: Enum.Material): Part
	return newPart(parent, name, Vector3.one * diameter, CFrame.new(center), color, mat, Enum.PartType.Ball)
end

local function polar(radius: number, angle: number): Vector2
	return Vector2.new(math.cos(angle) * radius, math.sin(angle) * radius)
end

local function folder(parent: Instance, name: string): Folder
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

---------------------------------------------------------------------
-- Build
---------------------------------------------------------------------

function CityBuilder.Build(options: Options): Model
	local gy = options.GroundY
	local rng = Random.new(options.Seed or 20261123)
	local plotCount = options.PlotCount
	local plotRadius = options.PlotRadius
	local plotSize = options.PlotSize

	-- ผังถนน
	local INNER_R, INNER_W = 66, 18 -- วงแหวนในรอบโรงงาน
	local PLAZA_R = INNER_R - INNER_W / 2 -- ลานปูนรอบโรงงาน
	local PLOT_FRONT_R = plotRadius - plotSize / 2 -- ขอบหน้าลานร้าน
	local OUTER_W = 20
	local OUTER_R = PLOT_FRONT_R - 10 - OUTER_W / 2 -- วงแหวนนอก (ผ่านหน้าร้านทุกร้าน)
	local SPOKE_W = 18
	local SIDEWALK_W = 4

	local plotAngles = {}
	for i = 1, plotCount do
		plotAngles[i] = (i - 1) / plotCount * TAU
	end

	local city = Instance.new("Model")
	city.Name = "City"

	local roads = folder(city, "Roads")
	local lines = folder(city, "RoadLines")
	local sidewalks = folder(city, "Sidewalks")
	local lights = folder(city, "StreetLights")
	local parks = folder(city, "Parks")
	local buildings = folder(city, "Buildings")
	local trees = folder(city, "Trees")

	-- แผ่นแบนวางจาก a ไป b (บนพื้น) ความหนา height ผิวบนอยู่ที่ yTop
	local function strip(parent: Instance, name: string, a: Vector2, b: Vector2, width: number, height: number, yTop: number, color: Color3, mat: Enum.Material, extraLength: number?): Part
		local length = (b - a).Magnitude + (extraLength or 0)
		local mid = (a + b) / 2
		local cf = CFrame.lookAt(Vector3.new(mid.X, yTop - height / 2, mid.Y), Vector3.new(b.X, yTop - height / 2, b.Y))
		return newPart(parent, name, Vector3.new(width, height, length), cf, color, mat)
	end

	-----------------------------------------------------------------
	-- ถนน
	-----------------------------------------------------------------

	local ROAD_TOP = gy + 0.2
	local LINE_TOP = gy + 0.24

	-- ลานปูนกลางเมือง (ใต้โรงงาน)
	cylinder(city, "Plaza", 0.3, PLAZA_R * 2, Vector3.new(0, gy + 0.15, 0), C.Plaza, M.Pavement)

	local function ringRoad(name: string, radius: number, width: number, segments: number)
		for i = 0, segments - 1 do
			local a0 = i / segments * TAU
			local a1 = (i + 1) / segments * TAU
			strip(roads, name, polar(radius, a0), polar(radius, a1), width, 0.2, ROAD_TOP, C.Road, M.Asphalt, 1.5)
			-- เส้นประเหลืองกลางถนน
			local mid = (a0 + a1) / 2
			local half = 2.5 / radius
			decor(strip(lines, "Dash", polar(radius, mid - half), polar(radius, mid + half), 0.5, 0.04, LINE_TOP, C.Line, M.Plastic))
		end
	end

	ringRoad("InnerRing", INNER_R, INNER_W, 36)
	ringRoad("OuterRing", OUTER_R, OUTER_W, 72)

	-- ถนนหลักจากวงแหวนในออกไปถึงหน้าร้าน
	for _, angle in plotAngles do
		local dir = polar(1, angle)
		local perp = Vector2.new(-dir.Y, dir.X)
		strip(roads, "Spoke", dir * INNER_R, dir * (PLOT_FRONT_R + 1), SPOKE_W, 0.2, ROAD_TOP, C.Road, M.Asphalt)

		for r = INNER_R + INNER_W / 2 + 6, OUTER_R - OUTER_W / 2 - 6, 12 do
			decor(strip(lines, "Dash", dir * r, dir * (r + 5), 0.5, 0.04, LINE_TOP, C.Line, M.Plastic))
		end

		-- ทางเท้าสองข้าง (ระหว่างวงแหวนใน-นอก)
		local sideStart = INNER_R + INNER_W / 2
		local sideEnd = OUTER_R - OUTER_W / 2
		for _, side in { -1, 1 } do
			local offset = perp * side * (SPOKE_W / 2 + SIDEWALK_W / 2)
			strip(sidewalks, "Sidewalk", dir * sideStart + offset, dir * sideEnd + offset, SIDEWALK_W, 0.6, gy + 0.6, C.Sidewalk, M.Pavement)
		end
	end

	-----------------------------------------------------------------
	-- ไฟถนน
	-----------------------------------------------------------------

	local function streetLight(at: Vector2, facing: Vector2)
		local model = Instance.new("Model")
		model.Name = "StreetLight"
		local base = Vector3.new(at.X, gy, at.Y)
		newPart(model, "Pole", Vector3.new(0.6, 15, 0.6), CFrame.new(base + Vector3.new(0, 7.5, 0)), C.Pole, M.Metal)
		local top = base + Vector3.new(0, 14.6, 0)
		local f = Vector3.new(facing.X, 0, facing.Y).Unit
		decor(newPart(model, "Arm", Vector3.new(0.4, 0.4, 4), CFrame.lookAt(top + f * 2, top + f * 4), C.Pole, M.Metal))
		local lamp = decor(newPart(model, "Lamp", Vector3.new(1.4, 0.5, 1.8), CFrame.lookAt(top + f * 4 - Vector3.new(0, 0.4, 0), top + f * 6 - Vector3.new(0, 0.4, 0)), C.Lamp, M.Neon))
		local light = Instance.new("PointLight")
		light.Color = C.Lamp
		light.Range = 26
		light.Brightness = 1.2
		light.Shadows = false
		light.Parent = lamp
		model.Parent = lights
	end

	local function angleGap(a: number, b: number): number
		local d = math.abs((a - b) % TAU)
		return math.min(d, TAU - d)
	end

	-- ริมถนนหลัก
	for _, angle in plotAngles do
		local dir = polar(1, angle)
		local perp = Vector2.new(-dir.Y, dir.X)
		local side = 1
		for r = INNER_R + 22, OUTER_R - 22, 28 do
			streetLight(dir * r + perp * side * (SPOKE_W / 2 + 3), -perp * side)
			side = -side
		end
	end
	-- ริมวงแหวนนอก (เว้นช่วงหน้าร้าน)
	for deg = 0, 359, 12 do
		local angle = math.rad(deg)
		local nearPlot = false
		for _, pa in plotAngles do
			if angleGap(angle, pa) < math.rad(11) then
				nearPlot = true
			end
		end
		if not nearPlot then
			local at = polar(OUTER_R + OUTER_W / 2 + 3, angle)
			streetLight(at, -at.Unit)
		end
	end
	-- รอบวงแหวนใน (หันเข้าโรงงาน)
	for deg = 30, 359, 60 do
		local at = polar(INNER_R + INNER_W / 2 + 3, math.rad(deg))
		streetLight(at, -at.Unit)
	end

	-----------------------------------------------------------------
	-- ระบบจองพื้นที่ (กันของซ้อนกัน / ทับถนน / ทับร้าน)
	-----------------------------------------------------------------

	local placed: { { Pos: Vector2, Radius: number } } = {}

	local function reserve(pos: Vector2, radius: number)
		table.insert(placed, { Pos = pos, Radius = radius })
	end

	local function isFree(p: Vector2, radius: number): boolean
		local r = p.Magnitude
		if r < PLAZA_R + radius + 2 then
			return false
		end
		if math.abs(r - INNER_R) < INNER_W / 2 + radius + 5 then
			return false
		end
		if math.abs(r - OUTER_R) < OUTER_W / 2 + radius + 5 then
			return false
		end
		for i, angle in plotAngles do
			local dir = polar(1, angle)
			local along = p:Dot(dir)
			if along > 0 and along < PLOT_FRONT_R + radius then
				local perpDistance = (p - dir * along).Magnitude
				if perpDistance < SPOKE_W / 2 + SIDEWALK_W + radius + 4 then
					return false -- ทับถนนหลัก
				end
			end
			local plotCenter = polar(plotRadius, plotAngles[i])
			if (p - plotCenter).Magnitude < plotSize * 0.75 + radius then
				return false -- ทับร้าน
			end
		end
		for _, other in placed do
			if (p - other.Pos).Magnitude < other.Radius + radius + 2 then
				return false
			end
		end
		return true
	end

	-- สุ่มหาตำแหน่งว่างภายในช่วงรัศมี/มุม
	local function findSpot(rMin: number, rMax: number, aMin: number, aMax: number, radius: number): Vector2?
		for _ = 1, 60 do
			local p = polar(rng:NextNumber(rMin, rMax), rng:NextNumber(aMin, aMax))
			if isFree(p, radius) then
				return p
			end
		end
		return nil
	end

	-- กันพื้นที่เส้นทางเดินในสวนไม่ให้ต้นไม้ขึ้นทับ
	local function reservePath(a: Vector2, b: Vector2, halfWidth: number)
		local length = (b - a).Magnitude
		for t = 0, length, 4 do
			reserve(a + (b - a).Unit * t, halfWidth)
		end
	end

	-----------------------------------------------------------------
	-- ของในเมือง
	-----------------------------------------------------------------

	local function tree(parent: Instance, at: Vector2, scale: number?)
		local s = scale or 1
		local model = Instance.new("Model")
		model.Name = "Tree"
		local height = rng:NextNumber(8, 13) * s
		cylinder(model, "Trunk", height, 1.5 * s, Vector3.new(at.X, gy + height / 2, at.Y), C.Trunk, M.Wood)
		local size = rng:NextNumber(9, 13) * s
		local leaves = C.Leaves[rng:NextInteger(1, #C.Leaves)]
		ball(model, "Leaves", size, Vector3.new(at.X, gy + height + size * 0.2, at.Y), leaves, M.Grass)
		local offset = Vector3.new(rng:NextNumber(-2, 2), 0, rng:NextNumber(-2, 2)) * s
		decor(ball(model, "Leaves2", size * 0.7, Vector3.new(at.X, gy + height + size * 0.45, at.Y) + offset, leaves:Lerp(Color3.new(1, 1, 1), 0.08), M.Grass))
		model.Parent = parent
	end

	local function bench(parent: Instance, at: Vector2, lookAt: Vector2)
		local model = Instance.new("Model")
		model.Name = "Bench"
		local base = CFrame.lookAt(Vector3.new(at.X, gy, at.Y), Vector3.new(lookAt.X, gy, lookAt.Y))
		newPart(model, "Seat", Vector3.new(5, 0.4, 1.6), base * CFrame.new(0, 1.6, 0), C.Bench, M.Planks)
		newPart(model, "Back", Vector3.new(5, 1.6, 0.3), base * CFrame.new(0, 2.6, 0.75), C.Bench, M.Planks)
		newPart(model, "Leg", Vector3.new(0.4, 1.4, 1.4), base * CFrame.new(-2, 0.7, 0), C.Pole, M.Metal)
		newPart(model, "Leg", Vector3.new(0.4, 1.4, 1.4), base * CFrame.new(2, 0.7, 0), C.Pole, M.Metal)
		model.Parent = parent
	end

	local function flowerBed(parent: Instance, at: Vector2)
		local model = Instance.new("Model")
		model.Name = "FlowerBed"
		cylinder(model, "Soil", 0.8, 6, Vector3.new(at.X, gy + 0.4, at.Y), C.Soil, M.Concrete)
		decor(cylinder(model, "Flowers", 0.4, 5.2, Vector3.new(at.X, gy + 0.95, at.Y), C.Flowers[rng:NextInteger(1, #C.Flowers)], M.Grass))
		model.Parent = parent
	end

	local function fountain(parent: Instance, at: Vector2)
		local model = Instance.new("Model")
		model.Name = "Fountain"
		local p = Vector3.new(at.X, gy, at.Y)
		cylinder(model, "Basin", 1.6, 22, p + Vector3.new(0, 0.8, 0), C.Stone, M.Concrete)
		local water = decor(cylinder(model, "Water", 0.2, 20, p + Vector3.new(0, 1.65, 0), C.Water, M.Glass))
		water.Transparency = 0.25
		cylinder(model, "Pillar", 4, 2.4, p + Vector3.new(0, 3.6, 0), C.Stone, M.Concrete)
		cylinder(model, "Bowl", 0.8, 8, p + Vector3.new(0, 5.6, 0), C.Stone, M.Concrete)
		local topWater = decor(cylinder(model, "TopWater", 0.2, 7, p + Vector3.new(0, 6.05, 0), C.Water, M.Glass))
		topWater.Transparency = 0.25
		model.Parent = parent
	end

	local function building(parent: Instance, at: Vector2, width: number, depth: number, height: number, yaw: number)
		local model = Instance.new("Model")
		model.Name = "Building"
		local base = CFrame.new(at.X, gy, at.Y) * CFrame.Angles(0, yaw, 0)
		local color = C.Buildings[rng:NextInteger(1, #C.Buildings)]

		decor(newPart(model, "Pad", Vector3.new(width + 6, 0.3, depth + 6), base * CFrame.new(0, 0.15, 0), C.Sidewalk, M.Pavement))
		newPart(model, "Body", Vector3.new(width, height, depth), base * CFrame.new(0, height / 2, 0), color, if rng:NextNumber() < 0.3 then M.Brick else M.Concrete)
		decor(newPart(model, "Roof", Vector3.new(width + 0.6, 0.8, depth + 0.6), base * CFrame.new(0, height + 0.4, 0), color:Lerp(Color3.new(0, 0, 0), 0.3), M.Concrete))

		-- แถบหน้าต่างรอบตึกทีละชั้น (ชิ้นเดียวครอบ 4 ด้าน)
		for y = 4.5, height - 3, 6 do
			local band = decor(newPart(model, "Windows", Vector3.new(width + 0.15, 2.4, depth + 0.15), base * CFrame.new(0, y, 0), C.Window, M.Glass))
			band.Reflectance = 0.1
		end

		-- ของบนดาดฟ้า
		if rng:NextNumber() < 0.6 then
			decor(newPart(model, "AirCon", Vector3.new(4, 2, 3), base * CFrame.new(rng:NextNumber(-width / 4, width / 4), height + 1.8, rng:NextNumber(-depth / 4, depth / 4)), C.Stone, M.Metal))
		end
		if rng:NextNumber() < 0.4 then
			local tankPos = (base * CFrame.new(width / 4, height + 3.3, -depth / 4)).Position
			decor(cylinder(model, "WaterTank", 5, 4, tankPos, C.Trunk, M.Wood))
		end
		model.Parent = parent
	end

	-----------------------------------------------------------------
	-- โซนระหว่างถนนหลัก: สลับ สวน / ย่านตึก
	-----------------------------------------------------------------

	local zoneInner = INNER_R + INNER_W / 2
	local zoneOuter = OUTER_R - OUTER_W / 2

	for zone = 1, plotCount do
		local a0 = plotAngles[zone]
		local a1 = a0 + TAU / plotCount
		local center = (a0 + a1) / 2

		if zone % 2 == 1 then
			-- สวน: น้ำพุตรงกลาง + ทางเดินวงกลม + ม้านั่ง + แปลงดอกไม้ + ต้นไม้
			local park = Instance.new("Model")
			park.Name = "Park"
			park.Parent = parks

			local mid = polar((zoneInner + zoneOuter) / 2, center)
			fountain(park, mid)
			reserve(mid, 30)

			for i = 0, 23 do
				local b0 = i / 24 * TAU
				local b1 = (i + 1) / 24 * TAU
				decor(strip(park, "Path", mid + polar(20, b0), mid + polar(20, b1), 4, 0.1, gy + 0.1, C.Path, M.Sand, 1))
			end
			-- ทางเดินจากวงกลมไปถนนหลักสองข้าง
			for _, spokeAngle in { a0, a1 } do
				local spokeDir = polar(1, spokeAngle)
				local target = spokeDir * mid:Dot(spokeDir)
				local toward = (target - mid).Unit
				local from = mid + toward * 20
				local to = target - toward * (SPOKE_W / 2 + SIDEWALK_W)
				decor(strip(park, "Path", from, to, 4, 0.1, gy + 0.1, C.Path, M.Sand))
				reservePath(from, to, 3)
			end

			for i = 0, 3 do
				local angle = center + math.pi / 4 + i * math.pi / 2
				bench(park, mid + polar(25, angle), mid)
				flowerBed(park, mid + polar(14.5, angle + math.pi / 4))
			end

			for _ = 1, 22 do
				local spot = findSpot(zoneInner + 8, zoneOuter - 8, a0, a1, 5)
				if spot then
					reserve(spot, 5)
					tree(park, spot)
				end
			end
		else
			-- ย่านตึก: ตึกหันหน้าตามแนวรัศมี
			for _ = 1, 9 do
				local width = rng:NextNumber(18, 30)
				local depth = rng:NextNumber(18, 28)
				local radius = math.sqrt(width * width + depth * depth) / 2 + 3
				local spot = findSpot(zoneInner + radius, zoneOuter - radius, a0, a1, radius)
				if spot then
					reserve(spot, radius)
					local yaw = -math.atan2(spot.Y, spot.X) + math.pi / 2
					building(buildings, spot, width, depth, rng:NextNumber(18, 55), yaw)
				end
			end
			-- ต้นไม้ริมทางในย่านตึก
			for _ = 1, 8 do
				local spot = findSpot(zoneInner + 6, zoneOuter - 6, a0, a1, 4)
				if spot then
					reserve(spot, 4)
					tree(trees, spot, 0.8)
				end
			end
		end
	end

	-----------------------------------------------------------------
	-- รอบนอก: ต้นไม้ระหว่างร้าน + ตึกสูงเป็นฉากหลัง
	-----------------------------------------------------------------

	for _ = 1, 40 do
		local spot = findSpot(OUTER_R + OUTER_W / 2 + 8, plotRadius + plotSize / 2 + 10, 0, TAU, 5)
		if spot then
			reserve(spot, 5)
			tree(trees, spot)
		end
	end

	local skylineInner = plotRadius + plotSize / 2 + 30
	for _ = 1, 45 do
		local width = rng:NextNumber(22, 40)
		local depth = rng:NextNumber(22, 40)
		local radius = math.sqrt(width * width + depth * depth) / 2 + 3
		local spot = findSpot(skylineInner + radius, skylineInner + 170, 0, TAU, radius)
		if spot then
			reserve(spot, radius)
			local yaw = -math.atan2(spot.Y, spot.X) + math.pi / 2
			building(buildings, spot, width, depth, rng:NextNumber(35, 110), yaw)
		end
	end

	city.Parent = workspace
	return city
end

return CityBuilder
