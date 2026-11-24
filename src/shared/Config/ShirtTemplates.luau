--!strict
-- ShirtTemplates: "แบบเสื้อ" ทั้งหมดในเกม
-- เสื้อที่สุ่มได้แต่ละตัว = templateId + ค่าเฉพาะตัว (rarity, condition, trueValue ฯลฯ) ที่สร้างบน server
--
-- Weight      = โอกาสถูกเลือกเมื่อสุ่มได้ rarity นั้น (ค่ามาก = เจอบ่อย)
-- Category    = ใช้กับ Collection Book (Phase 4)
-- ShirtAssetId = Classic Shirt template สำหรับสวมใส่ (Phase 3) ใส่ 0 ไว้ก่อน
-- GraphicId    = รูปลายหน้าอก (Image asset id) แสดงบนการ์ดและเสื้อบนราว 0 = ยังไม่มีรูป (ใช้อิโมจิแทน)
--                ไฟล์ลายอยู่ที่ art/shirts/png/<Id>.png อัปโหลดผ่าน Asset Manager แล้วเอาเลข id มาใส่

local Rarities = require(script.Parent.Rarities)

export type ShirtTemplate = {
	Id: string,
	DisplayName: string,
	Rarity: string,
	Category: string,
	Weight: number,
	ShirtAssetId: number,
	GraphicId: number,
	ShirtImageId: number,
}

local List: { ShirtTemplate } = {
	-- Common
	{ Id = "plain_white", DisplayName = "Plain White Tee", Rarity = "Common", Category = "Basic", Weight = 3, ShirtAssetId = 0, GraphicId = 79890285812729, ShirtImageId = 135415605786517 },
	{ Id = "plain_black", DisplayName = "Plain Black Tee", Rarity = "Common", Category = "Basic", Weight = 3, ShirtAssetId = 0, GraphicId = 79890285812729, ShirtImageId = 116967427366995 },
	{ Id = "striped_polo", DisplayName = "Striped Polo", Rarity = "Common", Category = "Basic", Weight = 2, ShirtAssetId = 0, GraphicId = 79890285812729, ShirtImageId = 136163816949915 },
	{ Id = "souvenir_tee", DisplayName = "Sack City Souvenir Tee", Rarity = "Common", Category = "Travel", Weight = 2, ShirtAssetId = 0, GraphicId = 79890285812729, ShirtImageId = 117339156855811 },

	-- Uncommon
	{ Id = "faded_band", DisplayName = "Rusty Sacks Band Tee", Rarity = "Uncommon", Category = "Band", Weight = 2, ShirtAssetId = 0, GraphicId = 132207732660269, ShirtImageId = 105706604368949 },
	{ Id = "college_hoodie", DisplayName = "College Hoodie", Rarity = "Uncommon", Category = "College", Weight = 2, ShirtAssetId = 0, GraphicId = 132207732660269, ShirtImageId = 123038932006972 },
	{ Id = "retro_jersey", DisplayName = "Thrift City Rollers Jersey", Rarity = "Uncommon", Category = "Sport", Weight = 1, ShirtAssetId = 0, GraphicId = 74240904014529, ShirtImageId = 127467107228451 },

	-- Rare
	{ Id = "vintage_band_a", DisplayName = "Boneyard Skull Tee", Rarity = "Rare", Category = "Band", Weight = 2, ShirtAssetId = 0, GraphicId = 124466118480845, ShirtImageId = 91179578013487 },
	{ Id = "racing_jacket_90s", DisplayName = "Sack Racing Team '96", Rarity = "Rare", Category = "Sport", Weight = 1, ShirtAssetId = 0, GraphicId = 129251391160490, ShirtImageId = 120105981665252 },
	{ Id = "single_stitch", DisplayName = "Single-Stitch Tee", Rarity = "Rare", Category = "Basic", Weight = 2, ShirtAssetId = 0, GraphicId = 124466118480845, ShirtImageId = 112734042428301 },

	-- Epic
	{ Id = "tour_tee_1985", DisplayName = "Neon Wolves Tour 1985", Rarity = "Epic", Category = "Band", Weight = 2, ShirtAssetId = 0, GraphicId = 133238254970009, ShirtImageId = 100155899277859 },
	{ Id = "varsity_jacket", DisplayName = "Varsity Jacket", Rarity = "Epic", Category = "College", Weight = 1, ShirtAssetId = 0, GraphicId = 133238254970009, ShirtImageId = 94018314429521 },
	{ Id = "anime_promo", DisplayName = "Starblade Promo Tee", Rarity = "Epic", Category = "Cartoon", Weight = 1, ShirtAssetId = 0, GraphicId = 111560115152042, ShirtImageId = 125493945508202 },

	-- Legendary
	{ Id = "bootleg_rap", DisplayName = "Big Sack Bootleg Tee", Rarity = "Legendary", Category = "Band", Weight = 1, ShirtAssetId = 0, GraphicId = 118882815446788, ShirtImageId = 132102053475026 },
	{ Id = "rock_legend_tour", DisplayName = "Angel of Rust Farewell Tee", Rarity = "Legendary", Category = "Band", Weight = 1, ShirtAssetId = 0, GraphicId = 117068605682428, ShirtImageId = 126234433759101 },

	-- Mythic
	{ Id = "prototype_sample", DisplayName = "Prototype Sample Tee", Rarity = "Mythic", Category = "Grail", Weight = 1, ShirtAssetId = 0, GraphicId = 75039109254517, ShirtImageId = 130209766881244 },
	{ Id = "first_print_band", DisplayName = "Thunder Tongue First Press", Rarity = "Mythic", Category = "Grail", Weight = 1, ShirtAssetId = 0, GraphicId = 75039109254517, ShirtImageId = 89096333609345 },
}

local ById: { [string]: ShirtTemplate } = {}
local ByRarity: { [string]: { ShirtTemplate } } = {}

for _, rarity in Rarities.List do
	ByRarity[rarity.Name] = {}
end

for _, template in List do
	assert(ById[template.Id] == nil, "ShirtTemplates: duplicate Id " .. template.Id)
	assert(Rarities.ByName[template.Rarity], "ShirtTemplates: unknown rarity on " .. template.Id)
	assert(template.Weight > 0, "ShirtTemplates: Weight must be > 0 on " .. template.Id)
	ById[template.Id] = template
	table.insert(ByRarity[template.Rarity], template)
end

-- ทุก rarity ต้องมีเสื้ออย่างน้อย 1 แบบ ไม่งั้นสุ่มได้ rarity นั้นแล้วจะไม่มีเสื้อให้
for rarityName, templates in ByRarity do
	assert(#templates > 0, "ShirtTemplates: rarity " .. rarityName .. " has no templates")
end

local ShirtTemplates = {
	List = List,
	ById = ById,
	ByRarity = ByRarity,
}

function ShirtTemplates.Get(id: string): ShirtTemplate?
	return ById[id]
end

return ShirtTemplates
