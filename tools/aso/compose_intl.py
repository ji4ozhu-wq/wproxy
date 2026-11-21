#!/usr/bin/env python3
"""Localized Aurora store screenshots for WProxy / 无极代理."""
import os
import subprocess
import tempfile
from PIL import Image, ImageDraw, ImageFont

import compose_variants as cv

ROOT = cv.ROOT
OUT_ROOT = os.path.join(ROOT, "应用商店信息")
RAW_ROOT = os.path.join(ROOT, "screenshots", "store-intl-raw")

SF_BLACK = "/Library/Fonts/SF-Pro-Display-Black.otf"
FONTS = {
    "zh-Hans": ("/System/Library/Fonts/Hiragino Sans GB.ttc", 2),
    "zh-Hant": ("/System/Library/Fonts/STHeiti Medium.ttc", 0),
    "ja": ("/System/Library/Fonts/ヒラギノ角ゴシック W6.ttc", 0),
    "ko": ("/System/Library/Fonts/AppleSDGothicNeo.ttc", 6),
    "th": ("/System/Library/Fonts/Supplemental/Thonburi.ttc", 1),
}
NO_SPACE_LANGS = {"zh-Hans", "zh-Hant", "ja", "ko", "th"}

HEADLINES = {
    "en": [("CONNECT", "TO YOUR OWN SERVER IN ONE TAP"),
           ("MANAGE", "EVERY SERVER, SORTED BY SPEED"),
           ("ROUTE", "ONLY THE TRAFFIC YOU CHOOSE"),
           ("IMPORT", "QR CODE, LINK, OR SUBSCRIPTION"),
           ("SYNC", "SUBSCRIPTIONS THAT STAY FRESH")],
    "zh-Hans": [("一键连接", "连接你的私有服务器"),
                ("节点管理", "按延迟自动排序"),
                ("智能分流", "只代理你需要的流量"),
                ("快速导入", "扫码、链接或订阅"),
                ("订阅同步", "节点与流量保持最新")],
    "zh-Hant": [("一鍵連接", "連接你的私有伺服器"),
                ("節點管理", "依延遲自動排序"),
                ("智慧分流", "只代理你需要的流量"),
                ("快速匯入", "掃碼、連結或訂閱"),
                ("訂閱同步", "節點與流量保持最新")],
    "ja": [("ワンタップ接続", "自分のサーバーへ"),
           ("ノード管理", "遅延順に自動並べ替え"),
           ("スマート振り分け", "必要な通信だけ"),
           ("かんたんインポート", "QR・リンク・購読"),
           ("購読を同期", "常に最新のノード")],
    "ko": [("원탭 연결", "내 서버에 연결"),
           ("노드 관리", "지연 순 자동 정렬"),
           ("스마트 분할", "필요한 트래픽만"),
           ("빠른 가져오기", "QR·링크·구독"),
           ("구독 동기화", "최신 노드 유지")],
    "es": [("CONECTA", "A TU SERVIDOR EN UN TOQUE"),
           ("GESTIONA", "TODOS LOS SERVIDORES POR VELOCIDAD"),
           ("ENRUTA", "SOLO EL TRÁFICO QUE ELIGES"),
           ("IMPORTA", "QR, ENLACE O SUSCRIPCIÓN"),
           ("SINCRONIZA", "SUSCRIPCIONES SIEMPRE AL DÍA")],
    "fr": [("CONNECTEZ", "À VOTRE PROPRE SERVEUR EN UN TOUCHER"),
           ("GÉREZ", "TOUS LES SERVEURS PAR VITESSE"),
           ("ROUTEZ", "SEULEMENT LE TRAFIC CHOISI"),
           ("IMPORTEZ", "QR, LIEN OU ABONNEMENT"),
           ("SYNCHRONISEZ", "ABONNEMENTS TOUJOURS À JOUR")],
    "de": [("VERBINDEN", "MIT DEINEM EIGENEN SERVER"),
           ("VERWALTEN", "ALLE SERVER NACH GESCHWINDIGKEIT"),
           ("ROUTEN", "NUR DER AUSGEWÄHLTE TRAFFIC"),
           ("IMPORTIEREN", "QR, LINK ODER ABO"),
           ("SYNCHRONISIEREN", "ABOS IMMER AKTUELL")],
    "ru": [("ПОДКЛЮЧИСЬ", "К СВОЕМУ СЕРВЕРУ В ОДИН ТАП"),
           ("УПРАВЛЯЙ", "ВСЕМИ СЕРВЕРАМИ ПО СКОРОСТИ"),
           ("МАРШРУТИЗИРУЙ", "ТОЛЬКО НУЖНЫЙ ТРАФИК"),
           ("ИМПОРТИРУЙ", "QR, ССЫЛКА ИЛИ ПОДПИСКА"),
           ("СИНХРОНИЗИРУЙ", "ПОДПИСКИ ВСЕГДА АКТУАЛЬНЫ")],
    "th": [("เชื่อมต่อ", "เซิร์ฟเวอร์ของคุณ"),
           ("จัดการ", "ทุกเซิร์ฟเวอร์"),
           ("แยกเส้นทาง", "เฉพาะที่คุณเลือก"),
           ("นำเข้า", "QR ลิงก์ หรือการสมัคร"),
           ("ซิงก์", "การสมัครให้สดใหม่")],
    "vi": [("KẾT NỐI", "MÁY CHỦ RIÊNG CHỈ MỘT CHẠM"),
           ("QUẢN LÝ", "MỌI MÁY CHỦ THEO TỐC ĐỘ"),
           ("ĐỊNH TUYẾN", "CHỈ LƯU LƯỢNG BẠN CHỌN"),
           ("NHẬP", "MÃ QR, LIÊN KẾT HOẶC ĐĂNG KÝ"),
           ("ĐỒNG BỘ", "ĐĂNG KÝ LUÔN MỚI")],
}
SCREENS = ["01-home", "02-nodes", "03-add-node", "04-routing", "05-subscriptions"]
# Store file names keep the benefit order used by the English set.
OUT_NAMES = ["01-home", "02-nodes", "03-routing", "04-import", "05-subscriptions"]
RAW_NAMES = ["01-home.png", "02-nodes.png", "03-add-node.png", "04-routing.png", "05-subscriptions.png"]


def make_font(locale, size):
    if locale in FONTS:
        path, index = FONTS[locale]
        return ImageFont.truetype(path, size, index=index)
    return ImageFont.truetype(SF_BLACK, size)


def fit(draw, text, locale, max_width, start, minimum):
    for size in range(start, minimum - 1, -2):
        f = make_font(locale, size)
        if draw.textlength(text, font=f) <= max_width:
            return f
    return make_font(locale, minimum)


def wrap_words(draw, text, f, max_width):
    words, lines, current = text.split(), [], ""
    for word in words:
        candidate = f"{current} {word}".strip()
        if draw.textlength(candidate, font=f) <= max_width:
            current = candidate
        else:
            if current:
                lines.append(current)
            current = word
    if current:
        lines.append(current)
    return lines


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


def render_thai_text(text, size, max_width, out_path):
    subprocess.run([
        "swift", os.path.join(ROOT, "tools", "aso", "render_text.swift"),
        text, str(size), "#0E1525", str(max_width), out_path,
    ], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    im = Image.open(out_path).convert("RGBA")
    bbox = im.getbbox()
    return im.crop(bbox) if bbox else im


def fit_width(im, max_width):
    if im.width <= max_width:
        return im
    h = int(im.height * max_width / im.width)
    return im.resize((max_width, h), Image.LANCZOS)


def compose_thai(canvas, verb, desc):
    with tempfile.TemporaryDirectory() as tmp:
        v = fit_width(render_thai_text(verb, 210, 1080, os.path.join(tmp, "verb.png")), 1080)
        d = fit_width(render_thai_text(desc, 86, 1080, os.path.join(tmp, "desc.png")), 1080)
        y = 186
        canvas.alpha_composite(v, ((cv.CANVAS_W - v.width) // 2, y))
        y += v.height + 28
        canvas.alpha_composite(d, ((cv.CANVAS_W - d.width) // 2, y))


def compose(locale, index):
    verb, desc = HEADLINES[locale][index]
    if locale not in NO_SPACE_LANGS and locale not in {"zh-Hans", "zh-Hant", "ja", "ko", "th"}:
        verb, desc = verb.upper(), desc.upper()

    shot = os.path.join(RAW_ROOT, locale, RAW_NAMES[index])
    if locale == "zh-Hans":
        shot = os.path.join(ROOT, "screenshots", "store-zh-raw", RAW_NAMES[index])

    canvas = cv.background_pastel()
    if locale == "th":
        compose_thai(canvas, verb, desc)
        cv.DEVICE_TOP = 850
        cv.paste_device(canvas, shot, shadow_colour=(80, 58, 105))
        out_dir = os.path.join(OUT_ROOT, f"商店5图-{locale}")
        os.makedirs(out_dir, exist_ok=True)
        path = os.path.join(out_dir, f"{OUT_NAMES[index]}.jpg")
        canvas.convert("RGB").save(path, "JPEG", quality=92, subsampling=1)
        return path

    draw = ImageDraw.Draw(canvas)
    fill, desc_fill = (14, 21, 37, 255), (44, 54, 76, 255)

    verb_font = fit(draw, verb, locale, int(cv.CANVAS_W * 0.84), 232, 132)
    bbox = draw.textbbox((0, 0), verb, font=verb_font)
    y = 186
    draw.text(((cv.CANVAS_W - (bbox[2] - bbox[0])) / 2, y - bbox[1]), verb,
              font=verb_font, fill=fill)
    y += (bbox[3] - bbox[1]) + 30

    # Pick the largest descriptor size that fits above the device.
    for desc_size in range(94, 54, -2):
        f = make_font(locale, desc_size)
        wrap = wrap_chars if locale in NO_SPACE_LANGS else wrap_words
        lines = wrap(draw, desc, f, int(cv.CANVAS_W * 0.84))[:2]
        boxes = [draw.textbbox((0, 0), line, font=f) for line in lines]
        total = sum(b[3] - b[1] for b in boxes) + (len(lines) - 1) * 10
        if y + total <= 815:
            break
    for line, lb in zip(lines, boxes):
        draw.text(((cv.CANVAS_W - (lb[2] - lb[0])) / 2, y - lb[1]), line,
                  font=f, fill=desc_fill)
        y += (lb[3] - lb[1]) + 10

    cv.DEVICE_TOP = 850
    cv.paste_device(canvas, shot, shadow_colour=(80, 58, 105))
    out_dir = os.path.join(OUT_ROOT, f"商店5图-{locale}")
    os.makedirs(out_dir, exist_ok=True)
    path = os.path.join(out_dir, f"{OUT_NAMES[index]}.jpg")
    canvas.convert("RGB").save(path, "JPEG", quality=92, subsampling=1)
    return path


def preview(locale, files):
    tw, th = 264, 574
    sheet = Image.new("RGB", (tw * 5, th + 20), (245, 245, 245))
    for i, f in enumerate(files):
        im = Image.open(f).convert("RGB")
        im.thumbnail((tw, th))
        sheet.paste(im, (i * tw + (tw - im.width) // 2, 10))
    path = os.path.join(OUT_ROOT, f"商店5图-{locale}-预览.jpg")
    sheet.save(path, "JPEG", quality=90)
    return path


def main():
    for locale in HEADLINES:
        files = [compose(locale, i) for i in range(5)]
        print(preview(locale, files))


if __name__ == "__main__":
    main()
