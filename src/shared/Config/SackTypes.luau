--!strict
-- SackTypes: ประเภทกระสอบ ราคา จำนวนเสื้อ อัตราสุ่ม rarity และช่วง condition
--
-- อยู่ใน ReplicatedStorage โดยตั้งใจ: อัตราสุ่มต้องเปิดเผยให้ผู้เล่นดูได้ (ปุ่ม Drop Rate / กฎ Roblox)
-- การ "สุ่มจริง" ทำบน server เท่านั้น client อ่านตารางนี้ได้แต่โกงผลไม่ได้
--
-- RarityWeights : เปอร์เซ็นต์ รวมกันต้องได้ 100
-- Condition     : สุ่มแบบสามเหลี่ยม (Min..Max โดยออกใกล้ Mode บ่อยสุด) -> กระสอบแพง Mode สูงกว่า
-- SpawnWeight   : น้ำหนักการเกิดที่โรงงาน (เทียบกันเฉพาะกระสอบที่ Enabled)
-- IsRare        : เกิดแล้วประกาศทั้งเซิร์ฟ + นับถอยหลังก่อนซื้อได้ (Phase 2)
-- Enabled       : MVP เปิดแค่ 3 แบบแรก

local Rarities = require(script.Parent.Rarities)

export type SackType = {
	Id: string,
	DisplayName: string,
	Price: number,
	ShirtCount: number,
	RarityWeights: { [string]: number },
	Condition: { Min: number, Max: number, Mode: number },
	SpawnWeight: number,
	IsRare: boolean,
	Enabled: boolean,
	Color: Color3,
}

local List: { SackType } = {
	{
		Id = "Basic",
		DisplayName = "กระสอบปุ๋ย",
		Price = 200,
		ShirtCount = 5,
		RarityWeights = { Common = 70, Uncommon = 25, Rare = 4.5, Epic = 0.5, Legendary = 0, Mythic = 0 },
		Condition = { Min = 5, Max = 85, Mode = 40 },
		SpawnWeight = 60,
		IsRare = false,
		Enabled = true,
		Color = Color3.fromRGB(230, 225, 200),
	},
	{
		Id = "RawCotton",
		DisplayName = "กระสอบผ้าดิบ",
		Price = 1000,
		ShirtCount = 6,
		RarityWeights = { Common = 50, Uncommon = 33, Rare = 13, Epic = 3.5, Legendary = 0.5, Mythic = 0 },
		Condition = { Min = 10, Max = 90, Mode = 50 },
		SpawnWeight = 28,
		IsRare = false,
		Enabled = true,
		Color = Color3.fromRGB(200, 180, 140),
	},
	{
		Id = "Import",
		DisplayName = "กระสอบนำเข้า",
		Price = 5000,
		ShirtCount = 7,
		RarityWeights = { Common = 30, Uncommon = 35, Rare = 25, Epic = 8, Legendary = 1.9, Mythic = 0.1 },
		Condition = { Min = 15, Max = 95, Mode = 60 },
		SpawnWeight = 10,
		IsRare = false,
		Enabled = true,
		Color = Color3.fromRGB(90, 130, 200),
	},
	{
		Id = "Japan",
		DisplayName = "กระสอบญี่ปุ่น",
		Price = 20000,
		ShirtCount = 8,
		RarityWeights = { Common = 15, Uncommon = 30, Rare = 33, Epic = 16, Legendary = 5.5, Mythic = 0.5 },
		Condition = { Min = 25, Max = 100, Mode = 70 },
		SpawnWeight = 1.8,
		IsRare = true,
		Enabled = false,
		Color = Color3.fromRGB(220, 60, 70),
	},
	{
		Id = "VintageUSA",
		DisplayName = "กระสอบวินเทจ USA",
		Price = 80000,
		ShirtCount = 10,
		RarityWeights = { Common = 5, Uncommon = 20, Rare = 35, Epic = 27, Legendary = 11, Mythic = 2 },
		Condition = { Min = 30, Max = 100, Mode = 78 },
		SpawnWeight = 0.2,
		IsRare = true,
		Enabled = false,
		Color = Color3.fromRGB(255, 200, 50),
	},
}

-- ตรวจ config ตอนโหลด: ผิดตรงไหนจะ error ใน Output ทันที ไม่ต้องรอเจอบั๊กตอนเล่น
local ById: { [string]: SackType } = {}
for _, sack in List do
	assert(ById[sack.Id] == nil, "SackTypes: duplicate Id " .. sack.Id)

	local total = 0
	for rarityName, weight in sack.RarityWeights do
		assert(Rarities.ByName[rarityName], ("SackTypes: %s has unknown rarity %s"):format(sack.Id, rarityName))
		assert(weight >= 0, ("SackTypes: %s has negative weight for %s"):format(sack.Id, rarityName))
		total += weight
	end
	assert(math.abs(total - 100) < 0.001, ("SackTypes: %s RarityWeights sum to %s, expected 100"):format(sack.Id, tostring(total)))

	local c = sack.Condition
	assert(1 <= c.Min and c.Min <= c.Mode and c.Mode <= c.Max and c.Max <= 100, "SackTypes: bad Condition range on " .. sack.Id)
	assert(sack.ShirtCount >= 1 and sack.Price > 0, "SackTypes: bad ShirtCount/Price on " .. sack.Id)

	ById[sack.Id] = sack
end

local SackTypes = {
	List = List,
	ById = ById,
}

function SackTypes.Get(id: string): SackType?
	return ById[id]
end

-- กระสอบที่เปิดใช้งาน เรียงตามราคา
function SackTypes.GetEnabled(): { SackType }
	local result = {}
	for _, sack in List do
		if sack.Enabled then
			table.insert(result, sack)
		end
	end
	table.sort(result, function(a, b)
		return a.Price < b.Price
	end)
	return result
end

return SackTypes
