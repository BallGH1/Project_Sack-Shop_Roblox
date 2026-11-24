-- PlacementRules: กติกาการวางของตกแต่ง ใช้ร่วมกันทั้ง client (เงาสีเขียว/แดง) และ server (ตัดสินจริง)
--
-- ร้านแต่ละล็อตต้องมี (ShopBuilder สร้างให้ใน Fixtures):
--   BuildArea                       กล่องแบนครอบพื้นในร้าน (ผิวล่าง = พื้น)
--   WallBack / WallLeft / WallRight แผ่นบางแปะผนังด้านใน: -Z ของ part หันเข้าในร้าน, +Z แนบผนัง
--   NoBuild*                        พื้นที่ห้ามวางของบนพื้น (ทางเข้า, โซนเปิดกระสอบ, คิวจ่ายเงิน ฯลฯ)
--
-- ตำแหน่งที่ส่งไป server ไม่ใช่ CFrame แต่เป็นค่าบนพื้นผิว (ให้ server คำนวณ CFrame เอง กันโกง):
--   พื้น : { X, Z, Rot }    X/Z = ตำแหน่งเทียบกับ BuildArea, Rot = 0..3 (หมุนทีละ 90°)
--   ผนัง : { Wall, U, V }   U = แนวนอนตามผนัง, V = แนวตั้ง (เทียบกับกึ่งกลางแผ่นผนัง)

local PlacementRules = {}

PlacementRules.Grid = 0.5
PlacementRules.WallNames = { "WallBack", "WallLeft", "WallRight" }

local function snap(value: number): number
	return math.round(value / PlacementRules.Grid) * PlacementRules.Grid
end
PlacementRules.Snap = snap

function PlacementRules.GetBuildArea(plot: Instance): BasePart?
	local area = plot:FindFirstChild("BuildArea", true)
	return if area and area:IsA("BasePart") then area else nil
end

function PlacementRules.GetWall(plot: Instance, name: any): BasePart?
	if type(name) ~= "string" or not table.find(PlacementRules.WallNames, name) then
		return nil
	end
	local wall = plot:FindFirstChild(name, true)
	return if wall and wall:IsA("BasePart") then wall else nil
end

function PlacementRules.GetWalls(plot: Instance): { BasePart }
	local walls = {}
	for _, name in PlacementRules.WallNames do
		local wall = PlacementRules.GetWall(plot, name)
		if wall then
			table.insert(walls, wall)
		end
	end
	return walls
end

-- ความสูงพื้นในร้าน (world Y)
function PlacementRules.FloorY(area: BasePart): number
	return area.Position.Y - area.Size.Y / 2
end

function PlacementRules.FloorCFrame(area: BasePart, def, x: number, z: number, rot: number): CFrame
	return area.CFrame * CFrame.new(snap(x), -area.Size.Y / 2 + def.Size.Y / 2, snap(z)) * CFrame.Angles(0, (rot % 4) * math.pi / 2, 0)
end

function PlacementRules.WallCFrame(wall: BasePart, def, u: number, v: number): CFrame
	-- ด้านหลังของกรอบแนบผนังพอดี (ผิว +Z ของแผ่นผนัง)
	return wall.CFrame * CFrame.new(snap(u), snap(v), wall.Size.Z / 2 - def.Size.Z / 2)
end

-- คำนวณ CFrame จากข้อมูลที่บันทึกไว้ คืน (CFrame, wall?) หรือ nil ถ้าใช้ไม่ได้
function PlacementRules.ResolveEntry(plot: Instance, def, entry): (CFrame?, BasePart?)
	if def.Surface == "Floor" then
		local area = PlacementRules.GetBuildArea(plot)
		if not area or type(entry.X) ~= "number" or type(entry.Z) ~= "number" or type(entry.Rot) ~= "number" then
			return nil
		end
		return PlacementRules.FloorCFrame(area, def, entry.X, entry.Z, entry.Rot), nil
	end
	local wall = PlacementRules.GetWall(plot, entry.Wall)
	if not wall or type(entry.U) ~= "number" or type(entry.V) ~= "number" then
		return nil
	end
	return PlacementRules.WallCFrame(wall, def, entry.U, entry.V), wall
end

local function isFinite(n: any): boolean
	return type(n) == "number" and n == n and math.abs(n) < 1000
end

-- ตรวจ/ทำความสะอาดข้อมูลตำแหน่งที่ client ส่งมา คืน entry ใหม่ หรือ nil
function PlacementRules.Sanitize(def, payload: any)
	if type(payload) ~= "table" then
		return nil
	end
	if def.Surface == "Floor" then
		if not (isFinite(payload.X) and isFinite(payload.Z) and isFinite(payload.Rot)) then
			return nil
		end
		return { Type = def.Id, X = snap(payload.X), Z = snap(payload.Z), Rot = math.floor(payload.Rot) % 4 }
	end
	if not (PlacementRules.GetWallName(payload.Wall) and isFinite(payload.U) and isFinite(payload.V)) then
		return nil
	end
	return { Type = def.Id, Wall = payload.Wall, U = snap(payload.U), V = snap(payload.V) }
end

function PlacementRules.GetWallName(name: any): string?
	return if type(name) == "string" and table.find(PlacementRules.WallNames, name) then name else nil
end

-- ตรวจว่าวางได้ไหม: ต้องอยู่ในพื้นที่ร้าน/บนผนัง และไม่ทับของอื่น
-- ignore = โมเดลตัวเองตอนย้าย (ไม่นับว่าทับ)
function PlacementRules.Validate(plot: Instance, def, cframe: CFrame, ignore: Instance?, wall: BasePart?): (boolean, string?)
	local half = def.Size / 2
	if def.Surface == "Floor" then
		local area = PlacementRules.GetBuildArea(plot)
		if not area then
			return false, "ร้านนี้วางของไม่ได้"
		end
		for _, sx in { -1, 1 } do
			for _, sz in { -1, 1 } do
				local corner = area.CFrame:PointToObjectSpace(cframe * Vector3.new(sx * half.X, 0, sz * half.Z))
				if math.abs(corner.X) > area.Size.X / 2 + 0.01 or math.abs(corner.Z) > area.Size.Z / 2 + 0.01 then
					return false, "ต้องวางภายในร้าน"
				end
			end
		end
	else
		if not wall then
			return false, "ต้องวางบนผนังในร้าน"
		end
		for _, sx in { -1, 1 } do
			for _, sy in { -1, 1 } do
				local corner = wall.CFrame:PointToObjectSpace(cframe * Vector3.new(sx * half.X, sy * half.Y, 0))
				if math.abs(corner.X) > wall.Size.X / 2 + 0.01 or math.abs(corner.Y) > wall.Size.Y / 2 + 0.01 then
					return false, "เลยขอบผนัง"
				end
			end
		end
	end

	-- ทับของอื่นไหม (ของตกแต่งร้านเดิม, ของที่วางแล้ว, พื้นที่ห้ามวาง)
	local include = {}
	for _, name in { "Props", "Furniture" } do
		local container = plot:FindFirstChild(name)
		if container then
			table.insert(include, container)
		end
	end
	if def.Surface == "Floor" then
		local fixtures = plot:FindFirstChild("Fixtures")
		if fixtures then
			for _, child in fixtures:GetChildren() do
				if child.Name:sub(1, 7) == "NoBuild" then
					table.insert(include, child)
				end
			end
		end
	end
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = include
	local shrink = Vector3.new(0.1, 0.1, 0.1)
	for _, hit in workspace:GetPartBoundsInBox(cframe, def.Size - shrink, params) do
		if not (ignore and hit:IsDescendantOf(ignore)) then
			if hit.Name:sub(1, 7) == "NoBuild" then
				return false, "ตรงนี้ต้องเว้นไว้ให้ลูกค้าเดิน"
			end
			return false, "ทับของอื่นอยู่"
		end
	end
	return true, nil
end

return PlacementRules
