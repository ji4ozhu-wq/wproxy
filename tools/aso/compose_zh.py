#!/usr/bin/env python3
"""Chinese (zh-Hans) Aurora store screenshots using the real Chinese app UI."""
import os
from PIL import Image, ImageDraw, ImageFont

import compose_variants as cv

ROOT = cv.ROOT
CANVAS_W, CANVAS_H = cv.CANVAS_W, cv.CANVAS_H
CJK_FONT = "/System/Library/Fonts/Hiragino Sans GB.ttc"
OUT = os.path.join(ROOT, "应用商店信息", "商店5图-中文")
RAW = os.path.join(ROOT, "screenshots", "store-zh-raw")

SHOTS = [
    ("01-home", "一键连接", "连接你的私有服务器", "01-home.png"),
    ("02-nodes", "节点管理", "按延迟自动排序", "02-nodes.png"),
    ("03-routing", "智能分流", "只代理你需要的流量", "04-routing.png"),
    ("04-import", "快速导入", "扫码、链接或订阅", "03-add-node.png"),
    ("05-subscriptions", "订阅同步", "节点与流量保持最新", "05-subscriptions.png"),
]


def cjk(size, weight=2):
    return ImageFont.truetype(CJK_FONT, size, index=weight)


def fit(draw, text, max_width, start, minimum):
    for size in range(start, minimum - 1, -2):
        f = cjk(size)
        if draw.textlength(text, font=f) <= max_width:
            return f
    return cjk(minimum)


def wrap_chars(draw, text, f, max_width):
    lines, current = [], ""
    for ch in text:
        candidate = current + ch
        if draw.textlength(candidate, font=f) <= max_width:
            current = candidate
        else:
            if current:
                lines.append(current)
            current = ch
    if current:
        lines.append(current)
    return lines


def centered(draw, y, text, f, fill, max_width=None):
    lines = wrap_chars(draw, text, f, max_width) if max_width else [text]
    for line in lines:
        bbox = draw.textbbox((0, 0), line, font=f)
        draw.text(((CANVAS_W - (bbox[2] - bbox[0])) / 2, y), line, font=f, fill=fill)
        y += (bbox[3] - bbox[1]) + 6
    return y


def compose(slug, verb, desc, raw_name):
    shot = os.path.join(RAW, raw_name)
    canvas = cv.background_pastel()
    draw = ImageDraw.Draw(canvas)
    fill = (14, 21, 37, 255)
    desc_fill = (44, 54, 76, 255)

    verb_font = fit(draw, verb, int(CANVAS_W * 0.8), 276, 188)
    bbox = draw.textbbox((0, 0), verb, font=verb_font)
    y = 196
    draw.text(((CANVAS_W - (bbox[2] - bbox[0])) / 2, y), verb, font=verb_font, fill=fill)
    y += bbox[3] + 30

    desc_font = cjk(96, weight=2)
    y = centered(draw, y, desc, desc_font, desc_fill, int(CANVAS_W * 0.82))
    # If the description is unusually tall, pull the device down is not possible;
    # the current copy fits comfortably above y=830.
    cv.DEVICE_TOP = 850
    cv.paste_device(canvas, shot, shadow_colour=(80, 58, 105))
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, f"{slug}.jpg")
    canvas.convert("RGB").save(path, "JPEG", quality=92, subsampling=1)
    return path


def main():
    files = [compose(*shot) for shot in SHOTS]
    tw, th = 264, 574
    sheet = Image.new("RGB", (tw * 5, th + 20), (245, 245, 245))
    for i, f in enumerate(files):
        im = Image.open(f).convert("RGB")
        im.thumbnail((tw, th))
        sheet.paste(im, (i * tw + (tw - im.width) // 2, 10))
    sheet.save(os.path.join(ROOT, "应用商店信息", "商店5图-中文-预览.jpg"), "JPEG", quality=90)
    print("\n".join(files))
    print("preview:", os.path.join(ROOT, "应用商店信息", "商店5图-中文-预览.jpg"))


if __name__ == "__main__":
    main()
