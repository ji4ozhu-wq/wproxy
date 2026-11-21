#!/usr/bin/env python3
"""Create the 3.3.0 localization records, attach the build and upload screenshots."""
import hashlib
import json
import os
import sys
import time
import urllib.parse
import urllib.request

sys.path.insert(0, os.path.dirname(__file__))
import asc_api as api

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
ASSETS = os.path.join(ROOT, "应用商店信息")
APP = "1448657437"
APP_INFO = "8a9a2dc5-c35b-4aea-ad6d-f04a56713dc2"
APP_INFO_LOC_ZH = "ce4ba247-fbaa-42f2-9cf2-fd9900d1c4dc"
VERSION = "a071dd6a-9752-42ab-850a-92a8b87142a3"
VERSION_LOC_ZH = "1c5af231-37ec-4920-956b-76ec3c02d020"
BUILD = "2012e011-a16d-476c-ac30-a4799d05e713"
SUPPORT_URL = "http://www.54nb.com"

DESCRIPTIONS = {
    "en-US": "Rebuilt the UI to support iPhone 16+, iPad, and iPhone Duo.\nWProxy is a proxy client for your own server. We don't provide nodes and don't collect data. It supports VMess, VLESS, Trojan, Shadowsocks, and SOCKS5, with manual, QR, or subscription import and automatic latency tests. Route globally or by rules, bypass selected countries/regions and LAN, and use remote DoH. 11 languages, no in-app purchases, no ads.",
    "zh-Hans": "为支持 iPhone 16+、iPad、iPhone Duo 特性，重构了 UI.\n无极代理是连接自有服务器的代理客户端，不提供节点、不收集数据。支持 VMess、VLESS、Trojan、Shadowsocks、SOCKS5，可手动添加、扫码或订阅导入并自动测速；支持全局/规则分流、跳过指定国家与局域网、远程 DoH。支持 11 种语言,无内购,无广告.",
    "zh-Hant": "為支援 iPhone 16+、iPad、iPhone Duo 特性，重構了 UI。\n無極代理是連接自有伺服器的代理客戶端，不提供節點、不收集資料。支援 VMess、VLESS、Trojan、Shadowsocks、SOCKS5，可手動新增、掃碼或訂閱匯入並自動測速；支援全域/規則分流、跳過指定國家/區域與區域網路、遠端 DoH。支援 11 種語言，無內購，無廣告。",
    "es-ES": "Interfaz renovada para aprovechar iPhone 16+, iPad e iPhone Duo.\nWProxy es un cliente proxy para tu propio servidor. No proporcionamos nodos ni recopilamos datos. Compatible con VMess, VLESS, Trojan, Shadowsocks y SOCKS5; importa manualmente, por QR o suscripción y mide la latencia automáticamente. Enrutamiento global o por reglas, omite países/regiones seleccionados y la LAN, y usa DoH remoto. 11 idiomas, sin compras integradas ni anuncios.",
    "fr-FR": "Interface repensée pour iPhone 16+, iPad et iPhone Duo.\nWProxy est un client proxy pour votre propre serveur. Nous ne fournissons pas de nœuds et ne collectons aucune donnée. Compatible VMess, VLESS, Trojan, Shadowsocks et SOCKS5 ; import manuel, QR ou abonnement avec test de latence automatique. Routage global ou par règles, exclusion des pays/régions choisis et du LAN, DoH distant. 11 langues, sans achats intégrés ni publicité.",
    "de-DE": "UI für iPhone 16+, iPad und iPhone Duo neu aufgebaut.\nWProxy ist ein Proxy-Client für deinen eigenen Server. Wir stellen keine Nodes bereit und sammeln keine Daten. Unterstützt VMess, VLESS, Trojan, Shadowsocks und SOCKS5; Import manuell, per QR oder Abo mit automatischem Latenztest. Globales oder regelbasiertes Routing, ausgewählte Länder/Regionen und LAN ausgenommen, Remote-DoH. 11 Sprachen, keine In-App-Käufe, keine Werbung.",
    "ja": "iPhone 16+、iPad、iPhone Duo の特性をサポートするため、UI を刷新しました。\nWProxy は自分のサーバーに接続するためのプロキシクライアントです。ノードの提供やデータ収集は行いません。VMess、VLESS、Trojan、Shadowsocks、SOCKS5 に対応し、手動・QR コード・サブスクリプションでインポート、レイテンシーを自動測定。グローバル/ルール分流、指定した国・地域と LAN の除外、リモート DoH に対応。11 言語、アプリ内課金・広告なし。",
    "ko": "iPhone 16+, iPad, iPhone Duo 특성을 지원하기 위해 UI를 재구성했습니다.\nWProxy는 내 서버에 연결하는 프록시 클라이언트입니다. 노드를 제공하거나 데이터를 수집하지 않습니다. VMess, VLESS, Trojan, Shadowsocks, SOCKS5를 지원하며 수동, QR 코드, 구독으로 가져오기 및 지연 자동 측정이 가능합니다. 전역/규칙 분할, 선택한 국가/지역 및 LAN 제외, 원격 DoH를 지원합니다. 11개 언어, 인앱 구매 및 광고 없음.",
    "ru": "Интерфейс переработан для iPhone 16+, iPad и iPhone Duo.\nWProxy — прокси-клиент для вашего собственного сервера. Мы не предоставляем узлы и не собираем данные. Поддерживаются VMess, VLESS, Trojan, Shadowsocks и SOCKS5; импорт вручную, по QR-коду или подписке с автоматическим тестом задержки. Глобальная или правиловая маршрутизация, обход выбранных стран/регионов и LAN, удалённый DoH. 11 языков, без встроенных покупок и рекламы.",
    "th": "ออกแบบ UI ใหม่เพื่อรองรับคุณสมบัติ iPhone 16+, iPad และ iPhone Duo\nWProxy เป็นไคลเอนต์พร็อกซีสำหรับเชื่อมต่อเซิร์ฟเวอร์ของคุณเอง เราไม่มีโหนดให้และไม่เก็บข้อมูล รองรับ VMess, VLESS, Trojan, Shadowsocks และ SOCKS5 นำเข้าด้วยตนเอง QR หรือการสมัคร พร้อมทดสอบความหน่วงอัตโนมัติ แยกเส้นทางแบบทั่วโลกหรือตามกฎ ข้ามประเทศ/ภูมิภาคที่เลือกและ LAN ใช้ DoH ระยะไกล รองรับ 11 ภาษา ไม่มีซื้อในแอปและโฆษณา",
    "vi": "Giao diện được thiết kế lại để hỗ trợ iPhone 16+, iPad và iPhone Duo.\nWProxy là ứng dụng proxy kết nối máy chủ riêng của bạn. Chúng tôi không cung cấp node và không thu thập dữ liệu. Hỗ trợ VMess, VLESS, Trojan, Shadowsocks, SOCKS5; nhập thủ công, mã QR hoặc đăng ký và tự động đo độ trễ. Định tuyến toàn cầu hoặc theo quy tắc, bỏ qua quốc gia/khu vực đã chọn và LAN, dùng DoH từ xa. 11 ngôn ngữ, không mua trong ứng dụng, không quảng cáo.",
}

META = {
    "en-US": dict(name="WProxy", subtitle="Your server, one tap away",
                  keywords="proxy,vpn,nodes,subscription,qr,split routing,network tool,socks5,vmess,vless,trojan,shadowsocks",
                  promo="Your own server, one tap away. QR / link / subscription import, automatic latency tests, country and LAN bypass.",
                  whats_new="A full native rewrite: new UI, QR/link/manual import, subscription auto-update, automatic latency tests, country/region routing, and 11 languages.",
                  screenshots="商店5图-en"),
    "zh-Hans": dict(name="无极代理", subtitle="安全连接你的私有服务器",
                    keywords="代理,VPN,节点,订阅,扫码,分流,网络工具,SOCKS5,VMess,VLESS,Trojan,Shadowsocks",
                    promo="无需账号，不收集数据。用二维码、链接或订阅导入自己的节点，一键连接，按需分流。",
                    whats_new="全新原生版本：重写界面与交互，支持扫码/链接/手动导入、订阅自动更新、节点自动测速、国家/地区分流与 11 种语言。",
                    screenshots="商店5图-zh-Hans"),
    "zh-Hant": dict(name="無極代理", subtitle="安全連線你的私有伺服器",
                    keywords="代理,VPN,節點,訂閱,掃碼,分流,網路工具,SOCKS5,VMess,VLESS,Trojan,Shadowsocks",
                    promo="無需帳號，不收集資料。用 QR Code、連結或訂閱匯入自己的節點，一鍵連線，依需分流。",
                    whats_new="全新原生版本：重寫介面與互動，支援掃碼/連結/手動匯入、訂閱自動更新、節點自動測速、國家/區域分流與 11 種語言。",
                    screenshots="商店5图-zh-Hant"),
    "es-ES": dict(name="WProxy", subtitle="Tu servidor, a un toque",
                  keywords="proxy,vpn,nodos,suscripción,qr,enrutamiento,herramienta de red,socks5,vmess,vless,trojan,shadowsocks",
                  promo="Tu servidor, a un toque. Importa por QR, enlace o suscripción y enruta solo lo que necesitas.",
                  whats_new="Reescritura nativa: nueva interfaz, importación por QR/enlace/manual, actualización de suscripciones, test de latencia automático, enrutamiento por países/regiones y 11 idiomas.",
                  screenshots="商店5图-es"),
    "fr-FR": dict(name="WProxy", subtitle="Votre serveur en un geste",
                  keywords="proxy,vpn,nœuds,abonnement,qr,routage,outil réseau,socks5,vmess,vless,trojan,shadowsocks",
                  promo="Votre serveur en un geste. Import par QR, lien ou abonnement, routage à la demande.",
                  whats_new="Réécriture native : nouvelle interface, import QR/lien/manuel, mise à jour des abonnements, test de latence automatique, routage par pays/régions et 11 langues.",
                  screenshots="商店5图-fr"),
    "de-DE": dict(name="WProxy", subtitle="Dein Server, ein Tipp",
                  keywords="proxy,vpn,server,abo,qr,routing,netzwerkzeug,socks5,vmess,vless,trojan,shadowsocks",
                  promo="Dein Server, ein Tipp. Import per QR, Link oder Abo, Routing nach Bedarf.",
                  whats_new="Nativer Neuaufbau: neue UI, Import per QR/Link/manuell, automatische Abo-Updates, automatischer Latenztest, Routing nach Ländern/Regionen und 11 Sprachen.",
                  screenshots="商店5图-de"),
    "ja": dict(name="WProxy", subtitle="自分のサーバーにワンタップ",
               keywords="プロキシ,VPN,ノード,サブスクリプション,QR,分流,ネットワークツール,SOCKS5,VMess,VLESS,Trojan,Shadowsocks",
               promo="自分のサーバーへワンタップ。QR・リンク・購読で追加、必要な通信だけ分流。",
               whats_new="ネイティブで全面刷新：新しい UI、QR/リンク/手動インポート、購読の自動更新、レイテンシーの自動測定、国/地域分流、11 言語対応。",
               screenshots="商店5图-ja"),
    "ko": dict(name="WProxy", subtitle="내 서버에 원탭 연결",
               keywords="프록시,VPN,노드,구독,QR,분할,네트워크 도구,SOCKS5,VMess,VLESS,Trojan,Shadowsocks",
               promo="내 서버에 원탭으로. QR·링크·구독으로 추가하고 필요한 트래픽만 분할.",
               whats_new="네이티브 전면 재작성: 새로운 UI, QR/링크/수동 가져오기, 구독 자동 업데이트, 지연 자동 측정, 국가/지역 분할, 11개 언어 지원.",
               screenshots="商店5图-ko"),
    "ru": dict(name="WProxy", subtitle="Ваш сервер в одно касание",
               keywords="прокси,vpn,серверы,подписка,qr,маршрутизация,сеть,socks5,vmess,vless,trojan,shadowsocks",
               promo="Ваш сервер в одно касание. Импорт по QR, ссылке или подписке, нужная маршрутизация.",
               whats_new="Полная нативная переработка: новый интерфейс, импорт по QR/ссылке/вручную, автообновление подписок, автотест задержки, маршрутизация по странам/регионам и 11 языков.",
               screenshots="商店5图-ru"),
    "th": dict(name="WProxy", subtitle="เซิร์ฟเวอร์ในแตะเดียว",
               keywords="พร็อกซี,vpn,เซิร์ฟเวอร์,การสมัคร,qr,แยกเส้นทาง,เครื่องมือเครือข่าย,socks5,vmess,vless,trojan,shadowsocks",
               promo="เซิร์ฟเวอร์ของคุณในแตะเดียว นำเข้าด้วย QR ลิงก์ หรือการสมัคร แยกเฉพาะทราฟฟิกที่ต้องการ",
               whats_new="เขียนใหม่แบบเนทีฟ: UI ใหม่ นำเข้าด้วย QR/ลิงก์/ตนเอง อัปเดตการสมัครอัตโนมัติ ทดสอบความหน่วงอัตโนมัติ แยกตามประเทศ/ภูมิภาค และ 11 ภาษา",
               screenshots="商店5图-th"),
    "vi": dict(name="WProxy", subtitle="Máy chủ riêng một chạm",
               keywords="proxy,vpn,máy chủ,đăng ký,qr,định tuyến,công cụ mạng,socks5,vmess,vless,trojan,shadowsocks",
               promo="Máy chủ riêng trong một chạm. Nhập bằng QR, liên kết hoặc đăng ký, định tuyến theo nhu cầu.",
               whats_new="Viết lại hoàn toàn native: giao diện mới, nhập QR/liên kết/thủ công, tự động cập nhật đăng ký, tự động đo độ trễ, định tuyến theo quốc gia/khu vực và 11 ngôn ngữ.",
               screenshots="商店5图-vi"),
}


def create_app_info_localizations():
    print("\n== app info localizations ==")
    done = []
    for locale, meta in META.items():
        if locale == "zh-Hans":
            st, d = api.request("PATCH", f"/appInfoLocalizations/{APP_INFO_LOC_ZH}", {
                "data": {"type": "appInfoLocalizations", "id": APP_INFO_LOC_ZH,
                         "attributes": {"name": meta["name"], "subtitle": meta["subtitle"],
                                        "privacyPolicyUrl": SUPPORT_URL}}
            })
        else:
            st, d = api.request("POST", "/appInfoLocalizations", {
                "data": {"type": "appInfoLocalizations",
                         "attributes": {"locale": locale, "name": meta["name"],
                                        "subtitle": meta["subtitle"], "privacyPolicyUrl": SUPPORT_URL},
                         "relationships": {"appInfo": {"data": {"type": "appInfos", "id": APP_INFO}}}}
            })
        print(locale, st, "" if st < 400 else json.dumps(d, ensure_ascii=False)[:500])
        if st == 201 or st == 200:
            done.append(locale)
    return done


def create_version_localizations():
    print("\n== version localizations ==")
    mapping = {}
    for locale, meta in META.items():
        attrs = {
            "description": DESCRIPTIONS[locale],
            "keywords": meta["keywords"],
            "promotionalText": meta["promo"],
            "supportUrl": SUPPORT_URL,
            "whatsNew": meta["whats_new"],
        }
        if locale == "zh-Hans":
            st, d = api.request("PATCH", f"/appStoreVersionLocalizations/{VERSION_LOC_ZH}", {
                "data": {"type": "appStoreVersionLocalizations", "id": VERSION_LOC_ZH, "attributes": attrs}
            })
        else:
            attrs["locale"] = locale
            st, d = api.request("POST", "/appStoreVersionLocalizations", {
                "data": {"type": "appStoreVersionLocalizations", "attributes": attrs,
                         "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": VERSION}}}}
            })
        print(locale, st, "" if st < 400 else json.dumps(d, ensure_ascii=False)[:500])
        if st in (200, 201):
            mapping[locale] = d["data"]["id"]
    return mapping


def upload_file(url, data, headers):
    req = urllib.request.Request(url, data=data, method="PUT")
    if isinstance(headers, dict):
        headers = [{"name": k, "value": v} for k, v in headers.items()]
    for header in headers or []:
        req.add_header(header["name"], header["value"])
    with urllib.request.urlopen(req) as response:
        return response.status


def screenshot_set_id(localization_id, display_type="APP_IPHONE_67"):
    st, d = api.request("GET", f"/appStoreVersionLocalizations/{localization_id}/appScreenshotSets?limit=50")
    if st == 200:
        for item in d.get("data", []):
            if item["attributes"].get("screenshotDisplayType") == display_type:
                return item["id"]
    st, d = api.request("POST", "/appScreenshotSets", {
        "data": {"type": "appScreenshotSets",
                 "attributes": {"screenshotDisplayType": display_type},
                 "relationships": {"appStoreVersionLocalization": {
                     "data": {"type": "appStoreVersionLocalizations", "id": localization_id}}}}
    })
    print("  create screenshot set", st, "" if st < 400 else json.dumps(d, ensure_ascii=False)[:400])
    if st not in (200, 201):
        raise RuntimeError(f"screenshot set failed: {d}")
    return d["data"]["id"]


def upload_screenshots(locale, localization_id, folder):
    set_id = screenshot_set_id(localization_id)
    order = ["01-home.jpg", "02-nodes.jpg", "03-routing.jpg", "04-import.jpg", "05-subscriptions.jpg"]
    for name in order:
        path = os.path.join(ASSETS, folder, name)
        payload = open(path, "rb").read()
        checksum = hashlib.md5(payload).hexdigest()
        st, d = api.request("POST", "/appScreenshots", {
            "data": {"type": "appScreenshots",
                     "attributes": {"fileSize": len(payload), "fileName": name},
                     "relationships": {"appScreenshotSet": {"data": {"type": "appScreenshotSets", "id": set_id}}}}
        })
        if st not in (200, 201):
            print("  screenshot create failed", name, st, json.dumps(d, ensure_ascii=False)[:500])
            continue
        shot = d["data"]
        for op in shot["attributes"].get("uploadOperations", []):
            length = op.get("length", len(payload))
            offset = op.get("offset", 0)
            status = upload_file(op["url"], payload[offset:offset + length], op.get("requestHeaders", {}))
            if status >= 400:
                print("  chunk failed", name, status)
        st2, d2 = api.request("PATCH", f"/appScreenshots/{shot['id']}", {
            "data": {"type": "appScreenshots", "id": shot["id"],
                     "attributes": {"uploaded": True, "sourceFileChecksum": checksum}}
        })
        print("  upload", name, st2, "" if st2 < 400 else json.dumps(d2, ensure_ascii=False)[:400])
        time.sleep(0.4)


def attach_build():
    st, d = api.request("PATCH", f"/appStoreVersions/{VERSION}/relationships/build", {
        "data": {"type": "builds", "id": BUILD}
    })
    print("\nattach build", st, "" if st < 400 else json.dumps(d, ensure_ascii=False)[:800])


def main():
    only = sys.argv[1] if len(sys.argv) > 1 else "all"
    if only in ("all", "meta"):
        create_app_info_localizations()
        locs = create_version_localizations()
    else:
        locs = {}
    if only in ("all", "screens"):
        if not locs:
            st, d = api.request("GET", f"/appStoreVersions/{VERSION}/appStoreVersionLocalizations?limit=50")
            locs = {x["attributes"]["locale"]: x["id"] for x in d.get("data", [])}
        for locale, lid in locs.items():
            meta = META.get(locale)
            if not meta:
                continue
            print("\n== screenshots", locale, "==")
            upload_screenshots(locale, lid, meta["screenshots"])
    if only in ("all", "build"):
        attach_build()


if __name__ == "__main__":
    main()
