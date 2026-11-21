#!/usr/bin/env python3
"""Compose a Wuji App Store screenshot on a locally rendered pastel background.

The gpt-image-2 edit pass kept changing the output aspect ratio (and cropped the
headline), so the pastel background is generated deterministically here and the
headline/device are composited with the exact 1290×2796 layout from compose.py.
"""
import argparse
import os
import sys

from PIL import Image, ImageDraw, ImageFilter

sys.path.insert(0, os.path.dirname(__file__))
import compose  # noqa: E402

CANVAS_W, CANVAS_H = compose.CANVAS_W, compose.CANVAS_H
TEXT_COLOUR = (16, 22, 38, 255)


def build_background() -> Image.Image:
    bg = Image.new("RGBA", (CANVAS_W, CANVAS_H))
    draw = ImageDraw.Draw(bg)
    top, bottom = (234, 242, 255), (246, 236, 255)
    for y in range(CANVAS_H):
        t = y / (CANVAS_H - 1)
        color = tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3)) + (255,)
        draw.line([(0, y), (CANVAS_W, y)], fill=color)

    blobs = Image.new("RGBA", (CANVAS_W, CANVAS_H), (0, 0, 0, 0))
    bd = ImageDraw.Draw(blobs)
    bd.ellipse([-260, 120, 420, 720], fill=(255, 214, 231, 110))       # pink, left
    bd.ellipse([CANVAS_W - 460, 380, CANVAS_W + 200, 1080], fill=(201, 220, 255, 140))
    bd.ellipse([-300, 1500, 380, 2200], fill=(227, 212, 255, 100))
    bd.ellipse([CANVAS_W - 520, 1900, CANVAS_W + 260, 2750], fill=(255, 228, 240, 120))
    blobs = blobs.filter(ImageFilter.GaussianBlur(150))
    bg = Image.alpha_composite(bg, blobs)

    # Small four-point sparkles.
    sp = Image.new("RGBA", (CANVAS_W, CANVAS_H), (0, 0, 0, 0))
    sd = ImageDraw.Draw(sp)
    for (x, y, r, a) in [(128, 520, 9, 200), (1130, 300, 11, 190), (240, 1180, 7, 170),
                         (1080, 880, 8, 160), (120, 2280, 8, 150), (1160, 2380, 10, 170)]:
        sd.polygon([(x, y - r), (x + r * 0.22, y - r * 0.22), (x + r, y),
                    (x + r * 0.22, y + r * 0.22), (x, y + r),
                    (x - r * 0.22, y + r * 0.22), (x - r, y),
                    (x - r * 0.22, y - r * 0.22)], fill=(255, 255, 255, a))
    sp = sp.filter(ImageFilter.GaussianBlur(0.6))
    return Image.alpha_composite(bg, sp)


def build_image(verb: str, desc: str, screenshot_path: str, output_path: str) -> None:
    canvas = build_background()
    draw = ImageDraw.Draw(canvas)
    compose.TEXT_COLOUR = TEXT_COLOUR

    verb_font = compose.fit_font(verb.upper(), compose.MAX_VERB_W,
                                 compose.VERB_SIZE_MAX, compose.VERB_SIZE_MIN)
    desc_font = Image.new  # placeholder to keep flake quiet
    desc_font = compose.ImageFont.truetype(compose.FONT_PATH, compose.DESC_SIZE)

    y = 200
    y = compose.draw_centered(draw, y, verb.upper(), verb_font)
    y += compose.VERB_DESC_GAP
    compose.draw_centered(draw, y, desc.upper(), desc_font, max_w=compose.MAX_TEXT_W)

    device_x = (CANVAS_W - compose.DEVICE_W) // 2
    screen_x = device_x + compose.BEZEL
    screen_y = compose.DEVICE_Y + compose.BEZEL

    shot = Image.open(screenshot_path).convert("RGBA")
    scale = compose.SCREEN_W / shot.width
    shot = shot.resize((compose.SCREEN_W, int(shot.height * scale)), Image.LANCZOS)
    screen_h = CANVAS_H - screen_y + 500

    scr_mask = Image.new("L", canvas.size, 0)
    ImageDraw.Draw(scr_mask).rounded_rectangle(
        [screen_x, screen_y, screen_x + compose.SCREEN_W, screen_y + screen_h],
        radius=compose.SCREEN_CORNER_R, fill=255)

    scr_layer = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    ImageDraw.Draw(scr_layer).rounded_rectangle(
        [screen_x, screen_y, screen_x + compose.SCREEN_W, screen_y + screen_h],
        radius=compose.SCREEN_CORNER_R, fill=(0, 0, 0, 255))
    scr_layer.paste(shot, (screen_x, screen_y))
    scr_layer.putalpha(scr_mask)
    canvas = Image.alpha_composite(canvas, scr_layer)

    frame = Image.open(compose.FRAME_PATH).convert("RGBA")
    frame_layer = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    frame_layer.paste(frame, (device_x, compose.DEVICE_Y))
    canvas = Image.alpha_composite(canvas, frame_layer)

    canvas.convert("RGB").save(output_path, "PNG")
    print(f"✓ {output_path} ({CANVAS_W}×{CANVAS_H})")


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("--verb", required=True)
    p.add_argument("--desc", required=True)
    p.add_argument("--screenshot", required=True)
    p.add_argument("--output", required=True)
    a = p.parse_args()
    build_image(a.verb, a.desc, a.screenshot, a.output)
