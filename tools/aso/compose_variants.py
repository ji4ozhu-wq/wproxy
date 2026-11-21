#!/usr/bin/env python3
"""Generate App Store 5-shot sets in three visual directions.

Deterministic Pillow composition (no generative model): background, typography,
device frame and the real app screenshot are composited at exactly 1320x2868.
"""
import math
import os
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CANVAS_W, CANVAS_H = 1320, 2868
FRAME_PATH = os.path.join(ROOT, "tools", "aso", "assets", "device_frame.png")
FONT_PATH = "/Library/Fonts/SF-Pro-Display-Black.otf"

DEVICE_W = 1100
DEVICE_TOP = 830

SHOTS = [
    ("01-home", "CONNECT", "TO YOUR OWN SERVER IN ONE TAP", "01-home.png"),
    ("02-nodes", "MANAGE", "EVERY SERVER, SORTED BY SPEED", "02-nodes.png"),
    ("03-routing", "ROUTE", "ONLY THE TRAFFIC YOU CHOOSE", "04-routing.png"),
    ("04-import", "IMPORT", "QR CODE, LINK, OR SUBSCRIPTION", "03-add-node.png"),
    ("05-subscriptions", "SYNC", "SUBSCRIPTIONS THAT STAY FRESH", "05-subscriptions.png"),
]
RAW_DIR = os.path.join(ROOT, "screenshots", "store-raw")
OUT_ROOT = os.path.join(ROOT, "应用商店信息", "商店5图-候选")


def font(size):
    return ImageFont.truetype(FONT_PATH, size)


def wrap(draw, text, fnt, max_width):
    words = text.split()
    lines, current = [], ""
    for word in words:
        candidate = f"{current} {word}".strip()
        if draw.textlength(candidate, font=fnt) <= max_width:
            current = candidate
        else:
            if current:
                lines.append(current)
            current = word
    if current:
        lines.append(current)
    return lines


def fit_text(draw, text, max_width, start, minimum):
    for size in range(start, minimum - 1, -2):
        fnt = font(size)
        if draw.textlength(text, font=fnt) <= max_width:
            return fnt
    return font(minimum)


def centered_block(draw, top, verb, desc, max_width, verb_color, desc_color, desc_size=108):
    verb_font = fit_text(draw, verb, max_width, 252, 166)
    bbox = draw.textbbox((0, 0), verb, font=verb_font)
    x = (CANVAS_W - (bbox[2] - bbox[0])) / 2
    draw.text((x, top), verb, font=verb_font, fill=verb_color)
    y = top + bbox[3] + 26

    desc_font = font(desc_size)
    for line in wrap(draw, desc, desc_font, max_width)[:2]:
        bbox = draw.textbbox((0, 0), line, font=desc_font)
        draw.text(((CANVAS_W - (bbox[2] - bbox[0])) / 2, y), line,
                  font=desc_font, fill=desc_color)
        y += (bbox[3] - bbox[1]) + 8
    return y


def load_device_assets():
    frame_original = Image.open(FRAME_PATH).convert("RGBA")
    scale = DEVICE_W / frame_original.width
    frame = frame_original.resize(
        (DEVICE_W, int(frame_original.height * scale)), Image.LANCZOS
    )
    bezel = int(round(15 * scale))
    screen_w = DEVICE_W - 2 * bezel
    screen_h = frame.height - 2 * bezel
    x = (CANVAS_W - DEVICE_W) // 2
    y = DEVICE_TOP
    return frame, x, y, bezel, screen_w, screen_h


def paste_device(canvas, shot_path, shadow_colour=(0, 0, 0), glow=None):
    frame, x, y, bezel, screen_w, screen_h = load_device_assets()

    # soft shadow / optional glow under the device
    if glow:
        layer = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
        d = ImageDraw.Draw(layer)
        d.rounded_rectangle(
            [x - 70, y - 30, x + DEVICE_W + 70, y + frame.height - 120],
            radius=90, fill=glow,
        )
        layer = layer.filter(ImageFilter.GaussianBlur(110))
        canvas.alpha_composite(layer)

    shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle(
        [x + 20, y + 30, x + DEVICE_W + 20, y + frame.height - 20],
        radius=90, fill=(*shadow_colour, 95),
    )
    shadow = shadow.filter(ImageFilter.GaussianBlur(38))
    canvas.alpha_composite(shadow)

    shot = Image.open(shot_path).convert("RGBA")
    scale = screen_w / shot.width
    shot = shot.resize((screen_w, int(shot.height * scale)), Image.LANCZOS)

    screen = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    mask = Image.new("L", canvas.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [x + bezel, y + bezel, x + bezel + screen_w, y + bezel + screen_h],
        radius=int(62 * DEVICE_W / 1030), fill=255,
    )
    black = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    ImageDraw.Draw(black).rounded_rectangle(
        [x + bezel, y + bezel, x + bezel + screen_w, y + bezel + screen_h],
        radius=int(62 * DEVICE_W / 1030), fill=(0, 0, 0, 255),
    )
    screen.alpha_composite(black)
    screen.paste(shot, (x + bezel, y + bezel))
    screen.putalpha(mask)
    canvas.alpha_composite(screen)

    frame_layer = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    frame_layer.paste(frame, (x, y))
    canvas.alpha_composite(frame_layer)


def vertical_gradient(top, bottom):
    im = Image.new("RGBA", (CANVAS_W, CANVAS_H))
    d = ImageDraw.Draw(im)
    for yy in range(CANVAS_H):
        t = yy / (CANVAS_H - 1)
        colour = tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3)) + (255,)
        d.line([(0, yy), (CANVAS_W, yy)], fill=colour)
    return im


def sparkle(draw, x, y, r, alpha):
    draw.polygon([
        (x, y - r), (x + r * 0.22, y - r * 0.22), (x + r, y),
        (x + r * 0.22, y + r * 0.22), (x, y + r),
        (x - r * 0.22, y + r * 0.22), (x - r, y),
        (x - r * 0.22, y - r * 0.22),
    ], fill=(255, 255, 255, alpha))


def background_pastel():
    canvas = vertical_gradient((231, 240, 255), (247, 236, 255))
    blobs = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(blobs)
    d.ellipse([-260, 100, 460, 760], fill=(255, 214, 231, 120))
    d.ellipse([CANVAS_W - 500, 380, CANVAS_W + 220, 1120], fill=(196, 218, 255, 150))
    d.ellipse([-320, 1450, 420, 2260], fill=(225, 211, 255, 110))
    d.ellipse([CANVAS_W - 540, 1900, CANVAS_W + 280, 2790], fill=(255, 227, 239, 135))
    blobs = blobs.filter(ImageFilter.GaussianBlur(170))
    canvas.alpha_composite(blobs)
    sparkles = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    sd = ImageDraw.Draw(sparkles)
    for x, y, r, a in [(120, 520, 8, 190), (1190, 300, 10, 180), (220, 1240, 6, 150),
                       (1120, 900, 7, 140), (130, 2320, 7, 130), (1190, 2440, 9, 150)]:
        sparkle(sd, x, y, r, a)
    canvas.alpha_composite(sparkles.filter(ImageFilter.GaussianBlur(0.5)))
    return canvas


def background_midnight():
    canvas = vertical_gradient((5, 9, 22), (13, 24, 48))
    glows = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(glows)
    d.ellipse([-360, -160, 760, 920], fill=(31, 224, 132, 48))
    d.ellipse([CANVAS_W - 640, 260, CANVAS_W + 320, 1240], fill=(48, 121, 255, 58))
    d.ellipse([-400, 1700, 740, 2900], fill=(33, 195, 158, 34))
    glows = glows.filter(ImageFilter.GaussianBlur(190))
    canvas.alpha_composite(glows)
    grid = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    gd = ImageDraw.Draw(grid)
    for x in range(0, CANVAS_W, 88):
        gd.line([(x, 0), (x, CANVAS_H)], fill=(255, 255, 255, 5), width=1)
    canvas.alpha_composite(grid)
    return canvas


def background_cream():
    canvas = vertical_gradient((248, 243, 234), (238, 230, 217))
    # very subtle paper grain
    grain = Image.effect_noise((CANVAS_W, CANVAS_H), 9).convert("L")
    grain = grain.filter(ImageFilter.GaussianBlur(0.4))
    overlay = Image.new("RGBA", canvas.size, (120, 96, 60, 0))
    overlay.putalpha(grain.point(lambda v: int(v * 0.06)))
    canvas.alpha_composite(overlay)
    accent = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    ad = ImageDraw.Draw(accent)
    ad.ellipse([CANVAS_W - 420, -300, CANVAS_W + 240, 420], fill=(208, 106, 60, 28))
    ad.ellipse([-300, CANVAS_H - 680, 360, CANVAS_H + 120], fill=(38, 86, 84, 20))
    accent = accent.filter(ImageFilter.GaussianBlur(120))
    canvas.alpha_composite(accent)
    return canvas


def compose_variant(variant, slug, verb, desc, raw_file):
    shot_path = os.path.join(RAW_DIR, raw_file)
    canvas = (background_pastel() if variant == "aurora"
              else background_midnight() if variant == "midnight"
              else background_cream())
    draw = ImageDraw.Draw(canvas)

    if variant == "aurora":
        centered_block(draw, 180, verb, desc, int(CANVAS_W * 0.86),
                       (15, 22, 38, 255), (46, 56, 78, 255), 106)
        paste_device(canvas, shot_path, shadow_colour=(80, 58, 105))
    elif variant == "midnight":
        # accent rule + overline
        draw.rounded_rectangle([CANVAS_W // 2 - 34, 152, CANVAS_W // 2 + 34, 160],
                               radius=4, fill=(64, 236, 146, 255))
        over = "PRIVATE NETWORKING"
        of = font(34)
        ow = draw.textlength(over, font=of)
        draw.text(((CANVAS_W - ow) / 2, 182), over, font=of, fill=(123, 228, 175, 255))
        centered_block(draw, 260, verb, desc, int(CANVAS_W * 0.86),
                       (255, 255, 255, 255), (194, 209, 230, 255), 104)
        paste_device(canvas, shot_path, shadow_colour=(0, 0, 0),
                     glow=(32, 214, 130, 40))
    else:
        draw.rectangle([92, 206, 108, 560], fill=(201, 106, 60, 255))
        index = SHOTS.index((slug, verb, desc, raw_file)) + 1
        label = f"0{index} / 05"
        lf = font(34)
        draw.text((132, 188), "WPROXY", font=lf, fill=(115, 98, 78, 255))
        lw = draw.textlength(label, font=lf)
        draw.text((CANVAS_W - 110 - lw, 188), label, font=lf, fill=(115, 98, 78, 255))
        verb_font = fit_text(draw, verb, CANVAS_W - 260, 240, 160)
        draw.text((132, 232), verb, font=verb_font, fill=(20, 24, 30, 255))
        bbox = draw.textbbox((0, 0), verb, font=verb_font)
        y = 232 + bbox[3] + 28
        desc_font = font(102)
        for line in wrap(draw, desc, desc_font, CANVAS_W - 260)[:2]:
            draw.text((132, y), line, font=desc_font, fill=(74, 66, 56, 255))
            lb = draw.textbbox((0, 0), line, font=desc_font)
            y += (lb[3] - lb[1]) + 8
        paste_device(canvas, shot_path, shadow_colour=(80, 55, 30))

    out_dir = os.path.join(OUT_ROOT, variant)
    os.makedirs(out_dir, exist_ok=True)
    out = os.path.join(out_dir, f"{slug}.jpg")
    canvas.convert("RGB").save(out, "JPEG", quality=92, subsampling=1)
    return out


def make_contact_sheet(variant, files):
    thumb_w, thumb_h = 264, 574
    sheet = Image.new("RGB", (thumb_w * 5, thumb_h + 20), (245, 245, 245))
    for i, f in enumerate(files):
        im = Image.open(f).convert("RGB")
        im.thumbnail((thumb_w, thumb_h))
        sheet.paste(im, (i * thumb_w + (thumb_w - im.width) // 2, 10))
    out = os.path.join(OUT_ROOT, f"{variant}-预览.jpg")
    os.makedirs(OUT_ROOT, exist_ok=True)
    sheet.save(out, "JPEG", quality=90)
    return out


def main():
    if not os.path.exists(FONT_PATH):
        raise SystemExit(f"missing font: {FONT_PATH}")
    for variant in ("aurora", "midnight", "cream"):
        files = []
        for slug, verb, desc, raw in SHOTS:
            files.append(compose_variant(variant, slug, verb, desc, raw))
        preview = make_contact_sheet(variant, files)
        print(preview)


if __name__ == "__main__":
    main()
