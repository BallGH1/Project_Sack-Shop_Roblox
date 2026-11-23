--!strict
-- ShirtRules: กติกาของเสื้อที่ไม่ใช่ความลับ (client ใช้แสดงผลได้)
--   * Condition → ตัวคูณราคา, ระดับสภาพ, ตำหนิ
--   * ช่วงราคาที่ผู้เล่นมองเห็น
-- ส่วน trueValue ของเสื้อแต่ละตัวสุ่มและเก็บบน server เท่านั้น (ShirtGenerator)

local Rarities = require(script.Parent.Rarities)

export type ConditionTier = {
	Min: number, -- condition ต่ำสุดของระดับนี้
	Label: string,
	Color: Color3,
}

local ShirtRules = {}

-- ชนิดตำหนิ (ข้อ 6 ของ GDD: ตำหนิแต่ละชนิดซ่อมด้วยเครื่องคนละแบบ)
ShirtRules.Defects = {
	stain = { Name = "คราบ" },
	hole = { Name = "รอยขาด" },
	faded = { Name = "สีซีด" },
	stretched = { Name = "ผ้ายืด" },
}

-- ระดับสภาพตามข้อ 3.2 (เรียงจากดีสุด)
ShirtRules.ConditionTiers = {
	{ Min = 90, Label = "สภาพดีมาก", Color = Color3.fromRGB(110, 230, 120) },
	{ Min = 70, Label = "สีซีดเล็กน้อย", Color = Color3.fromRGB(190, 230, 100) },
	{ Min = 50, Label = "มีคราบ", Color = Color3.fromRGB(240, 210, 80) },
	{ Min = 30, Label = "ขาด + คราบ", Color = Color3.fromRGB(245, 150, 70) },
	{ Min = 1, Label = "ยับเยิน", Color = Color3.fromRGB(240, 90, 90) },
} :: { ConditionTier }

function ShirtRules.GetTier(condition: number): ConditionTier
	for _, tier in ShirtRules.ConditionTiers do
		if condition >= tier.Min then
			return tier
		end
	end
	return ShirtRules.ConditionTiers[#ShirtRules.ConditionTiers]
end

-- ตัวคูณราคาจากสภาพ: 100% = x1.0, 50% ≈ x0.55, 10% ≈ x0.32
function ShirtRules.ConditionMultiplier(condition: number): number
	local c = math.clamp(condition, 1, 100) / 100
	return 0.3 + 0.7 * c ^ 1.5
end

-- ช่วงราคาที่ผู้เล่นเห็น (ยังไม่ส่งเกรด) = ช่วงของ rarity × ตัวคูณสภาพ
-- trueValue จริงจะอยู่ในช่วงนี้เสมอ
function ShirtRules.GetPriceRange(rarityName: string, condition: number): (number, number)
	local rarity = Rarities.Get(rarityName)
	local multiplier = ShirtRules.ConditionMultiplier(condition)
	return math.floor(rarity.MinPrice * multiplier), math.ceil(rarity.MaxPrice * multiplier)
end

return ShirtRules
