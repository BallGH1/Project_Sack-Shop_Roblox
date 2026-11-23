--!strict
-- ShirtTemplates: "แบบเสื้อ" ทั้งหมดในเกม
-- เสื้อที่สุ่มได้แต่ละตัว = templateId + ค่าเฉพาะตัว (rarity, condition, trueValue ฯลฯ) ที่สร้างบน server
--
-- Weight      = โอกาสถูกเลือกเมื่อสุ่มได้ rarity นั้น (ค่ามาก = เจอบ่อย)
-- Category    = ใช้กับ Collection Book (Phase 4)
-- ShirtAssetId = Classic Shirt template สำหรับสวมใส่ (Phase 3) ใส่ 0 ไว้ก่อน

local Rarities = require(script.Parent.Rarities)

export type ShirtTemplate = {
	Id: string,
	DisplayName: string,
	Rarity: string,
	Category: string,
	Weight: number,
	ShirtAssetId: number,
}

local List: { ShirtTemplate } = {
	-- Common
	{ Id = "plain_white", DisplayName = "Plain White Tee", Rarity = "Common", Category = "Basic", Weight = 3, ShirtAssetId = 0 },
	{ Id = "plain_black", DisplayName = "Plain Black Tee", Rarity = "Common", Category = "Basic", Weight = 3, ShirtAssetId = 0 },
	{ Id = "striped_polo", DisplayName = "Striped Polo", Rarity = "Common", Category = "Basic", Weight = 2, ShirtAssetId = 0 },
	{ Id = "souvenir_tee", DisplayName = "Souvenir Tee", Rarity = "Common", Category = "Travel", Weight = 2, ShirtAssetId = 0 },

	-- Uncommon
	{ Id = "faded_band", DisplayName = "Faded Band Tee", Rarity = "Uncommon", Category = "Band", Weight = 2, ShirtAssetId = 0 },
	{ Id = "college_hoodie", DisplayName = "College Hoodie", Rarity = "Uncommon", Category = "College", Weight = 2, ShirtAssetId = 0 },
	{ Id = "retro_jersey", DisplayName = "Retro Sport Jersey", Rarity = "Uncommon", Category = "Sport", Weight = 1, ShirtAssetId = 0 },

	-- Rare
	{ Id = "vintage_band_a", DisplayName = "Vintage Band Tee A", Rarity = "Rare", Category = "Band", Weight = 2, ShirtAssetId = 0 },
	{ Id = "racing_jacket_90s", DisplayName = "90s Racing Jacket", Rarity = "Rare", Category = "Sport", Weight = 1, ShirtAssetId = 0 },
	{ Id = "single_stitch", DisplayName = "Single-Stitch Tee", Rarity = "Rare", Category = "Basic", Weight = 2, ShirtAssetId = 0 },

	-- Epic
	{ Id = "tour_tee_1985", DisplayName = "Tour Tee 1985", Rarity = "Epic", Category = "Band", Weight = 2, ShirtAssetId = 0 },
	{ Id = "varsity_jacket", DisplayName = "Varsity Jacket", Rarity = "Epic", Category = "College", Weight = 1, ShirtAssetId = 0 },
	{ Id = "anime_promo", DisplayName = "Anime Promo Tee", Rarity = "Epic", Category = "Cartoon", Weight = 1, ShirtAssetId = 0 },

	-- Legendary
	{ Id = "bootleg_rap", DisplayName = "Bootleg Rap Tee", Rarity = "Legendary", Category = "Band", Weight = 1, ShirtAssetId = 0 },
	{ Id = "rock_legend_tour", DisplayName = "Rock Legend Tour Tee", Rarity = "Legendary", Category = "Band", Weight = 1, ShirtAssetId = 0 },

	-- Mythic
	{ Id = "prototype_sample", DisplayName = "Prototype Sample Tee", Rarity = "Mythic", Category = "Grail", Weight = 1, ShirtAssetId = 0 },
	{ Id = "first_print_band", DisplayName = "First Print Band Tee", Rarity = "Mythic", Category = "Grail", Weight = 1, ShirtAssetId = 0 },
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
