-- ShirtGenerator: สุ่มเสื้อจากกระสอบ (server เท่านั้น เพราะมี trueValue)
--
-- ขั้นตอนต่อเสื้อ 1 ตัว
--   1. rarity    : สุ่มตาม RarityWeights ของกระสอบ
--   2. แบบเสื้อ   : สุ่มจาก ShirtTemplates ของ rarity นั้น (ตาม Weight)
--   3. condition : สุ่มแบบสามเหลี่ยมตาม Condition {Min, Mode, Max} ของกระสอบ
--   4. ตำหนิ      : ตามระดับ condition (ข้อ 3.2)
--   5. trueValue : baseValue (สุ่มในช่วงราคาของ rarity ค่ากลางออกบ่อยกว่า) × ตัวคูณสภาพ
--
-- ห้ามส่ง shirt ตัวเต็มให้ client ให้ใช้ ToPublic() เสมอ

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = ReplicatedStorage.Shared.Config
local Rarities = require(Config.Rarities)
local ShirtTemplates = require(Config.ShirtTemplates)
local ShirtRules = require(Config.ShirtRules)

export type Shirt = {
	Id: string,
	TemplateId: string,
	Rarity: string,
	Condition: number,
	Defects: { string },
	TrueValue: number, -- ความลับ!
	PriceMin: number,
	PriceMax: number,
	IsGraded: boolean,
	Grade: number, -- 0 = ยังไม่ส่งเกรด
	SourceSack: string,
	AcquiredAt: number,
}

export type PublicShirt = {
	Id: string,
	TemplateId: string,
	DisplayName: string,
	Rarity: string,
	Condition: number,
	Defects: { string },
	PriceMin: number,
	PriceMax: number,
	IsGraded: boolean,
	Grade: number,
	TrueValue: number?, -- ส่งให้เฉพาะเสื้อที่ส่งเกรดแล้ว
}

local ShirtGenerator = {}

local rng = Random.new()

-- สุ่มแบบสามเหลี่ยม: ค่าอยู่ใน a..b และออกใกล้ c บ่อยสุด
local function triangular(a: number, b: number, c: number): number
	if b <= a then
		return a
	end
	local u = rng:NextNumber()
	local f = (c - a) / (b - a)
	if u < f then
		return a + math.sqrt(u * (b - a) * (c - a))
	end
	return b - math.sqrt((1 - u) * (b - a) * (b - c))
end

local function rollRarity(weights: { [string]: number }): string
	local total = 0
	for _, rarity in Rarities.List do
		total += weights[rarity.Name] or 0
	end
	local roll = rng:NextNumber(0, total)
	for _, rarity in Rarities.List do
		local weight = weights[rarity.Name] or 0
		if weight > 0 then
			roll -= weight
			if roll <= 0 then
				return rarity.Name
			end
		end
	end
	-- กันเศษทศนิยม: คืน rarity สุดท้ายที่มีโอกาส
	for i = #Rarities.List, 1, -1 do
		local name = Rarities.List[i].Name
		if (weights[name] or 0) > 0 then
			return name
		end
	end
	return Rarities.List[1].Name
end

local function rollTemplate(rarityName: string)
	local templates = ShirtTemplates.ByRarity[rarityName]
	local total = 0
	for _, template in templates do
		total += template.Weight
	end
	local roll = rng:NextNumber(0, total)
	for _, template in templates do
		roll -= template.Weight
		if roll <= 0 then
			return template
		end
	end
	return templates[#templates]
end

local function rollDefects(condition: number): { string }
	local chance = function(p: number)
		return rng:NextNumber() < p
	end
	if condition >= 90 then
		return {}
	elseif condition >= 70 then
		return { "faded" }
	elseif condition >= 50 then
		local defects = { "stain" }
		if chance(0.5) then
			table.insert(defects, "faded")
		end
		return defects
	elseif condition >= 30 then
		local defects = { "hole", "stain" }
		if chance(0.4) then
			table.insert(defects, "faded")
		end
		return defects
	else
		local defects = { "hole", "stain", "faded" }
		if chance(0.7) then
			table.insert(defects, "stretched")
		end
		return defects
	end
end

function ShirtGenerator.RollOne(sackType): Shirt
	local rarityName = rollRarity(sackType.RarityWeights)
	local rarity = Rarities.Get(rarityName)
	local template = rollTemplate(rarityName)

	local c = sackType.Condition
	local condition = math.clamp(math.round(triangular(c.Min, c.Max, c.Mode)), 1, 100)

	local baseValue = triangular(rarity.MinPrice, rarity.MaxPrice, (rarity.MinPrice + rarity.MaxPrice) / 2)
	local priceMin, priceMax = ShirtRules.GetPriceRange(rarityName, condition)
	local trueValue = math.clamp(math.round(baseValue * ShirtRules.ConditionMultiplier(condition)), priceMin, priceMax)

	return {
		Id = HttpService:GenerateGUID(false),
		TemplateId = template.Id,
		Rarity = rarityName,
		Condition = condition,
		Defects = rollDefects(condition),
		TrueValue = trueValue,
		PriceMin = priceMin,
		PriceMax = priceMax,
		IsGraded = false,
		Grade = 0,
		SourceSack = sackType.Id,
		AcquiredAt = os.time(),
	}
end

function ShirtGenerator.RollSack(sackType): { Shirt }
	local shirts = {}
	for _ = 1, sackType.ShirtCount do
		table.insert(shirts, ShirtGenerator.RollOne(sackType))
	end
	return shirts
end

-- แปลงเป็นข้อมูลที่ส่งให้ client ได้ (ตัด trueValue ออกถ้ายังไม่ส่งเกรด)
function ShirtGenerator.ToPublic(shirt: Shirt): PublicShirt
	local template = ShirtTemplates.Get(shirt.TemplateId)
	return {
		Id = shirt.Id,
		TemplateId = shirt.TemplateId,
		DisplayName = if template then template.DisplayName else shirt.TemplateId,
		Rarity = shirt.Rarity,
		Condition = shirt.Condition,
		Defects = table.clone(shirt.Defects),
		PriceMin = shirt.PriceMin,
		PriceMax = shirt.PriceMax,
		IsGraded = shirt.IsGraded,
		Grade = shirt.Grade,
		TrueValue = if shirt.IsGraded then shirt.TrueValue else nil,
	}
end

return ShirtGenerator
