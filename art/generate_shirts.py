"""
สร้างลายเสื้อ (ลายหน้าอก) 10 แบบเป็น SVG แล้ว render เป็น PNG 512x512 พื้นโปร่งใส ด้วย Chrome headless

    python art/generate_shirts.py

ผลลัพธ์
    art/shirts/svg/<templateId>.svg   ต้นฉบับ (แก้ต่อได้ใน Inkscape / Illustrator)
    art/shirts/png/<prefix>_<templateId>.png   ไฟล์สำหรับอัปโหลดเข้า Roblox (prefix: cm_ uc_ r_ e_ lgd_ mt_ ตาม rarity)
    art/shirts/tee/tee_<prefix>_<templateId>.png   เสื้อทั้งตัวพร้อมลาย (texture ของโมเดล + รูปบนการ์ด)
    art/shirts/mesh/tee.obj           โมเดลเสื้อ 3D (ใช้ร่วมกันทุกแบบ)
    art/shirts/preview.png            ภาพรวมเสื้อทุกแบบ

ทุกลายเป็นงานออกแบบใหม่ ชื่อวง/แบรนด์เป็นชื่อสมมติทั้งหมด (ห้ามใช้โลโก้/ชื่อของจริง)
ความละเอียดของลายไล่ตาม rarity: Common เรียบสุด → Mythic ละเอียดสุด
"""

import math
import os
import random
import subprocess
import sys

ROOT = os.path.dirname(os.path.abspath(__file__))
OUT_SVG = os.path.join(ROOT, "shirts", "svg")
OUT_PNG = os.path.join(ROOT, "shirts", "png")
CHROME_CANDIDATES = [
    r"C:\Program Files\Google\Chrome\Application\chrome.exe",
    r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
    "google-chrome",
    "chromium",
]

W = H = 512
CX = CY = 256

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------


def svg_doc(body, defs=""):
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">'
        f"<defs>{defs}</defs>{body}</svg>"
    )


def distress(fid, cut=0.32, freq=0.055, seed=7):
    """เอฟเฟกต์ลายสกรีนแตก/ซีด: ใช้ noise เจาะรูในลาย (cut มาก = ซีดมาก)"""
    return (
        f'<filter id="{fid}" x="-5%" y="-5%" width="110%" height="110%">'
        f'<feTurbulence type="fractalNoise" baseFrequency="{freq}" numOctaves="4" seed="{seed}" result="n"/>'
        f'<feColorMatrix in="n" type="matrix" values="0 0 0 0 1  0 0 0 0 1  0 0 0 0 1  22 0 0 0 {-22 * cut:.2f}" result="m"/>'
        f'<feComposite in="SourceGraphic" in2="m" operator="in"/>'
        f"</filter>"
    )


def glow(fid, color, blur=6):
    return (
        f'<filter id="{fid}" x="-30%" y="-30%" width="160%" height="160%">'
        f'<feGaussianBlur in="SourceAlpha" stdDeviation="{blur}" result="b"/>'
        f'<feFlood flood-color="{color}" result="c"/>'
        f'<feComposite in="c" in2="b" operator="in" result="g"/>'
        f'<feMerge><feMergeNode in="g"/><feMergeNode in="g"/><feMergeNode in="SourceGraphic"/></feMerge>'
        f"</filter>"
    )


def shadow(fid, dx=4, dy=4, color="#000", opacity=0.8):
    return (
        f'<filter id="{fid}" x="-20%" y="-20%" width="140%" height="140%">'
        f'<feDropShadow dx="{dx}" dy="{dy}" stdDeviation="0" flood-color="{color}" flood-opacity="{opacity}"/>'
        f"</filter>"
    )


def lin_grad(gid, stops, x1=0, y1=0, x2=0, y2=1):
    s = "".join(f'<stop offset="{o}" stop-color="{c}"/>' for o, c in stops)
    return f'<linearGradient id="{gid}" x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}">{s}</linearGradient>'


def rad_grad(gid, stops, cx=0.5, cy=0.5, r=0.5):
    s = "".join(f'<stop offset="{o}" stop-color="{c}"/>' for o, c in stops)
    return f'<radialGradient id="{gid}" cx="{cx}" cy="{cy}" r="{r}">{s}</radialGradient>'


def text(x, y, s, size, fill, font="Impact", anchor="middle", stroke=None, sw=0, extra=""):
    st = f' stroke="{stroke}" stroke-width="{sw}" paint-order="stroke" stroke-linejoin="round"' if stroke else ""
    return (
        f'<text x="{x}" y="{y}" font-family="{font}" font-size="{size}" fill="{fill}" '
        f'text-anchor="{anchor}"{st} {extra}>{s}</text>'
    )


def arc_text(pid, s, cx, cy, r, size, fill, font="Impact", top=True, stroke=None, sw=0, spacing=0, extra=""):
    """ข้อความโค้งตามวงกลม (top=True โค้งด้านบน, False โค้งด้านล่าง)"""
    if top:
        d = f"M {cx - r},{cy} A {r},{r} 0 0 1 {cx + r},{cy}"
    else:
        d = f"M {cx - r},{cy} A {r},{r} 0 0 0 {cx + r},{cy}"
    st = f' stroke="{stroke}" stroke-width="{sw}" paint-order="stroke" stroke-linejoin="round"' if stroke else ""
    return (
        f'<path id="{pid}" d="{d}" fill="none"/>'
        f'<text font-family="{font}" font-size="{size}" fill="{fill}" letter-spacing="{spacing}"{st} {extra}>'
        f'<textPath href="#{pid}" startOffset="50%" text-anchor="middle">{s}</textPath></text>'
    )


def star_path(cx, cy, ro, ri, n=5, rot=-90):
    pts = []
    for i in range(n * 2):
        r = ro if i % 2 == 0 else ri
        a = math.radians(rot + i * 180 / n)
        pts.append(f"{cx + r * math.cos(a):.1f},{cy + r * math.sin(a):.1f}")
    return "M" + " L".join(pts) + " Z"


def star(cx, cy, ro, fill, ri=None, n=5, rot=-90, extra=""):
    return f'<path d="{star_path(cx, cy, ro, ri or ro * 0.45, n, rot)}" fill="{fill}" {extra}/>'


def sparkle(cx, cy, r, fill):
    return star(cx, cy, r, fill, ri=r * 0.18, n=4, rot=0)


def rose(cx, cy, r, petal="#b3203a", dark="#6e0f22", leaf="#3f7a3a"):
    """ดอกกุหลาบ: วงกลมซ้อน + เส้นกลีบหมุนวน + ใบ"""
    parts = []
    for ang in (-35, 215):
        a = math.radians(ang)
        lx, ly = cx + math.cos(a) * r * 1.05, cy + math.sin(a) * r * 1.05
        parts.append(
            f'<ellipse cx="{lx:.1f}" cy="{ly:.1f}" rx="{r * 0.75:.1f}" ry="{r * 0.32:.1f}" '
            f'transform="rotate({ang} {lx:.1f} {ly:.1f})" fill="{leaf}" stroke="#1e3b1c" stroke-width="2"/>'
        )
    parts.append(f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="{petal}" stroke="{dark}" stroke-width="3"/>')
    for i, k in enumerate((0.78, 0.55, 0.33)):
        rr = r * k
        start = i * 70
        a0, a1 = math.radians(start), math.radians(start + 250)
        x0, y0 = cx + rr * math.cos(a0), cy + rr * math.sin(a0)
        x1, y1 = cx + rr * math.cos(a1), cy + rr * math.sin(a1)
        parts.append(
            f'<path d="M{x0:.1f},{y0:.1f} A{rr:.1f},{rr:.1f} 0 1 1 {x1:.1f},{y1:.1f}" '
            f'fill="none" stroke="{dark}" stroke-width="3" stroke-linecap="round"/>'
        )
    parts.append(f'<circle cx="{cx}" cy="{cy}" r="{r * 0.14:.1f}" fill="{dark}"/>')
    return "".join(parts)


def feather_fan(px, py, count, length, width, a_start, a_end, colors, stroke="#1b1b1b", sw=2, mirror=False):
    """ปีก: ขนเรียงเป็นพัด หมุนรอบจุดไหล่ (px,py)"""
    parts = []
    for i in range(count):
        t = i / max(count - 1, 1)
        ang = a_start + (a_end - a_start) * t
        if mirror:
            ang = 180 - ang
        color = colors[i % len(colors)]
        L = length * (0.75 + 0.25 * math.sin(t * math.pi))
        parts.append(
            f'<path d="M0,0 C{L * 0.3:.1f},{-width:.1f} {L * 0.85:.1f},{-width * 0.8:.1f} {L:.1f},0 '
            f'C{L * 0.85:.1f},{width * 0.8:.1f} {L * 0.3:.1f},{width:.1f} 0,0 Z" '
            f'transform="translate({px},{py}) rotate({ang:.1f})" fill="{color}" stroke="{stroke}" stroke-width="{sw}"/>'
            f'<path d="M{L * 0.1:.1f},0 L{L * 0.92:.1f},0" transform="translate({px},{py}) rotate({ang:.1f})" '
            f'stroke="{stroke}" stroke-width="1.2" opacity="0.6"/>'
        )
    return "".join(parts)


def flames(cx, base_y, width, count, height, rng, colors=("#ff5a1f", "#ffb21f", "#ffe36b")):
    parts = []
    for layer, color in enumerate(colors):
        scale = 1 - layer * 0.28
        for i in range(count):
            x = cx - width / 2 + width * (i + 0.5) / count + rng.uniform(-6, 6)
            h = height * scale * rng.uniform(0.7, 1.15)
            w = width / count * 0.9 * scale
            parts.append(
                f'<path d="M{x - w:.1f},{base_y} C{x - w:.1f},{base_y - h * 0.5:.1f} {x - w * 0.2:.1f},{base_y - h * 0.6:.1f} '
                f'{x + rng.uniform(-w * 0.4, w * 0.4):.1f},{base_y - h:.1f} '
                f'C{x + w * 0.3:.1f},{base_y - h * 0.6:.1f} {x + w:.1f},{base_y - h * 0.5:.1f} {x + w:.1f},{base_y} Z" '
                f'fill="{color}"/>'
            )
    return "".join(parts)


def bolt(x, y, s, fill, stroke="#111", sw=4, rot=0):
    pts = [(0, 0), (40, 0), (22, 48), (48, 48), (-8, 130), (8, 66), (-16, 66)]
    p = " ".join(f"{x + px * s:.1f},{y + py * s:.1f}" for px, py in pts)
    return f'<polygon points="{p}" fill="{fill}" stroke="{stroke}" stroke-width="{sw}" stroke-linejoin="round" transform="rotate({rot} {x} {y})"/>'


def ribbon(cx, cy, w, h, fill, dark, label, font_size, text_fill, font="Impact"):
    """ป้ายริบบิ้นตัดปลาย"""
    x0, x1 = cx - w / 2, cx + w / 2
    tail = h * 0.9
    parts = [
        f'<polygon points="{x0 - tail},{cy - h / 2 + 10} {x0 + 10},{cy - h / 2 + 10} {x0 + 10},{cy + h / 2 + 10} {x0 - tail},{cy + h / 2 + 10} {x0 - tail * 0.55},{cy + 10}" fill="{dark}" stroke="#111" stroke-width="3"/>',
        f'<polygon points="{x1 + tail},{cy - h / 2 + 10} {x1 - 10},{cy - h / 2 + 10} {x1 - 10},{cy + h / 2 + 10} {x1 + tail},{cy + h / 2 + 10} {x1 + tail * 0.55},{cy + 10}" fill="{dark}" stroke="#111" stroke-width="3"/>',
        f'<rect x="{x0}" y="{cy - h / 2}" width="{w}" height="{h}" fill="{fill}" stroke="#111" stroke-width="3"/>',
        text(cx, cy + font_size * 0.35, label, font_size, text_fill, font=font),
    ]
    return "".join(parts)


# ---------------------------------------------------------------------------
# designs (เรียงจาก Common → Mythic)
# ---------------------------------------------------------------------------


def d_souvenir():
    """COMMON — Souvenir Tee: โปสการ์ด 'Greetings from Sack City'"""
    defs = distress("ds", cut=0.30) + lin_grad("sky", [(0, "#ff8a3d"), (1, "#ffd36b")]) + "<clipPath id='card'><rect x='106' y='170' width='300' height='170' rx='14'/></clipPath>"
    sky = "<g clip-path='url(#card)'><rect x='106' y='170' width='300' height='170' fill='url(#sky)'/>"
    sky += "<circle cx='256' cy='300' r='62' fill='#fff1c9'/>"
    rng = random.Random(1)
    x = 106
    while x < 406:
        w = rng.randint(18, 34)
        h = rng.randint(30, 95)
        sky += f"<rect x='{x}' y='{340 - h}' width='{w}' height='{h}' fill='#3b2a3f'/>"
        x += w - 2
    sky += "</g><rect x='106' y='170' width='300' height='170' rx='14' fill='none' stroke='#f3e6c8' stroke-width='7'/>"
    body = f"<g filter='url(#ds)'>"
    body += text(256, 150, "Greetings from", 34, "#f3e6c8", font="Georgia", extra='font-style="italic"')
    body += sky
    body += text(256, 405, "SACK CITY", 76, "#f3e6c8", stroke="#3b2a3f", sw=8)
    body += text(256, 440, "EST. 1987", 22, "#ffb36b", font="Arial Black", extra='letter-spacing="6"')
    body += "</g>"
    return svg_doc(body, defs)


def d_faded_band():
    """UNCOMMON — Faded Band Tee: วง RUSTY SACKS ตราวงกลม + สายฟ้า"""
    defs = distress("ds", cut=0.38, seed=11)
    body = "<g filter='url(#ds)'>"
    body += "<circle cx='256' cy='256' r='186' fill='none' stroke='#d96c2c' stroke-width='10'/>"
    body += "<circle cx='256' cy='256' r='170' fill='none' stroke='#efe2c4' stroke-width='3'/>"
    body += arc_text("t1", "RUSTY SACKS", 256, 256, 128, 66, "#efe2c4", spacing=4)
    body += bolt(240, 165, 1.35, "#f2c230", rot=8)
    body += arc_text("t2", "LIVE AT THE WAREHOUSE", 256, 256, 150, 24, "#d96c2c", font="Arial Black", top=False, spacing=3)
    for sx in (120, 392):
        body += star(sx, 262, 16, "#efe2c4")
    body += "</g>"
    return svg_doc(body, defs)


def d_retro_jersey():
    """UNCOMMON — Retro Sport Jersey: THRIFT CITY ROLLERS #23"""
    defs = distress("ds", cut=0.30, seed=5) + shadow("sh", 7, 7, "#1d2b52", 1)
    body = "<g filter='url(#ds)'>"
    body += arc_text("t1", "THRIFT CITY", 256, 250, 175, 56, "#c8323a", font="Arial Black", stroke="#ffffff", sw=8, spacing=3)
    body += f"<g filter='url(#sh)'>{text(256, 385, '23', 250, '#ffffff', stroke='#c8323a', sw=10)}</g>"
    body += text(256, 452, "Rollers", 64, "#1d2b52", font="Segoe Script", stroke="#ffffff", sw=6, extra='font-weight="bold"')
    for sx in (92, 420):
        body += star(sx, 300, 20, "#c8323a", extra="stroke='#fff' stroke-width='3'")
    body += "</g>"
    return svg_doc(body, defs)


def d_boneyard():
    """RARE — Vintage Band Tee: BONEYARD หัวกะโหลก + กุหลาบ + กระดูกไขว้"""
    bone_c, line = "#ece0c2", "#1a1414"
    defs = distress("ds", cut=0.27, seed=3) + "<clipPath id='skullclip'><circle cx='256' cy='225' r='92'/><rect x='196' y='250' width='120' height='92' rx='22'/></clipPath>"
    defs += lin_grad("shade", [(0, "#ece0c2"), (0.6, "#ece0c2"), (1, "#b9a782")], 0, 0, 1, 0)
    b = "<g filter='url(#ds)'>"
    # กระดูกไขว้ด้านหลัง
    for ang in (-35, 35):
        b += f"<g transform='rotate({ang} 256 290)'>"
        b += f"<rect x='96' y='279' width='320' height='22' rx='11' fill='{bone_c}' stroke='{line}' stroke-width='4'/>"
        for ex in (96, 416):
            for dy in (-12, 12):
                b += f"<circle cx='{ex}' cy='{290 + dy}' r='15' fill='{bone_c}' stroke='{line}' stroke-width='4'/>"
        b += "</g>"
    # กะโหลก
    b += f"<circle cx='256' cy='225' r='92' fill='url(#shade)' stroke='{line}' stroke-width='5'/>"
    b += f"<rect x='196' y='250' width='120' height='92' rx='22' fill='url(#shade)' stroke='{line}' stroke-width='5'/>"
    b += f"<g clip-path='url(#skullclip)'><rect x='150' y='250' width='212' height='30' fill='url(#shade)'/></g>"
    b += f"<ellipse cx='220' cy='242' rx='29' ry='33' fill='{line}'/><ellipse cx='292' cy='242' rx='29' ry='33' fill='{line}'/>"
    b += "<circle cx='228' cy='236' r='6' fill='#c33'/><circle cx='300' cy='236' r='6' fill='#c33'/>"
    b += f"<path d='M256,268 L240,298 L256,292 L272,298 Z' fill='{line}'/>"
    for i in range(7):
        x = 214 + i * 12.5
        b += f"<rect x='{x}' y='310' width='10' height='26' rx='3' fill='{bone_c}' stroke='{line}' stroke-width='2.5'/>"
    b += f"<path d='M232,152 L246,176 L238,194' fill='none' stroke='{line}' stroke-width='3'/>"
    b += f"<path d='M300,165 L288,182 L296,198 L284,210' fill='none' stroke='{line}' stroke-width='3'/>"
    # กุหลาบ
    b += rose(176, 352, 30) + rose(336, 352, 30) + rose(256, 372, 22)
    b += arc_text("t1", "BONEYARD", 256, 225, 160, 72, "#c42a2a", stroke=bone_c, sw=6, spacing=6)
    b += ribbon(256, 438, 250, 44, "#c42a2a", "#7c1717", "NO REST TOUR '89", 30, bone_c)
    b += "</g>"
    return svg_doc(b, defs)


def d_racing():
    """RARE — 90s Racing Jacket: SACK RACING TEAM ธงตาหมากรุก + ปีก + เลข 07"""
    defs = distress("ds", cut=0.25, seed=21)
    defs += "<pattern id='chk' width='20' height='20' patternUnits='userSpaceOnUse'><rect width='20' height='20' fill='#fff'/><rect width='10' height='10' fill='#111'/><rect x='10' y='10' width='10' height='10' fill='#111'/></pattern>"
    defs += lin_grad("red", [(0, "#ff4b3e"), (1, "#a8151a")])
    b = "<g filter='url(#ds)'>"
    for side in (-1, 1):
        px, py = 256 + side * 92, 74
        b += f"<line x1='256' y1='236' x2='{px}' y2='{py - 6}' stroke='#111' stroke-width='9' stroke-linecap='round'/>"
        b += f"<line x1='256' y1='236' x2='{px}' y2='{py - 6}' stroke='#ddd' stroke-width='5' stroke-linecap='round'/>"
        fx = px + side * 112
        b += (
            f"<path d='M{px},{py} Q{px + side * 56},{py - 22} {fx},{py - 6} L{fx},{py + 64} "
            f"Q{px + side * 56},{py + 44} {px},{py + 72} Z' fill='url(#chk)' stroke='#111' stroke-width='3'/>"
        )
    # ปีก
    b += feather_fan(226, 272, 7, 120, 13, 150, 205, ["#f2f2f2", "#d9d9d9"], mirror=False)
    b += feather_fan(286, 272, 7, 120, 13, 150, 205, ["#f2f2f2", "#d9d9d9"], mirror=True)
    # โล่เลข 07
    b += "<path d='M206,236 h100 v58 q0,48 -50,66 q-50,-18 -50,-66 Z' fill='url(#red)' stroke='#111' stroke-width='5'/>"
    b += text(256, 318, "07", 70, "#fff", stroke="#111", sw=6)
    # ตัวหนังสือเอียง + เส้นความเร็ว
    b += "<g transform='skewX(-14) translate(78,0)'>"
    b += text(256, 418, "SACK RACING", 66, "#ffd23f", stroke="#111", sw=8)
    for i, w in enumerate((70, 50, 34)):
        b += f"<rect x='{70 - w}' y='{384 + i * 14}' width='{w}' height='6' fill='#ff4b3e'/>"
    b += "</g>"
    b += text(256, 458, "TEAM · 1996 · CHAMPIONSHIP", 22, "#fff", font="Arial Black", extra='letter-spacing="3"')
    b += "</g>"
    return svg_doc(b, defs)


def wolf_path(ox, oy, k=1.0):
    """หมาป่านั่งหอน หันซ้าย (พิกัดในกล่อง ~200x256 แล้วเลื่อน/ย่อขยาย)"""
    d = (
        "M160,256 C176,254 178,240 166,236 C154,232 146,236 140,240 "
        "C141,200 138,170 128,150 C120,132 112,112 112,95 L120,60 L101,77 L97,55 L87,79 "
        "C77,73 66,64 58,50 L40,18 L33,27 L60,78 "
        "C66,100 74,120 78,140 C81,170 73,200 70,230 L66,256 L93,256 L93,233 "
        "C101,237 109,242 113,256 Z"
    )
    return f'<path d="{d}" transform="translate({ox},{oy}) scale({k})"'


def d_neon_wolves():
    """EPIC — Tour Tee 1985: NEON WOLVES WORLD TOUR หมาป่าหอนใต้พระจันทร์"""
    rng = random.Random(85)
    defs = distress("ds", cut=0.22, seed=9) + glow("gp", "#ff3fb4", 5) + glow("gc", "#38e1ff", 4)
    defs += rad_grad("moon", [(0, "#ffffff"), (0.7, "#cfe6ff"), (1, "#8fb7ff")])
    defs += lin_grad("m1", [(0, "#5b2a86"), (1, "#24113d")]) + lin_grad("m2", [(0, "#2a3f8f"), (1, "#0f1636")])
    b = "<g filter='url(#ds)'>"
    for _ in range(40):
        b += f"<circle cx='{rng.uniform(40, 472):.0f}' cy='{rng.uniform(60, 300):.0f}' r='{rng.uniform(0.8, 2.4):.1f}' fill='#fff' opacity='{rng.uniform(0.5, 1):.2f}'/>"
    b += "<circle cx='256' cy='228' r='138' fill='url(#moon)'/>"
    for _ in range(9):
        b += f"<circle cx='{rng.uniform(170, 342):.0f}' cy='{rng.uniform(140, 300):.0f}' r='{rng.uniform(6, 18):.0f}' fill='#9fb9e8' opacity='0.45'/>"
    b += "<polygon points='40,370 120,270 175,320 240,250 300,330 360,262 470,370' fill='url(#m1)'/>"
    b += "<polygon points='40,370 95,320 150,352 215,300 280,356 345,312 410,340 470,300 470,370' fill='url(#m2)'/>"
    b += "<path d='M160,372 L200,300 L300,296 L352,372 Z' fill='#0b0d1f'/>"
    b += wolf_path(150, 47) + " fill='#0b0d1f'/>"
    b += f"<g filter='url(#gp)'>{text(256, 92, 'NEON WOLVES', 72, '#ffe3f4', stroke='#ff3fb4', sw=3, extra='letter-spacing=\"3\"')}</g>"
    b += f"<g filter='url(#gc)'>{text(256, 420, 'WORLD TOUR 1985', 44, '#e9fbff', stroke='#38e1ff', sw=2, font='Arial Black')}</g>"
    b += text(256, 452, "TOKYO · LONDON · BANGKOK · L.A. · BERLIN", 17, "#ff9fd8", font="Courier New", extra='font-weight="bold" letter-spacing="1"')
    b += "</g>"
    return svg_doc(b, defs)


def d_starblade():
    """EPIC — Anime Promo Tee: STARBLADE ซามูไรหน้าพระอาทิตย์ synthwave"""
    rng = random.Random(88)
    defs = distress("ds", cut=0.2, seed=13) + glow("gm", "#ff4fd8", 4)
    defs += lin_grad("sun", [(0, "#ffe76b"), (0.55, "#ff8a3d"), (1, "#ff2f8e")])
    defs += lin_grad("chrome", [(0, "#ffffff"), (0.45, "#9fe8ff"), (0.5, "#2b5aa8"), (1, "#e6f6ff")])
    mask = "<mask id='stripes'><rect width='512' height='512' fill='#fff'/>"
    for i in range(7):
        y = 238 + i * 15
        mask += f"<rect x='0' y='{y}' width='512' height='{2 + i * 1.3:.1f}' fill='#000'/>"
    mask += "</mask>"
    defs += mask + "<clipPath id='floor'><rect x='60' y='330' width='392' height='120'/></clipPath>"
    b = "<g filter='url(#ds)'>"
    b += "<circle cx='256' cy='230' r='140' fill='url(#sun)' mask='url(#stripes)'/>"
    # พื้นตาราง
    b += "<g clip-path='url(#floor)' stroke='#ff4fd8' stroke-width='2.5' filter='url(#gm)'>"
    for i in range(-10, 11):
        b += f"<line x1='256' y1='330' x2='{256 + i * 70}' y2='450'/>"
    y, step = 336, 6
    while y < 450:
        b += f"<line x1='60' y1='{y:.0f}' x2='452' y2='{y:.0f}'/>"
        step *= 1.35
        y += step
    b += "</g><rect x='60' y='328' width='392' height='4' fill='#ffd0f4'/>"
    # ซามูไร
    b += "<g fill='#120a24'>"
    b += "<polygon points='256,148 214,186 298,186'/>"  # หมวก
    b += "<circle cx='256' cy='200' r='18'/>"
    b += "<polygon points='232,214 280,214 318,330 194,330'/>"  # เสื้อคลุม
    b += "<polygon points='280,222 330,180 338,190 292,236'/>"  # แขนยกดาบ
    b += "</g>"
    b += "<polygon points='330,186 420,78 426,84 338,192' fill='#e8f7ff' stroke='#120a24' stroke-width='2'/>"
    b += sparkle(420, 80, 22, "#ffffff")
    for _ in range(8):
        b += sparkle(rng.uniform(70, 440), rng.uniform(70, 200), rng.uniform(4, 9), "#fff6c2")
    # คาตาคานะแนวตั้ง
    for i, ch in enumerate("スターブレード"):
        b += text(58, 120 + i * 34, ch, 30, "#ff4fd8", font="Yu Gothic", stroke="#120a24", sw=4, extra='font-weight="bold"')
    b += text(256, 410, "STARBLADE", 82, "url(#chrome)", stroke="#120a24", sw=8, extra='font-style="italic"')
    b += text(256, 450, "EPISODE 01 · 1988", 20, "#9fe8ff", font="Arial Black", extra='letter-spacing="4"')
    b += "</g>"
    return svg_doc(b, defs)


def d_big_sack():
    """LEGENDARY — Bootleg Rap Tee: BIG SACK กรอบรูปพร้อมมงกุฎ โซ่ทอง ไฟ กุหลาบ"""
    rng = random.Random(97)
    defs = distress("ds", cut=0.18, seed=17) + shadow("sh", 5, 5, "#000", 1)
    defs += lin_grad("gold", [(0, "#fff7c2"), (0.35, "#f4c23b"), (0.55, "#9c6a10"), (0.8, "#f9d65c"), (1, "#fff1a8")])
    defs += lin_grad("bg", [(0, "#5a2a86"), (0.6, "#c23b6b"), (1, "#ff9a3d")])
    defs += "<clipPath id='oval'><ellipse cx='256' cy='236' rx='112' ry='136'/></clipPath>"
    b = "<g filter='url(#ds)'>"
    b += flames(256, 392, 380, 11, 130, rng)
    b += "<ellipse cx='256' cy='236' rx='122' ry='146' fill='url(#gold)' stroke='#111' stroke-width='5'/>"
    b += "<g clip-path='url(#oval)'><rect x='130' y='90' width='260' height='300' fill='url(#bg)'/>"
    for i in range(18):
        a = math.radians(i * 20)
        b += f"<polygon points='256,250 {256 + 300 * math.cos(a):.0f},{250 + 300 * math.sin(a):.0f} {256 + 300 * math.cos(a + 0.17):.0f},{250 + 300 * math.sin(a + 0.17):.0f}' fill='#ffffff' opacity='0.08'/>"
    # คน (เงา) + แว่น + โซ่
    b += "<path d='M150,372 C160,300 200,288 256,288 C312,288 352,300 362,372 Z' fill='#1a0f22'/>"
    b += "<ellipse cx='256' cy='222' rx='46' ry='56' fill='#1a0f22'/>"
    b += "<rect x='218' y='210' width='34' height='16' rx='5' fill='#000' stroke='#f4c23b' stroke-width='2'/><rect x='260' y='210' width='34' height='16' rx='5' fill='#000' stroke='#f4c23b' stroke-width='2'/>"
    b += "<rect x='250' y='215' width='12' height='3' fill='#f4c23b'/>"
    for i in range(15):
        t = i / 14
        x = 206 + 100 * t
        y = 300 + 38 * math.sin(t * math.pi)
        b += f"<circle cx='{x:.1f}' cy='{y:.1f}' r='6' fill='none' stroke='url(#gold)' stroke-width='4'/>"
    b += "<circle cx='256' cy='346' r='14' fill='url(#gold)' stroke='#111' stroke-width='2'/>"
    b += "</g>"
    # มงกุฎ
    b += "<path d='M206,150 L214,104 L236,132 L256,92 L276,132 L298,104 L306,150 Z' fill='url(#gold)' stroke='#111' stroke-width='4'/>"
    for x in (214, 256, 298):
        b += f"<circle cx='{x}' cy='{104 if x != 256 else 92}' r='6' fill='#e0304e' stroke='#111' stroke-width='2'/>"
    b += rose(128, 330, 26) + rose(384, 330, 26) + rose(150, 140, 18) + rose(362, 140, 18)
    for _ in range(10):
        b += sparkle(rng.uniform(60, 452), rng.uniform(60, 400), rng.uniform(5, 11), "#fff6c2")
    b += f"<g filter='url(#sh)'>{text(256, 76, 'BIG SACK', 82, 'url(#gold)', stroke='#111', sw=8, extra='letter-spacing=\"4\"')}</g>"
    b += ribbon(256, 418, 300, 46, "#111", "#3a3a3a", "KING OF THE THRIFT", 32, "url(#gold)")
    b += text(256, 470, "LIFE AFTER THRIFT · 1997", 20, "#f4c23b", font="Arial Black", extra='letter-spacing="3"')
    for y in range(150, 380, 90):
        b += text(36, y, "BOOTLEG", 14, "#f4c23b", font="Arial Black", extra=f'transform="rotate(-90 36 {y})"')
        b += text(476, y, "BOOTLEG", 14, "#f4c23b", font="Arial Black", extra=f'transform="rotate(90 476 {y})"')
    b += "</g>"
    return svg_doc(b, defs)


def d_angel_of_rust():
    """LEGENDARY — Rock Legend Tour Tee: ANGEL OF RUST ปีกนางฟ้าหลายชั้น + รัศมี + กรอบโกธิค"""
    rng = random.Random(93)
    defs = distress("ds", cut=0.2, seed=23) + glow("gh", "#ffd36b", 8)
    defs += lin_grad("body", [(0, "#f6d2c4"), (1, "#c97a6a")])
    defs += lin_grad("txt", [(0, "#f6e7c8"), (1, "#d9a066")])
    b = "<g filter='url(#ds)'>"
    # กรอบโค้งแบบหน้าต่างโบสถ์
    b += "<path d='M86,470 V210 Q86,60 256,40 Q426,60 426,210 V470' fill='none' stroke='#d9a066' stroke-width='5'/>"
    b += "<path d='M100,470 V214 Q100,76 256,56 Q412,76 412,214 V470' fill='none' stroke='#d9a066' stroke-width='2'/>"
    for _ in range(16):
        b += sparkle(rng.uniform(110, 400), rng.uniform(70, 380), rng.uniform(3, 7), "#ffe9b8")
    # ปีก 3 ชั้น ต่อข้าง
    layers = [
        (11, 170, 18, 150, 230, ["#2f6f7a", "#3b8793"]),
        (9, 132, 16, 158, 222, ["#6cb7b8", "#86cfcc"]),
        (7, 92, 14, 168, 214, ["#e9f3ef", "#cfe5de"]),
    ]
    for count, length, width, a0, a1, colors in layers:
        b += feather_fan(240, 210, count, length, width, a0, a1, colors, stroke="#16262a")
        b += feather_fan(272, 210, count, length, width, a0, a1, colors, stroke="#16262a", mirror=True)
    # รัศมี
    b += "<ellipse cx='256' cy='128' rx='40' ry='11' fill='none' stroke='#ffd36b' stroke-width='6' filter='url(#gh)'/>"
    # ตัวนางฟ้า
    b += "<g fill='url(#body)' stroke='#4a2a24' stroke-width='3'>"
    b += "<circle cx='256' cy='160' r='22'/>"
    b += "<path d='M238,184 Q256,174 274,184 Q292,250 304,326 Q256,342 208,326 Q220,250 238,184 Z'/>"
    b += "</g>"
    b += "<path d='M232,146 Q256,124 280,146 Q284,170 276,186 Q270,160 256,156 Q242,160 236,186 Q228,170 232,146 Z' fill='#7a3b2a'/>"
    b += "<g stroke='#a35d4c' stroke-width='2.5' fill='none'><path d='M248,200 Q240,260 232,322'/><path d='M256,196 L256,332'/><path d='M264,200 Q272,260 280,322'/></g>"
    b += "<circle cx='250' cy='232' r='7' fill='#f6d2c4' stroke='#4a2a24' stroke-width='2'/><circle cx='262' cy='232' r='7' fill='#f6d2c4' stroke='#4a2a24' stroke-width='2'/>"
    b += text(256, 392, "ANGEL OF RUST", 50, "url(#txt)", font="Georgia", stroke="#1d1110", sw=5, extra='font-weight="bold" letter-spacing="5"')
    b += "<line x1='150' y1='408' x2='362' y2='408' stroke='#d9a066' stroke-width='2'/>"
    b += text(256, 438, "FAREWELL TOUR · 1993", 24, "#f6e7c8", font="Georgia", extra='letter-spacing="4"')
    b += text(256, 462, "SEATTLE · OSAKA · PARIS · BANGKOK", 14, "#d9a066", font="Courier New", extra='font-weight="bold"')
    b += "</g>"
    return svg_doc(b, defs)


def d_thunder_tongue():
    """MYTHIC — First Print Band Tee: THUNDER TONGUE FIRST PRESS 1971 นกอินทรี + สายฟ้า + แสงแฉก + กรอบลวดลาย"""
    rng = random.Random(71)
    defs = distress("ds", cut=0.14, seed=31) + shadow("sh", 4, 4, "#000", 1) + glow("gy", "#ffe36b", 6)
    defs += lin_grad("gold", [(0, "#fff8cf"), (0.3, "#f6c445"), (0.55, "#8f5d0c"), (0.75, "#f7d25e"), (1, "#fff3b0")])
    defs += rad_grad("burst", [(0, "#fff3b0"), (0.5, "#f08a24"), (1, "#8a1d12")])
    defs += "<clipPath id='disc'><circle cx='256' cy='240' r='196'/></clipPath>"
    b = "<g filter='url(#ds)'>"
    # แสงแฉกในวงกลม
    b += "<circle cx='256' cy='240' r='196' fill='url(#burst)'/>"
    b += "<g clip-path='url(#disc)'>"
    for i in range(36):
        a = math.radians(i * 10)
        c = "#ffe9a3" if i % 2 == 0 else "#b8361b"
        b += f"<polygon points='256,240 {256 + 300 * math.cos(a):.1f},{240 + 300 * math.sin(a):.1f} {256 + 300 * math.cos(a + math.radians(10)):.1f},{240 + 300 * math.sin(a + math.radians(10)):.1f}' fill='{c}' opacity='0.35'/>"
    b += "</g>"
    # กรอบวงแหวนลวดลาย
    b += "<circle cx='256' cy='240' r='204' fill='none' stroke='url(#gold)' stroke-width='12'/>"
    b += "<circle cx='256' cy='240' r='190' fill='none' stroke='#2a1408' stroke-width='3'/>"
    for i in range(60):
        a = math.radians(i * 6)
        b += f"<circle cx='{256 + 214 * math.cos(a):.1f}' cy='{240 + 214 * math.sin(a):.1f}' r='3' fill='#f6c445'/>"
    for i in range(12):
        a = math.radians(i * 30 + 15)
        b += star(256 + 204 * math.cos(a), 240 + 204 * math.sin(a), 9, "#fff3b0", extra="stroke='#2a1408' stroke-width='1.5'")
    # สายฟ้าไขว้
    b += f"<g filter='url(#gy)'>{bolt(112, 150, 1.25, '#ffe36b', rot=-24)}{bolt(388, 140, 1.25, '#ffe36b', rot=24)}</g>"
    # นกอินทรี: ปีก 3 ชั้น
    for count, length, width, a0, a1, colors in (
        (13, 175, 15, 160, 238, ["#5a3216", "#6f4120"]),
        (11, 135, 14, 168, 230, ["#8a5a2b", "#a06c36"]),
        (9, 95, 13, 176, 222, ["#d9b27a", "#e8c793"]),
    ):
        b += feather_fan(236, 228, count, length, width, a0, a1, colors, stroke="#1c0f06")
        b += feather_fan(276, 228, count, length, width, a0, a1, colors, stroke="#1c0f06", mirror=True)
    # ตัว + หาง
    b += "<path d='M226,220 Q256,200 286,220 L280,320 Q256,340 232,320 Z' fill='#6f4120' stroke='#1c0f06' stroke-width='4'/>"
    for i in range(5):
        x = 238 + i * 9
        b += f"<path d='M{x},320 L{x - 6 + i * 3},372 L{x + 9},322 Z' fill='#f3ead8' stroke='#1c0f06' stroke-width='2'/>"
    # ลายขนอก
    for row in range(4):
        for col in range(3):
            x = 240 + col * 16 + (8 if row % 2 else 0)
            y = 246 + row * 16
            b += f"<path d='M{x - 7},{y} Q{x},{y + 10} {x + 7},{y}' fill='none' stroke='#2b1608' stroke-width='2'/>"
    # หัวนกอินทรี (หันขวา)
    b += "<path d='M232,214 Q228,170 262,160 Q292,158 300,180 L318,190 Q306,200 292,198 Q284,214 280,222 Z' fill='#f3ead8' stroke='#1c0f06' stroke-width='4'/>"
    b += "<path d='M296,178 Q318,180 324,194 Q312,204 296,198 Z' fill='#f2b52b' stroke='#1c0f06' stroke-width='3'/>"
    b += "<circle cx='278' cy='180' r='5' fill='#1c0f06'/><circle cx='279' cy='179' r='1.5' fill='#fff'/>"
    b += "<path d='M266,172 L290,174' stroke='#1c0f06' stroke-width='3'/>"
    # ตัวหนังสือ
    b += arc_text("t1", "★ FIRST PRESS ★ 1971 ★", 256, 240, 158, 26, "#fff3b0", font="Arial Black", spacing=4, stroke="#2a1408", sw=4)
    b += ribbon(256, 418, 330, 56, "#8a1d12", "#4f0e08", "THUNDER TONGUE", 42, "url(#gold)")
    # ตราประทับ No. 001
    b += "<g transform='rotate(-14 418 98)'>"
    b += "<circle cx='418' cy='98' r='44' fill='#b01e1e' stroke='#fff3b0' stroke-width='4'/>"
    b += "<circle cx='418' cy='98' r='36' fill='none' stroke='#fff3b0' stroke-width='1.5' stroke-dasharray='4 3'/>"
    b += text(418, 92, "No.", 16, "#fff3b0", font="Arial Black")
    b += text(418, 118, "001", 26, "#fff3b0", font="Arial Black")
    b += "</g>"
    b += text(256, 478, "ORIGINAL 1971 PRESSING · NOT FOR RESALE", 15, "#f6c445", font="Courier New", extra='font-weight="bold" letter-spacing="1"')
    b += "</g>"
    return svg_doc(b, defs)


def d_college():
    """UNCOMMON — College Hoodie: THRIFT CITY UNIVERSITY ตัวหนังสือโค้งแบบมหาลัย"""
    defs = distress("ds", cut=0.3, seed=41) + shadow("sh", 5, 5, "#0f1a33", 1)
    font = "Rockwell Extra Bold, Rockwell, Georgia"
    b = "<g filter='url(#ds)'>"
    b += arc_text("t1", "THRIFT CITY", 256, 300, 190, 62, "#1f2f5c", font=font, stroke="#f2efe6", sw=8, spacing=4)
    b += f"<g filter='url(#sh)'>{text(256, 300, 'UNIVERSITY', 58, '#f2efe6', font=font, stroke='#1f2f5c', sw=8)}</g>"
    b += "<line x1='120' y1='330' x2='392' y2='330' stroke='#1f2f5c' stroke-width='5'/>"
    b += text(256, 372, "EST · 1962", 30, "#1f2f5c", font=font, stroke="#f2efe6", sw=5, extra='letter-spacing="6"')
    for sx in (110, 402):
        b += star(sx, 362, 14, "#1f2f5c", extra="stroke='#f2efe6' stroke-width='3'")
    b += "</g>"
    return svg_doc(b, defs)


def d_single_stitch():
    """RARE — Single-Stitch Tee: ตรา SACK CO. วงรี ภูเขา + พระอาทิตย์ขึ้น"""
    defs = distress("ds", cut=0.26, seed=44)
    defs += "<clipPath id='ov'><ellipse cx='256' cy='250' rx='150' ry='118'/></clipPath>"
    defs += lin_grad("dawn", [(0, "#f6b25a"), (1, "#e2643a")])
    b = "<g filter='url(#ds)'>"
    b += "<g clip-path='url(#ov)'><rect x='100' y='130' width='312' height='240' fill='url(#dawn)'/>"
    b += "<circle cx='256' cy='268' r='58' fill='#fde7b0'/>"
    for i in range(5):
        y = 262 + i * 9
        b += f"<rect x='190' y='{y}' width='132' height='3' fill='#e2643a'/>"
    b += "<polygon points='100,370 170,270 220,320 270,240 340,330 380,290 412,330 412,370' fill='#3b2d2a'/>"
    b += "<polygon points='255,248 270,240 284,256' fill='#f3ead8'/>"
    b += "</g>"
    b += "<ellipse cx='256' cy='250' rx='150' ry='118' fill='none' stroke='#f3ead8' stroke-width='7'/>"
    b += "<ellipse cx='256' cy='250' rx='170' ry='138' fill='none' stroke='#f3ead8' stroke-width='2'/>"
    b += arc_text("t1", "QUALITY GOODS", 256, 262, 170, 26, "#f3ead8", font="Arial Black", spacing=6)
    b += text(256, 222, "SACK CO.", 54, "#f3ead8", font="Georgia", stroke="#3b2d2a", sw=6, extra='font-weight="bold" letter-spacing="2"')
    b += ribbon(256, 410, 220, 40, "#f3ead8", "#b9ab90", "EST. 1990", 28, "#3b2d2a")
    b += "</g>"
    return svg_doc(b, defs)


def d_varsity():
    """EPIC — Varsity Jacket: ตัว T แพตช์ผ้าขนหนู + ช่อมะกอก + ดาว + CHAMPIONS 1979"""
    rng = random.Random(79)
    defs = distress("ds", cut=0.18, seed=47)
    defs += "<filter id='felt'><feTurbulence type='fractalNoise' baseFrequency='0.7' numOctaves='3' seed='4'/>"
    defs += "<feColorMatrix values='0 0 0 0 0  0 0 0 0 0  0 0 0 0 0  0 0 0 0.6 -0.15'/><feComposite in2='SourceGraphic' operator='in'/></filter>"
    defs += "<path id='T' d='M150,110 H362 V176 H334 Q330,150 300,148 H284 V360 Q284,384 314,388 V410 H198 V388 Q228,384 228,360 V148 H212 Q182,150 178,176 H150 Z'/>"
    b = "<g filter='url(#ds)'>"
    # ช่อมะกอกสองข้าง
    for side in (-1, 1):
        for i in range(9):
            t = i / 8
            x = 256 + side * (128 + 34 * math.sin(t * math.pi))  # โค้งออกตรงกลาง
            y = 140 + t * 250
            leaf_rot = side * (25 - 50 * t)
            b += f"<ellipse cx='{x:.1f}' cy='{y:.1f}' rx='9' ry='22' transform='rotate({leaf_rot:.0f} {x:.1f} {y:.1f})' fill='#c9a227' stroke='#3a2b06' stroke-width='2'/>"
    # แพตช์ตัว T: ขอบทอง → ขอบขาว → ผ้าแดง + ลายผ้า
    b += "<use href='#T' fill='#c9a227' stroke='#c9a227' stroke-width='30' stroke-linejoin='round'/>"
    b += "<use href='#T' fill='#f4f0e6' stroke='#f4f0e6' stroke-width='16' stroke-linejoin='round'/>"
    b += "<use href='#T' fill='#b3242e'/>"
    b += "<use href='#T' fill='#fff' filter='url(#felt)'/>"
    b += "<use href='#T' fill='none' stroke='#5c0f14' stroke-width='2' stroke-dasharray='5 4' transform='translate(256 260) scale(0.93) translate(-256 -260)'/>"
    for i in range(5):
        a = math.radians(-150 + i * 30)
        b += star(256 + 200 * math.cos(a), 300 + 200 * math.sin(a), 13, "#f4f0e6", extra="stroke='#c9a227' stroke-width='2'")
    b += ribbon(256, 452, 260, 44, "#1f2f5c", "#121c38", "CHAMPIONS 1979", 30, "#f4f0e6")
    for _ in range(6):
        b += sparkle(rng.uniform(90, 420), rng.uniform(90, 420), rng.uniform(4, 8), "#fff3c4")
    b += "</g>"
    return svg_doc(b, defs)


def d_prototype():
    """MYTHIC — Prototype Sample Tee: แบบร่างพิมพ์เขียว (blueprint) ของตราลับ + สติกเกอร์โฮโลแกรม + ตรา NOT FOR SALE"""
    defs = distress("ds", cut=0.12, seed=53)
    defs += "<pattern id='grid' width='16' height='16' patternUnits='userSpaceOnUse'><path d='M16,0 H0 V16' fill='none' stroke='#9cc7ff' stroke-opacity='0.35' stroke-width='1'/></pattern>"
    defs += lin_grad("holo", [(0, "#ff7ad9"), (0.25, "#7ad7ff"), (0.5, "#9dff9a"), (0.75, "#fff27a"), (1, "#ff9a7a")], 0, 0, 1, 1)
    defs += "<marker id='ar' markerWidth='8' markerHeight='8' refX='4' refY='4' orient='auto-start-reverse'><path d='M0,0 L8,4 L0,8 Z' fill='#e8f2ff'/></marker>"
    line = "#e8f2ff"
    b = "<g filter='url(#ds)'>"
    b += "<rect x='66' y='70' width='380' height='330' rx='10' fill='#1d4e89' stroke='#e8f2ff' stroke-width='4'/>"
    b += "<rect x='66' y='70' width='380' height='330' rx='10' fill='url(#grid)'/>"
    # ภาพลายเส้น: ปีก + โล่ + ดาว (เส้นอย่างเดียวแบบแบบร่าง)
    b += f"<g fill='none' stroke='{line}' stroke-width='2'>"
    for i in range(9):
        t = i / 8
        for side in (-1, 1):
            ang = math.radians(200 - 50 * t) if side == -1 else math.radians(-20 + 50 * t)
            L = 110 * (0.7 + 0.3 * math.sin(t * math.pi))
            x1, y1 = 256 + side * 22, 222
            x2, y2 = x1 + L * math.cos(ang), y1 + L * math.sin(ang)
            b += f"<path d='M{x1},{y1} Q{(x1 + x2) / 2:.1f},{(y1 + y2) / 2 - 14:.1f} {x2:.1f},{y2:.1f}'/>"
    b += "<path d='M222,196 h68 v52 q0,40 -34,56 q-34,-16 -34,-56 Z' stroke-width='3'/>"
    b += f"<path d='{star_path(256, 244, 22, 9)}'/>"
    b += "<circle cx='256' cy='222' r='120' stroke-dasharray='6 6' stroke-opacity='0.6'/>"
    b += "<line x1='136' y1='110' x2='136' y2='334' stroke-opacity='0.5'/><line x1='376' y1='110' x2='376' y2='334' stroke-opacity='0.5'/>"
    b += "</g>"
    # เส้นบอกขนาด
    b += f"<line x1='100' y1='360' x2='412' y2='360' stroke='{line}' stroke-width='2' marker-start='url(#ar)' marker-end='url(#ar)'/>"
    b += text(256, 352, "W 52 cm", 16, line, font="Courier New", extra='font-weight="bold"')
    b += f"<line x1='92' y1='100' x2='92' y2='340' stroke='{line}' stroke-width='2' marker-start='url(#ar)' marker-end='url(#ar)'/>"
    b += text(84, 225, "H 71 cm", 16, line, font="Courier New", extra='font-weight="bold" transform="rotate(-90 84 225)"')
    # กรอบข้อมูลมุมขวาล่าง
    b += f"<rect x='300' y='370' width='140' height='24' fill='#163f70' stroke='{line}' stroke-width='2'/>"
    b += text(370, 387, "PROTO No.000 REV A", 12, line, font="Courier New", extra='font-weight="bold"')
    b += text(256, 96, "PROTOTYPE · SAMPLE", 22, line, font="Arial Black", extra='letter-spacing="5"')
    # สติกเกอร์โฮโลแกรม
    b += "<circle cx='392' cy='118' r='40' fill='url(#holo)' stroke='#ffffff' stroke-width='3'/>"
    b += "<circle cx='392' cy='118' r='31' fill='none' stroke='#ffffff' stroke-opacity='0.8' stroke-width='1.5' stroke-dasharray='3 3'/>"
    b += text(392, 114, "AUTH", 15, "#3a2a5a", font="Arial Black")
    b += text(392, 132, "ENTIC", 15, "#3a2a5a", font="Arial Black")
    # ตรา NOT FOR SALE
    b += "<g transform='rotate(-12 170 440)'>"
    b += "<rect x='70' y='414' width='200' height='50' rx='6' fill='none' stroke='#d9262c' stroke-width='5'/>"
    b += text(170, 449, "NOT FOR SALE", 26, "#d9262c", font="Arial Black")
    b += "</g>"
    b += text(372, 450, "FACTORY ONLY", 18, "#9cc7ff", font="Courier New", extra='font-weight="bold"')
    b += "</g>"
    return svg_doc(b, defs)


# (templateId, rarity, ชื่อที่แสดง, ฟังก์ชันสร้าง)
DESIGNS = [
    ("souvenir_tee", "Common", "Sack City Souvenir Tee", d_souvenir),
    ("faded_band", "Uncommon", "Rusty Sacks Band Tee", d_faded_band),
    ("retro_jersey", "Uncommon", "Thrift City Rollers Jersey", d_retro_jersey),
    ("vintage_band_a", "Rare", "Boneyard Skull Tee", d_boneyard),
    ("racing_jacket_90s", "Rare", "Sack Racing Team '96", d_racing),
    ("tour_tee_1985", "Epic", "Neon Wolves Tour 1985", d_neon_wolves),
    ("anime_promo", "Epic", "Starblade Promo Tee", d_starblade),
    ("bootleg_rap", "Legendary", "Big Sack Bootleg Tee", d_big_sack),
    ("rock_legend_tour", "Legendary", "Angel of Rust Farewell Tee", d_angel_of_rust),
    ("first_print_band", "Mythic", "Thunder Tongue First Press", d_thunder_tongue),
    ("plain_white", "Common", "Plain White Tee", None),
    ("plain_black", "Common", "Plain Black Tee", None),
    ("striped_polo", "Common", "Striped Polo", None),
    ("college_hoodie", "Uncommon", "College Hoodie", d_college),
    ("single_stitch", "Rare", "Single-Stitch Tee", d_single_stitch),
    ("varsity_jacket", "Epic", "Varsity Jacket", d_varsity),
    ("prototype_sample", "Mythic", "Prototype Sample Tee", d_prototype),
]

# ชื่อไฟล์ PNG = prefix ตาม rarity + templateId (เช่น r_vintage_band_a.png)
RARITY_PREFIX = {
    "Common": "cm_",
    "Uncommon": "uc_",
    "Rare": "r_",
    "Epic": "e_",
    "Legendary": "lgd_",
    "Mythic": "mt_",
}


def png_name(template_id, rarity):
    return RARITY_PREFIX[rarity] + template_id + ".png"


RARITY_COLORS = {
    "Common": "#a0a0a0",
    "Uncommon": "#55c85a",
    "Rare": "#46a0ff",
    "Epic": "#aa55ff",
    "Legendary": "#ffc328",
    "Mythic": "#ff3c3c",
}

# ---------------------------------------------------------------------------
# render
# ---------------------------------------------------------------------------


def find_chrome():
    for c in CHROME_CANDIDATES:
        if os.path.isfile(c):
            return c
    for c in CHROME_CANDIDATES:
        try:
            subprocess.run([c, "--version"], capture_output=True, check=True)
            return c
        except Exception:
            pass
    sys.exit("ไม่พบ Chrome/Edge สำหรับ render PNG")


def screenshot(chrome, html_path, png_path, width, height):
    url = "file:///" + html_path.replace("\\", "/")
    subprocess.run(
        [
            chrome,
            "--headless=new",
            "--disable-gpu",
            "--hide-scrollbars",
            "--default-background-color=00000000",
            f"--window-size={width},{height}",
            f"--screenshot={png_path}",
            url,
        ],
        capture_output=True,
        timeout=120,
    )
    if not os.path.isfile(png_path):
        sys.exit(f"render ไม่สำเร็จ: {png_path}")


# ---------------------------------------------------------------------------
# เสื้อทั้งตัว (texture) + โมเดลเสื้อ 3D (mesh)
# ---------------------------------------------------------------------------

OUT_TEE = os.path.join(ROOT, "shirts", "tee")
OUT_MESH = os.path.join(ROOT, "shirts", "mesh")

# รูปทรงเสื้อยืด (พิกัดพิกเซลในรูป 512x512, y ชี้ลง) ใช้ทั้งวาด texture และสร้าง mesh ให้ตรงกันพอดี
TEE_PATH = (
    "M150,40 L210,20 Q256,52 302,20 L362,40 L452,110 L408,180 L370,156 L370,480 "
    "Q256,494 142,480 L142,156 L104,180 L60,110 Z"
)

# สีผ้าของเสื้อแต่ละแบบ (ผ้าฟอกวินเทจ)
FABRIC = {
    "souvenir_tee": "#7d8590",  # เทาท็อปดราย
    "faded_band": "#3a3a3e",  # ดำฟอกซีด
    "retro_jersey": "#e4ddc9",  # ครีม
    "vintage_band_a": "#2b2a2d",
    "racing_jacket_90s": "#26272b",
    "tour_tee_1985": "#232331",  # ดำอมน้ำเงิน
    "anime_promo": "#3a2a4f",  # ม่วงเข้ม
    "bootleg_rap": "#1f1e21",
    "rock_legend_tour": "#2c3436",  # เขียวหม่นเข้ม
    "first_print_band": "#2a2120",  # ดำอมน้ำตาล
    "plain_white": "#e9e6df",
    "plain_black": "#252527",
    "striped_polo": "#2f5aa8",  # น้ำเงิน + ลายทางขาว
    "college_hoodie": "#8d8f94",  # เทาท็อปดราย
    "single_stitch": "#8c3a34",  # แดงซีด
    "varsity_jacket": "#22304f",  # กรมท่า
    "prototype_sample": "#d8d2c4",  # ผ้าดิบออฟไวท์
}

# ผ้าสีอ่อน: ใช้ตะเข็บสีเข้มแทนดำ และลดความด่างของผ้า
LIGHT_FABRIC = ("retro_jersey", "plain_white", "prototype_sample")
# ลายทาง / ปกโปโล
STRIPES = ("striped_polo",)
POLO_COLLAR = ("striped_polo",)


def tee_polygon():
    """แปลง TEE_PATH เป็นรายการจุด (สุ่มจุดบนเส้นโค้ง Q)"""
    return [
        (150, 40), (210, 20), *[_quad((210, 20), (256, 52), (302, 20), t / 8) for t in range(1, 8)], (302, 20),
        (362, 40), (452, 110), (408, 180), (370, 156), (370, 480),
        *[_quad((370, 480), (256, 494), (142, 480), t / 8) for t in range(1, 8)], (142, 480),
        (142, 156), (104, 180), (60, 110),
    ]


def _quad(p0, p1, p2, t):
    x = (1 - t) ** 2 * p0[0] + 2 * (1 - t) * t * p1[0] + t * t * p2[0]
    y = (1 - t) ** 2 * p0[1] + 2 * (1 - t) * t * p1[1] + t * t * p2[1]
    return (x, y)


NO_PRINT = ("plain_white", "plain_black", "striped_polo")


def tee_texture_html(template_id, rarity):
    fabric = FABRIC.get(template_id, "#2b2a2d")
    light = template_id in LIGHT_FABRIC
    seam = "#000000" if not light else "#8a8270"
    has_print = os.path.isfile(os.path.join(OUT_PNG, png_name(template_id, rarity))) and template_id not in NO_PRINT
    print_svg = (
        f'<image href="../png/{png_name(template_id, rarity)}" x="151" y="92" width="210" height="210" opacity="0.95"/>'
        if has_print
        else ""
    )
    stripes_svg = (
        '<rect width="512" height="512" fill="url(#stripes)"/>' if template_id in STRIPES else ""
    )
    polo_svg = (
        f'<path d="M216,24 L256,60 L240,96 L206,40 Z" fill="{fabric}" stroke="#000" stroke-opacity="0.5" stroke-width="3"/>'
        f'<path d="M296,24 L256,60 L272,96 L306,40 Z" fill="{fabric}" stroke="#000" stroke-opacity="0.5" stroke-width="3"/>'
        '<rect x="246" y="56" width="20" height="78" fill="#000" fill-opacity="0.18"/>'
        '<circle cx="256" cy="78" r="4" fill="#f2efe6"/><circle cx="256" cy="108" r="4" fill="#f2efe6"/>'
        if template_id in POLO_COLLAR
        else ""
    )
    svg = f"""
<svg xmlns="http://www.w3.org/2000/svg" width="512" height="512" viewBox="0 0 512 512">
<defs>
  <clipPath id="tee"><path d="{TEE_PATH}"/></clipPath>
  <filter id="wash" x="0" y="0" width="100%" height="100%">
    <feTurbulence type="fractalNoise" baseFrequency="0.012" numOctaves="4" seed="{len(template_id) * 7}"/>
    <feColorMatrix values="0 0 0 0 1  0 0 0 0 1  0 0 0 0 1  1.6 0 0 0 -0.62"/>
  </filter>
  <filter id="grain" x="0" y="0" width="100%" height="100%">
    <feTurbulence type="fractalNoise" baseFrequency="0.9" numOctaves="2" seed="3"/>
    <feColorMatrix values="0 0 0 0 0  0 0 0 0 0  0 0 0 0 0  0 0 0 0.35 -0.08"/>
  </filter>
  <linearGradient id="sideShade" x1="0" x2="1">
    <stop offset="0" stop-color="#000" stop-opacity="0.35"/><stop offset="0.18" stop-color="#000" stop-opacity="0"/>
    <stop offset="0.82" stop-color="#000" stop-opacity="0"/><stop offset="1" stop-color="#000" stop-opacity="0.35"/>
  </linearGradient>
  <pattern id="stripes" width="512" height="30" patternUnits="userSpaceOnUse"><rect y="0" width="512" height="12" fill="#f2efe6" opacity="0.9"/></pattern>
  <linearGradient id="vShade" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#fff" stop-opacity="0.08"/><stop offset="1" stop-color="#000" stop-opacity="0.25"/>
  </linearGradient>
</defs>
<g clip-path="url(#tee)">
  <rect width="512" height="512" fill="{fabric}"/>
  {stripes_svg}
  <rect width="512" height="512" filter="url(#wash)" opacity="{0.10 if light else 0.22}"/>
  <rect width="512" height="512" fill="url(#sideShade)"/>
  <rect width="512" height="512" fill="url(#vShade)"/>
  <!-- รอยยับแนวตั้งตอนแขวน -->
  <path d="M200,150 Q190,320 205,470 M318,160 Q330,330 312,472 M256,300 Q262,400 252,480" stroke="#000" stroke-opacity="0.12" stroke-width="10" fill="none"/>
  <!-- ลายหน้าอก -->
  {print_svg}
  <rect width="512" height="512" filter="url(#grain)"/>
  <!-- ตะเข็บ: แขน / ชายเสื้อ / ปลายแขน -->
  <g stroke="{seam}" stroke-opacity="0.45" stroke-width="2.5" stroke-dasharray="6 4" fill="none">
    <path d="M150,40 L142,156"/><path d="M362,40 L370,156"/>
    <path d="M142,468 Q256,482 370,468"/>
    <path d="M70,122 L114,190"/><path d="M442,122 L398,190"/>
  </g>
  <!-- คอเสื้อ: ผ้าด้านในหลังคอ + ขอบยางคอ -->
  <path d="M210,20 Q256,52 302,20 Q256,30 210,20 Z" fill="#000" fill-opacity="0.45"/>
  <path d="M206,22 Q256,58 306,22" stroke="{fabric}" stroke-width="12" fill="none"/>
  <path d="M206,22 Q256,58 306,22" stroke="#000" stroke-opacity="0.35" stroke-width="12" fill="none"/>
  <path d="M200,26 Q256,66 312,26" stroke="{seam}" stroke-opacity="0.4" stroke-width="2" stroke-dasharray="5 4" fill="none"/>
  {polo_svg}
</g>
<path d="{TEE_PATH}" fill="none" stroke="#000" stroke-opacity="0.5" stroke-width="3"/>
</svg>"""
    return f"<html><body style='margin:0;background:transparent'>{svg}</body></html>"


def write_tee_obj(path, width_studs=2.4, thickness=0.12):
    """โมเดลเสื้อ: หน้า/หลังเป็นรูปทรงเสื้อ (หน้า = -Z), มีความหนา, UV หน้าตรงกับ texture พอดี"""
    pts = tee_polygon()
    k = width_studs / (452 - 60)  # studs ต่อพิกเซล
    cx, cy = 256, 257
    verts2d = [((x - cx) * k, (cy - y) * k) for x, y in pts]  # y ขึ้น

    # ear clipping (รูปทรงเป็นรูปหลายเหลี่ยมเว้า)
    def area(poly):
        return sum(poly[i][0] * poly[(i + 1) % len(poly)][1] - poly[(i + 1) % len(poly)][0] * poly[i][1] for i in range(len(poly))) / 2

    idx = list(range(len(verts2d)))
    if area(verts2d) < 0:
        idx.reverse()  # ให้เป็นทวนเข็ม (CCW)
    ccw = [verts2d[i] for i in idx]

    def cross(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])

    def inside(p, a, b, c):
        return cross(a, b, p) >= 0 and cross(b, c, p) >= 0 and cross(c, a, p) >= 0

    remaining = idx[:]
    tris = []
    guard = 0
    while len(remaining) > 3 and guard < 10000:
        guard += 1
        n = len(remaining)
        for i in range(n):
            ia, ib, ic = remaining[(i - 1) % n], remaining[i], remaining[(i + 1) % n]
            a, b, c = verts2d[ia], verts2d[ib], verts2d[ic]
            if cross(a, b, c) <= 1e-9:
                continue
            if any(inside(verts2d[j], a, b, c) for j in remaining if j not in (ia, ib, ic)):
                continue
            tris.append((ia, ib, ic))
            remaining.pop(i)
            break
    tris.append(tuple(remaining))

    n = len(verts2d)
    zf, zb = -thickness / 2, thickness / 2
    lines = ["# Thrift Sack Tycoon - hanging tee mesh (front faces -Z)", "o Tee"]
    for x, y in verts2d:
        lines.append(f"v {x:.5f} {y:.5f} {zf:.5f}")
    for x, y in verts2d:
        lines.append(f"v {x:.5f} {y:.5f} {zb:.5f}")
    # UV: หน้าเสื้อ = ตำแหน่งเดียวกับใน texture, หลัง/ข้าง = จุดผ้าเรียบ ๆ ใกล้ชายเสื้อ
    for x, y in pts:
        lines.append(f"vt {x / 512:.5f} {1 - y / 512:.5f}")
    lines.append(f"vt {256 / 512:.5f} {1 - 440 / 512:.5f}")
    plain_uv = n + 1
    lines += ["vn 0 0 -1", "vn 0 0 1"]
    for a, b, c in tris:
        # หน้า (-Z): มองจาก -Z ต้องทวนเข็ม = กลับลำดับ เพราะแกน x กลับด้านเมื่อมองจากด้านหน้า
        lines.append(f"f {a + 1}/{a + 1}/1 {c + 1}/{c + 1}/1 {b + 1}/{b + 1}/1")
        lines.append(f"f {a + 1 + n}/{plain_uv}/2 {b + 1 + n}/{plain_uv}/2 {c + 1 + n}/{plain_uv}/2")
    # ผนังด้านข้าง
    normals = []
    for i in range(n):
        j = (i + 1) % n
        (x0, y0), (x1, y1) = verts2d[i], verts2d[j]
        dx, dy = x1 - x0, y1 - y0
        length = math.hypot(dx, dy) or 1
        # เส้นรอบรูปเรียงตาม pts (ทวนหรือตามเข็ม) → เลือกทิศออกนอกจากพื้นที่
        sign = 1 if area(verts2d) > 0 else -1
        nx, ny = sign * dy / length, -sign * dx / length
        normals.append(f"vn {nx:.5f} {ny:.5f} 0")
    lines += normals
    for i in range(n):
        j = (i + 1) % n
        vn = 3 + i
        fi, fj, bi, bj = i + 1, j + 1, i + 1 + n, j + 1 + n
        # เลือกลำดับให้ normal ของสามเหลี่ยมชี้ออกนอก
        (x0, y0), (x1, y1) = verts2d[i], verts2d[j]
        p_fi, p_fj, p_bi = (x0, y0, zf), (x1, y1, zf), (x0, y0, zb)
        u = [p_fj[t] - p_fi[t] for t in range(3)]
        v = [p_bi[t] - p_fi[t] for t in range(3)]
        cn = (u[1] * v[2] - u[2] * v[1], u[2] * v[0] - u[0] * v[2])
        sign = 1 if area(verts2d) > 0 else -1
        out = (sign * (y1 - y0), -sign * (x1 - x0))
        if cn[0] * out[0] + cn[1] * out[1] >= 0:
            lines.append(f"f {fi}/{plain_uv}/{vn} {fj}/{plain_uv}/{vn} {bj}/{plain_uv}/{vn}")
            lines.append(f"f {fi}/{plain_uv}/{vn} {bj}/{plain_uv}/{vn} {bi}/{plain_uv}/{vn}")
        else:
            lines.append(f"f {fi}/{plain_uv}/{vn} {bj}/{plain_uv}/{vn} {fj}/{plain_uv}/{vn}")
            lines.append(f"f {fi}/{plain_uv}/{vn} {bi}/{plain_uv}/{vn} {bj}/{plain_uv}/{vn}")
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    return len(tris)


def main():
    for d in (OUT_SVG, OUT_PNG, OUT_TEE, OUT_MESH):
        os.makedirs(d, exist_ok=True)
    chrome = find_chrome()

    # 1) ลายหน้าอก (PNG โปร่งใส)
    for template_id, rarity, _name, fn in DESIGNS:
        if fn is None:
            continue  # เสื้อเปล่า ไม่มีลายหน้าอก
        svg_path = os.path.join(OUT_SVG, template_id + ".svg")
        with open(svg_path, "w", encoding="utf-8") as f:
            f.write(fn())
        html_path = os.path.join(OUT_SVG, "_render.html")
        with open(html_path, "w", encoding="utf-8") as f:
            f.write(
                "<html><body style='margin:0;background:transparent'>"
                f"<img src='{template_id}.svg' width='512' height='512'></body></html>"
            )
        screenshot(chrome, html_path, os.path.join(OUT_PNG, png_name(template_id, rarity)), 512, 512)
        print("ok print", template_id)
    os.remove(os.path.join(OUT_SVG, "_render.html"))

    # 2) เสื้อทั้งตัว (ใช้เป็น texture ของโมเดล + รูปบนการ์ด)
    for template_id, rarity, _name, _fn in DESIGNS:
        html_path = os.path.join(OUT_TEE, "_render.html")
        with open(html_path, "w", encoding="utf-8") as f:
            f.write(tee_texture_html(template_id, rarity))
        screenshot(chrome, html_path, os.path.join(OUT_TEE, "tee_" + png_name(template_id, rarity)), 512, 512)
        print("ok tee", template_id)
    os.remove(os.path.join(OUT_TEE, "_render.html"))

    # 3) โมเดลเสื้อ 3D
    tri_count = write_tee_obj(os.path.join(OUT_MESH, "tee.obj"))
    print("ok mesh", tri_count, "front triangles")

    # 4) preview
    cards = ""
    for template_id, rarity, name, _fn in DESIGNS:
        color = RARITY_COLORS[rarity]
        cards += (
            f"<div class='card' style='border-color:{color}'>"
            f"<img class='tee' src='tee/tee_{png_name(template_id, rarity)}'>"
            f"<div class='name'>{name}</div><div class='rarity' style='color:{color}'>{rarity}</div></div>"
        )
    html = (
        "<html><head><meta charset='utf-8'><style>"
        "body{margin:0;background:#141210;font-family:Segoe UI,Arial;padding:24px}"
        ".grid{display:grid;grid-template-columns:repeat(5,300px);gap:20px}"
        ".card{position:relative;background:#3a3532;border:4px solid;border-radius:14px;height:380px}"
        ".tee{position:absolute;left:10px;top:6px;width:280px;height:280px}"
        ".name{position:absolute;bottom:38px;width:100%;text-align:center;color:#fff;font-weight:700;font-size:18px}"
        ".rarity{position:absolute;bottom:12px;width:100%;text-align:center;font-weight:800;font-size:16px}"
        "</style></head><body><div class='grid'>" + cards + "</div></body></html>"
    )
    preview_html = os.path.join(ROOT, "shirts", "_preview.html")
    with open(preview_html, "w", encoding="utf-8") as f:
        f.write(html)
    screenshot(chrome, preview_html, os.path.join(ROOT, "shirts", "preview.png"), 5 * 300 + 4 * 20 + 48, ((len(DESIGNS) + 4) // 5) * 400 + 28)
    os.remove(preview_html)
    print("ok preview")


if __name__ == "__main__":
    main()
