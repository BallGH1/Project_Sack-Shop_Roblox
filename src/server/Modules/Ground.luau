-- Ground: หาความสูงของพื้นจริง ณ ตำแหน่ง X,Z (ยิง raycast ลงมาจากฟ้า)
-- ใช้ตอนสร้างร้าน/โรงงานด้วยโค้ด ให้วางบนพื้นพอดี ไม่ว่า Baseplate หรือ Terrain จะสูงเท่าไหร่

local Ground = {}

function Ground.GetY(position: Vector3, ignore: { Instance }?): number
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore or {}
	params.IgnoreWater = true

	local result = workspace:Raycast(Vector3.new(position.X, 1000, position.Z), Vector3.new(0, -2000, 0), params)
	if result then
		return result.Position.Y
	end
	warn(("[Ground] ไม่เจอพื้นที่ X=%.0f Z=%.0f ใช้ความสูง 0"):format(position.X, position.Z))
	return 0
end

return Ground
