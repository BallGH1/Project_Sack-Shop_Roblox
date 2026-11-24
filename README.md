# Thrift Sack Tycoon (ชื่อชั่วคราว)

เกม Roblox แนว Tycoon + Gacha + Trading — โค้ดเขียนด้วย Luau และ sync เข้า Studio ด้วย [Rojo](https://rojo.space) 7.7.1

## โครงสร้าง (ไฟล์ → ตำแหน่งใน Studio)

| ไฟล์ | ใน Studio |
|---|---|
| `src/shared/Config/*.luau` | `ReplicatedStorage.Shared.Config` (ModuleScript) |
| `src/server/init.server.luau` | `ServerScriptService.Server` (Script ตัวบูต) |
| `src/server/Services/*.luau` | `ServerScriptService.Server.Services` (ModuleScript) |
| `src/client/init.client.luau` | `StarterPlayer.StarterPlayerScripts.Client` |
| (ใน `default.project.json`) | `ReplicatedStorage.Remotes` (Folder) |

## เริ่มทำงาน

```bash
rojo build -o "Project-Game-Roblox.rbxlx"   # ทำครั้งแรกครั้งเดียว
rojo serve                                   # เปิดค้างไว้ระหว่างเขียนโค้ด
```

เปิด `Project-Game-Roblox.rbxlx` ใน Studio → แท็บ Plugins → Rojo → Connect

## ตั้งค่าที่ต้องทำเองใน Studio / Creator Hub

1. **Publish เกม**: File → Publish to Roblox (DataStore ใช้ได้เฉพาะเกมที่ publish แล้ว)
2. **เปิด DataStore ใน Studio**: Home → Game Settings → Security → เปิด *Enable Studio Access to API Services*
   (ถ้าไม่เปิด เกมยังรันได้ แต่จะใช้ที่เก็บชั่วคราวและขึ้น warning ใน Output)
3. **ผู้เล่นสูงสุด 6 คน**: Creator Hub → เกมของคุณ → Places → Configure Place → Server Size = 6
4. **ล็อตร้าน**: ถ้ายังไม่มี `Workspace.Plots` ระบบจะสร้างล็อตชั่วคราว 6 ล็อตรอบจุด (0,0,0) ให้เอง
   ถ้าจะสร้างล็อตเอง ให้ทำตามโครงสร้างที่อธิบายไว้หัวไฟล์ `src/server/Services/PlotService.luau`
   แล้ว **Save ไฟล์ place** (Rojo ไม่ลบของที่สร้างใน Workspace)

## สถานะ

- [x] Phase 1 ข้อ 1 — ล็อตร้าน 6 ล็อต (`PlotService`)
- [x] Phase 1 ข้อ 2 — เงิน + DataStore + session lock (`DataService`)
- [x] Phase 1 ข้อ 3 — Config: `Rarities`, `ShirtTemplates`, `SackTypes`, `GameConfig`
- [x] Phase 1 ข้อ 4 — โรงงาน: spawn กระสอบ + ซื้อ + เดินแบก (`SackService`, `FactoryBuilder`)
- [x] Phase 1 ข้อ 5 — เปิดกระสอบ → สุ่มเสื้อ + คลังเสื้อ + หน้าอัตราสุ่ม (`SackOpenService`, `InventoryService`, `ShirtGenerator`)
- [x] Phase 1 ข้อ 6 — วางขาย + ตั้งราคา + NPC หยิบเสื้อไปจ่ายที่เคาน์เตอร์ + กดคิดเงิน (`ShopService`, `NPCService`, `DisplayController`)
- [x] ตกแต่งร้าน: ราวตากผ้า / ตู้โชว์ / กรอบรูป วางได้อิสระ ย้าย/ขายคืนได้ (`DecorService`, `DecorController`, `PlacementRules`)
- [x] UI ใหม่ทั้งชุด (`UI/Theme`, `HudController`)
- [ ] อนาคต — จ้างพนักงานแคชเชียร์ (เรียก `NPCService:CheckoutNext` อัตโนมัติ)

## TODO สำคัญ

- [ ] **กลับมาลงรายละเอียดร้านเริ่มต้น** (`src/server/Modules/ShopBuilder.luau`) — ตอนนี้เป็นแบบร่างเพิงสังกะสีโทรม ๆ

- [ ] **เปลี่ยน DataService ไปใช้ ProfileStore ก่อนเริ่มทำระบบเทรด (Phase 3 ข้อ 12)**
  — ตอนนี้ใช้ session lock ที่เขียนเอง ซึ่งพอสำหรับช่วงพัฒนา แต่ระบบเทรดเสี่ยงของเบิ้ล ต้องใช้ตัวที่ผ่านการทดสอบมาแล้ว
  แก้แค่ข้างใน `DataService.luau` โดยให้ API (`GetData`, `AddMoney`, `TrySpend`, `ProfileLoaded`) เหมือนเดิม
