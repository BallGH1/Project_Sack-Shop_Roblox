--!strict
-- Furniture: ของตกแต่งร้านที่ผู้เล่นซื้อแล้ววางเองได้อิสระ (ทุกชิ้นใช้แขวน/โชว์เสื้อขายได้)
--
-- Surface    : "Floor" วางได้เฉพาะพื้นในร้าน / "Wall" วางได้เฉพาะผนังด้านในร้าน
-- Size       : ขนาดกล่องครอบ (studs) ใช้ตรวจการวางทับ และตรวจว่าอยู่ในร้าน
-- Slots      : จำนวนช่องโชว์เสื้อขาย
-- PriceBonus : ลูกค้ามองเสื้อในชิ้นนี้ว่ามีค่ามากขึ้นกี่ % (ยอมจ่ายแพงขึ้น)

export type FurnitureDef = {
	Id: string,
	DisplayName: string,
	Description: string,
	Icon: string,
	Price: number,
	Surface: "Floor" | "Wall",
	Size: Vector3,
	Slots: number,
	PriceBonus: number,
}

local List: { FurnitureDef } = {
	{
		Id = "ClothesRack",
		DisplayName = "ราวตากผ้า",
		Description = "ราวเหล็กล้อเลื่อน แขวนขายได้ 4 ตัว",
		Icon = "🧺",
		Price = 1500,
		Surface = "Floor",
		Size = Vector3.new(6.4, 7.2, 2.4),
		Slots = 4,
		PriceBonus = 0,
	},
	{
		Id = "WallFrame",
		DisplayName = "กรอบรูปโชว์เสื้อ",
		Description = "แขวนผนัง โชว์ 1 ตัว ลูกค้ายอมจ่ายเพิ่ม 5%",
		Icon = "🖼️",
		Price = 1200,
		Surface = "Wall",
		Size = Vector3.new(3.4, 4, 0.5),
		Slots = 1,
		PriceBonus = 0.05,
	},
	{
		Id = "DisplayCase",
		DisplayName = "ตู้โชว์เสื้อ",
		Description = "ตู้กระจกมีไฟ โชว์ 1 ตัว ลูกค้ายอมจ่ายเพิ่ม 10%",
		Icon = "🗄️",
		Price = 5000,
		Surface = "Floor",
		Size = Vector3.new(3.6, 7.4, 2.6),
		Slots = 1,
		PriceBonus = 0.1,
	},
}

local ById: { [string]: FurnitureDef } = {}
for _, def in List do
	assert(ById[def.Id] == nil, "Furniture: duplicate Id " .. def.Id)
	assert(def.Slots >= 1 and def.Price > 0, "Furniture: bad Slots/Price on " .. def.Id)
	ById[def.Id] = def
end

local Furniture = {
	List = List,
	ById = ById,
}

function Furniture.Get(id: string): FurnitureDef?
	return ById[id]
end

return Furniture
