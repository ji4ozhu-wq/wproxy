#!/usr/bin/env python3
"""Localized iPad store screenshots (Aurora) for the 10 non-English locales."""
import os
import sys
from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, os.path.dirname(__file__))
import compose_intl as ci
import compose_variants as cv

ROOT = ci.ROOT
OUT_ROOT = os.path.join(ROOT, "应用商店信息")
RAW_ROOT = os.path.join(ROOT, "screenshots", "store-ipad")
W, H = 2048, 2732
SCREENS = ["01-home", "02-nodes", "03-add-node", "04-routing", "05-subscriptions"]
OUT_NAMES = ["01-home", "02-nodes", "03-routing", "04-import", "05-subscriptions"]
RAW_NAMES = [s + ".png" for s in SCREENS]


def make_font(locale, size):
    if locale in ci.FONTS:
        path, index = ci.FONTS[locale]
        return ImageFont.truetype(path, size, index=index)
    return ImageFont.truetype(ci.SF_BLACK, size)


def wrap_words(draw, text, f, max_width):
    words, lines, cur = text.split(), [], ""
    for word in words:
        cand = f"{cur} {word}".strip()
        if draw.textlength(cand, font=f) <= max_width:
            cur = cand
        else:
            if cur: lines.append(cur)
            cur = word
    if cur: lines.append(cur)
    return lines


def wrap_chars(draw, text, f, max_width):
    lines, cur = [], ""
    for ch in text:
        cand = cur + ch
        if draw.textlength(cand, font=f) <= max_width:
            cur = cand
        else:
            if cur: lines.append(cur)
            cur = ch
    if cur: lines.append(cur)
    return lines


def draw_block(draw, y, lines, f, fill, gap=14):
    for line in lines:
        b = draw.textbbox((0, 0), line, font=f)
        draw.text(((W - (b[2] - b[0])) // 2, y - b[1]), line, font=f, fill=fill)
        y += (b[3] - b[1]) + gap
    return y


def paste_card(canvas, shot_path):
    shot = Image.open(shot_path).convert("RGBA")
    card_w = 1640
    bezel = 18
    card = shot.resize((card_w - 2 * bezel, int(shot.height * (card_w - 2 * bezel) / shot.width)), Image.LANCZOS)
    frame_w = card_w
    frame_h = card.height + 2 * bezel
    x = (W - frame_w) // 2
    card_y = 900
    shadow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle(
        [x + 24, card_y + 30, x + frame_w + 24, card_y + frame_h + 30],
        radius=100, fill=(58, 40, 78, 95),
    )
    canvas.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(45)))
    layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(layer).rounded_rectangle([x, card_y, x + frame_w, card_y + frame_h],
                                            radius=100, fill=(15, 17, 22, 255))
    mask = Image.new("L", (W, H), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [x + bezel, card_y + bezel, x + bezel + card.width, card_y + bezel + card.height],
        radius=82, fill=255,
    )
    layer.paste(card, (x + bezel, card_y + bezel))
    layer.putalpha(mask)
    canvas.alpha_composite(layer)


def compose(locale, index):
    verb, desc = ci.HEADLINES[locale][index]
    if locale not in ci.NO_SPACE_LANGS:
        verb, desc = verb.upper(), desc.upper()
    raw = os.path.join(RAW_ROOT, locale, RAW_NAMES[index])
    canvas = Image.new("RGBA", (W, H), (255, 255, 255, 255))
    # Reuse the Aurora background at iPad size by scaling the iPhone background.
    bg = cv.background_pastel().resize((W, H), Image.LANCZOS)
    canvas.alpha_composite(bg)
    draw = ImageDraw.Draw(canvas)
    fill, desc_fill = (14, 21, 37, 255), (44, 54, 76, 255)
    if locale == "th":
        # CoreText shaping for Thai, overlay above the device card.
        from compose_intl import render_thai_text, fit_width
        v = fit_width(render_thai_text(verb, 190, 1500, "/tmp/ipad-th-verb.png"), 1500)
        d = fit_width(render_thai_text(desc, 78, 1500, "/tmp/ipad-th-desc.png"), 1500)
        y = 140
        canvas.alpha_composite(v, ((W - v.width) // 2, y))
        y += v.height + 28
        canvas.alpha_composite(d, ((W - d.width) // 2, y))
    else:
        verb_font = None
        for size in range(230, 120, -2):
            f = make_font(locale, size)
            if draw.textlength(verb, font=f) <= int(W * 0.84):
                verb_font = f
                break
        verb_font = verb_font or make_font(locale, 120)
        b = draw.textbbox((0, 0), verb, font=verb_font)
        y = 140
        draw.text(((W - (b[2] - b[0])) // 2, y - b[1]), verb, font=verb_font, fill=fill)
        y += (b[3] - b[1]) + 34
        for size in range(88, 46, -2):
            f = make_font(locale, size)
            wrap = wrap_chars if locale in ci.NO_SPACE_LANGS else wrap_words
            lines = wrap(draw, desc, f, int(W * 0.84))[:2]
            boxes = [draw.textbbox((0, 0), x, font=f) for x in lines]
            total = sum((bb[3] - bb[1]) for bb in boxes) + (len(lines) - 1) * 12
            if y + total <= 870:
                break
        draw_block(draw, y, lines, f, desc_fill)
    paste_card(canvas, raw)
    out_dir = os.path.join(OUT_ROOT, f"商店5图-{locale}-iPad")
    os.makedirs(out_dir, exist_ok=True)
    path = os.path.join(out_dir, OUT_NAMES[index] + ".jpg")
    canvas.convert("RGB").save(path, "JPEG", quality=92, subsampling=1)
    return path


def main():
    for locale in ("zh-Hans", "zh-Hant", "es", "fr", "de", "ja", "ko", "ru", "th", "vi"):
        files = [compose(locale, i) for i in range(5)]
        # preview
        tw, th = 264, 352
        sheet = Image.new("RGB", (tw * 5, th + 20), (245, 245, 245))
        for i, f in enumerate(files):
            im = Image.open(f).convert("RGB"); im.thumbnail((tw, th))
            sheet.paste(im, (i * tw + (tw - im.width) // 2, 10))
        sheet.save(os.path.join(OUT_ROOT, f"商店5图-{locale}-iPad-预览.jpg"), "JPEG", quality=90)
        print(locale, files[0], "...", files[-1])


if __name__ == "__main__":
    from PIL import ImageFilter
    main()
