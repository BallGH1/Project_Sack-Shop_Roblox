--!strict
-- Rarities: ระดับความหายาก + ช่วงราคาที่ผู้เล่น "มองเห็น" + สีกรอบ UI
-- หมายเหตุ: นี่คือช่วงราคาสาธารณะ ส่วน trueValue ของเสื้อแต่ละตัวสุ่มบน server และไม่ส่งให้ client

export type Rarity = {
	Name: string,
	Order: number, -- 1 = ธรรมดาสุด
	MinPrice: number,
	MaxPrice: number,
	Color: Color3,
}

local List: { Rarity } = {
	{ Name = "Common", Order = 1, MinPrice = 20, MaxPrice = 150, Color = Color3.fromRGB(160, 160, 160) },
	{ Name = "Uncommon", Order = 2, MinPrice = 100, MaxPrice = 500, Color = Color3.fromRGB(85, 200, 90) },
	{ Name = "Rare", Order = 3, MinPrice = 400, MaxPrice = 2000, Color = Color3.fromRGB(70, 160, 255) },
	{ Name = "Epic", Order = 4, MinPrice = 1500, MaxPrice = 8000, Color = Color3.fromRGB(170, 85, 255) },
	{ Name = "Legendary", Order = 5, MinPrice = 6000, MaxPrice = 40000, Color = Color3.fromRGB(255, 195, 40) },
	{ Name = "Mythic", Order = 6, MinPrice = 30000, MaxPrice = 250000, Color = Color3.fromRGB(255, 60, 60) }, -- UI ทำรุ้งทีหลัง
}

local ByName: { [string]: Rarity } = {}
for _, rarity in List do
	assert(ByName[rarity.Name] == nil, "Rarities: duplicate name " .. rarity.Name)
	assert(rarity.MinPrice < rarity.MaxPrice, "Rarities: MinPrice must be < MaxPrice for " .. rarity.Name)
	ByName[rarity.Name] = rarity
end

local Rarities = {
	List = List,
	ByName = ByName,
}

function Rarities.Get(name: string): Rarity
	local rarity = ByName[name]
	assert(rarity, "Rarities: unknown rarity " .. tostring(name))
	return rarity
end

return Rarities
