#!/usr/bin/env python3
"""Витрина App Store в стиле топовых транспортных приложений (Kyiv Digital,
Citymapper, Transit): телефон в корпусе-рамке, акцентное слово в цвете линии,
декор «схема метро», плавающие элементы (Dynamic Island, банер сповіщення),
фінальний бренд-слайд. Выход 1320×2868 (iPhone 6.9")."""
from PIL import Image, ImageDraw, ImageFilter, ImageFont
from pathlib import Path

W, H = 1320, 2868
ROOT = Path(__file__).parent.parent
SHOTS = ROOT / "AppStore" / "screenshots"
OUT = SHOTS / "framed"
OUT.mkdir(exist_ok=True)
ICON = ROOT / "App" / "Assets.xcassets" / "AppIcon.appiconset" / "icon1024.png"

RED, BLUE, GREEN = (237, 28, 36), (0, 114, 188), (0, 166, 81)
BG_TOP, BG_BOT = (14, 15, 18), (22, 24, 30)
TEXT_DIM = (255, 255, 255, 150)

def font(size, bold=True):
    candidates = ([("/System/Library/Fonts/Supplemental/Arial Bold.ttf", 0),
                   ("/System/Library/Fonts/HelveticaNeue.ttc", 12),
                   ("/System/Library/Fonts/Helvetica.ttc", 1)] if bold else
                  [("/System/Library/Fonts/Supplemental/Arial.ttf", 0),
                   ("/System/Library/Fonts/HelveticaNeue.ttc", 0),
                   ("/System/Library/Fonts/Helvetica.ttc", 0)])
    for path, index in candidates:
        try:
            return ImageFont.truetype(path, size, index=index)
        except OSError:
            continue
    raise SystemExit("не знайдено шрифт із кирилицею")

def rounded(img, radius):
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, *img.size], radius=radius, fill=255)
    img = img.convert("RGBA")
    img.putalpha(mask)
    return img

# MARK: фон: градиент + мягкое свечение акцента + водяная «М»

def make_canvas(accent, extra_glows=()):
    base = Image.new("RGB", (W, H))
    d = ImageDraw.Draw(base)
    for y in range(H):
        t = y / H
        d.line([(0, y), (W, y)], fill=tuple(
            int(a + (b - a) * t) for a, b in zip(BG_TOP, BG_BOT)))
    base = base.convert("RGBA")

    glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.ellipse([-420, -340, 760, 660], fill=accent + (80,))
    for (gx, gy, color) in extra_glows:
        gd.ellipse([gx - 420, gy - 360, gx + 420, gy + 360], fill=color + (55,))
    glow = glow.filter(ImageFilter.GaussianBlur(210))
    base.alpha_composite(glow)

    wm = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(wm).text((830, -190), "М", font=font(820), fill=(255, 255, 255, 11))
    base.alpha_composite(wm)
    return base

# MARK: шапка слайда

def brand_row(canvas):
    d = ImageDraw.Draw(canvas)
    d.rounded_rectangle([90, 126, 156, 192], radius=17, fill=RED)
    fm = font(44)
    mw = d.textlength("М", font=fm)
    d.text((90 + (66 - mw) / 2, 136), "М", font=fm, fill=(255, 255, 255))
    d.text((178, 140), "Метро-таймер", font=font(42), fill=(255, 255, 255, 210))

def fit_font(draw, text, size, max_w=1140, bold=True):
    f = font(size, bold)
    while draw.textlength(text, font=f) > max_w and size > 40:
        size -= 4
        f = font(size, bold)
    return f

def header(canvas, h1, h2, accent, sub, badges=False):
    d = ImageDraw.Draw(canvas)
    brand_row(canvas)
    f1 = fit_font(d, h1, 126)
    f2 = fit_font(d, h2, 126)
    d.text((90, 252), h1, font=f1, fill=(255, 255, 255))
    d.text((90, 402), h2, font=f2, fill=accent)
    d.text((90, 570), sub, font=fit_font(d, sub, 52, bold=False), fill=TEXT_DIM)
    if badges:
        x = 90
        fb = font(40)
        for label, dot in [("Працює в тунелі", RED), ("Без реклами", BLUE), ("Безкоштовно", GREEN)]:
            tw = d.textlength(label, font=fb)
            bw = int(tw) + 96
            d.rounded_rectangle([x, 668, x + bw, 748], radius=40,
                                outline=(255, 255, 255, 56), width=3)
            d.ellipse([x + 30, 694, x + 58, 722], fill=dot)
            d.text((x + 72, 686), label, font=fb, fill=(255, 255, 255, 205))
            x += bw + 22
    return canvas

# MARK: декор «схема метро» — линия со станциями позади телефона

def metro_line(canvas, accent, y):
    layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    d.line([(-30, y + 16), (1350, y - 20)], fill=accent + (85,), width=12)
    for i, x in enumerate((120, 400, 680, 960, 1240)):
        cy = y + 16 - int(36 * (x + 30) / 1380)
        if i == 3:
            d.ellipse([x - 26, cy - 26, x + 26, cy + 26], outline=accent + (220,), width=7)
            d.ellipse([x - 11, cy - 11, x + 11, cy + 11], fill=(255, 255, 255, 235))
        else:
            d.ellipse([x - 13, cy - 13, x + 13, cy + 13], fill=accent + (190,))
    canvas.alpha_composite(layer)

# MARK: телефон в корпусе

def phone_body(shot_path, width_px):
    shot = Image.open(shot_path).convert("RGB")
    scale = width_px / shot.width
    shot = shot.resize((width_px, int(shot.height * scale)), Image.LANCZOS)
    shot = rounded(shot, 88)
    pad = 26
    body = Image.new("RGBA", (shot.width + pad * 2, shot.height + pad * 2), (0, 0, 0, 0))
    d = ImageDraw.Draw(body)
    d.rounded_rectangle([0, 0, body.width - 1, body.height - 1], radius=116,
                        fill=(23, 25, 30, 255))
    d.rounded_rectangle([0, 0, body.width - 1, body.height - 1], radius=116,
                        outline=(74, 79, 90, 255), width=4)
    body.paste(shot, (pad, pad), shot)
    return body

def paste_with_shadow(canvas, body, x, y):
    alpha = body.split()[3].point(lambda a: int(a * 0.6))
    shadow = Image.new("RGBA", body.size, (0, 0, 0, 255))
    shadow.putalpha(alpha)
    shadow = shadow.filter(ImageFilter.GaussianBlur(46))
    canvas.alpha_composite(shadow, (x - 6, y + 34))
    canvas.alpha_composite(body, (x, y))

def add_phone(canvas, shot_path, y, angle=0, width_px=1108):
    body = phone_body(SHOTS / shot_path, width_px)
    if angle:
        body = body.rotate(angle, expand=True, resample=Image.BICUBIC)
    paste_with_shadow(canvas, body, (W - body.width) // 2, y)

# MARK: плавающие элементы

def float_card(canvas, card, y, glow_color, radius=None):
    """Карточка поверх телефона: свечение + тонкая обводка."""
    if radius is None:
        radius = card.height // 2
    x = (W - card.width) // 2
    glow = Image.new("RGBA", (card.width + 240, card.height + 240), (0, 0, 0, 0))
    ImageDraw.Draw(glow).rounded_rectangle(
        [120, 120, 120 + card.width, 120 + card.height],
        radius=radius, fill=glow_color + (110,))
    glow = glow.filter(ImageFilter.GaussianBlur(70))
    canvas.alpha_composite(glow, (x - 120, y - 120))
    canvas.alpha_composite(card, (x, y))
    d = ImageDraw.Draw(canvas)
    d.rounded_rectangle([x, y, x + card.width, y + card.height],
                        radius=radius, outline=(255, 255, 255, 48), width=3)

def island_card(width_px=920):
    """Реальные пиксели Dynamic Island из скриншота симулятора."""
    src = Image.open(SHOTS / "store_4_island.png").crop((340, 28, 1015, 160))
    scale = width_px / src.width
    src = src.resize((width_px, int(src.height * scale)), Image.LANCZOS)
    return rounded(src, src.height // 2)

def banner_card(width_px=1040):
    """Реальный системный банер сповіщення (кроп скриншота симулятора)."""
    src = Image.open(SHOTS / "banner_real.png")
    scale = width_px / src.width
    src = src.resize((width_px, int(src.height * scale)), Image.LANCZOS)
    # скругление углов самого банера ≈ четверть его высоты
    return rounded(src, src.height // 4)

# MARK: слайды 1–4 (телефон)

def phone_slide(out, shot, h1, h2, accent, sub, badges=False, angle=0.0,
                float_maker=None, phone_y=780):
    c = make_canvas(accent)
    # линия-декор чуть выше телефона — не пересекается ни с бейджами, ни с текстом
    metro_line(c, accent, y=phone_y - 55)
    add_phone(c, shot, phone_y, angle=angle)
    header(c, h1, h2, accent, sub, badges=badges)
    if float_maker:
        card = float_maker()
        if card is not None:
            radius = card.height // 4 if float_maker is banner_card else None
            float_card(c, card, phone_y - 120, accent, radius=radius)
    c.convert("RGB").save(OUT / out, "PNG")
    print("ok", out)

# MARK: слайд 5 — бренд/офлайн

def brand_slide(out="store_5_offline.png"):
    c = make_canvas(RED, extra_glows=[(1100, 300, BLUE), (200, 2600, GREEN)])
    d = ImageDraw.Draw(c)

    icon = Image.open(ICON).convert("RGB").resize((560, 560), Image.LANCZOS)
    icon = rounded(icon, 126)
    paste_with_shadow(c, icon, (W - 560) // 2, 430)

    fz = font(122)
    y = 1180
    for word, rest, color in [("Нуль", " реклами.", RED),
                              ("Нуль", " трекінгу.", BLUE),
                              ("Нуль", " серверів.", GREEN)]:
        ww = d.textlength(word, font=fz)
        rw = d.textlength(rest, font=fz)
        x = (W - ww - rw) / 2
        d.text((x, y), word, font=fz, fill=color)
        d.text((x + ww, y), rest, font=fz, fill=(255, 255, 255))
        y += 168

    sub = "Відлік працює без інтернету — навіть у тунелі."
    fs = fit_font(d, sub, 52, max_w=1160, bold=False)
    d.text(((W - d.textlength(sub, font=fs)) / 2, y + 60), sub, font=fs, fill=TEXT_DIM)
    sub2 = "Безкоштовно · Без реєстрації · Українською"
    fs2 = fit_font(d, sub2, 44, max_w=1100, bold=False)
    d.text(((W - d.textlength(sub2, font=fs2)) / 2, y + 150), sub2, font=fs2,
           fill=(255, 255, 255, 110))

    # фирменные три линии внизу
    for i, color in enumerate((RED, BLUE, GREEN)):
        lw = 260 - i * 60
        d.rounded_rectangle([(W - lw) / 2, 2560 + i * 34, (W + lw) / 2, 2560 + i * 34 + 14],
                            radius=7, fill=color)
    name = "Метро-таймер: Київ"
    fn = font(48)
    d.text(((W - d.textlength(name, font=fn)) / 2, 2680), name, font=fn,
           fill=(255, 255, 255, 220))
    c.convert("RGB").save(OUT / out, "PNG")
    print("ok", out)

phone_slide("store_1_trip.png", "store_2_trip.png",
            "Не проспи", "свою станцію", RED,
            "Вібрація за одну зупинку до виходу",
            badges=True, float_maker=banner_card, phone_y=940)
phone_slide("store_2_island.png", "store_2_trip.png",
            "Відлік у", "Dynamic Island", BLUE,
            "Зупинки й час — не відкриваючи застосунок",
            float_maker=island_card, phone_y=1060)
phone_slide("store_3_pick.png", "store_1_main.png",
            "Обери станції —", "і поїхали", GREEN,
            "Маршрут і сповіщення — за два дотики", angle=-2.4)
phone_slide("store_4_transfer.png", "store_3_transfer.png",
            "Пересадки", "будує сам", RED,
            "Перехід між лініями вже в розрахунку", angle=2.4)
brand_slide()
print("done ->", OUT)
