#!/usr/bin/env python3
"""Convert the legal Markdown sources into small bilingual HTML pages."""
import html
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ASSETS = ROOT / "应用商店信息"
OUT = Path(__file__).resolve().parent / "legal_html"

CSS = '''
:root{color-scheme:light dark;--bg:#f6f7f9;--card:#fff;--ink:#171b26;--muted:#5c667a;--line:#e4e7ec;--accent:#1f6feb}
@media (prefers-color-scheme:dark){:root{--bg:#0d1117;--card:#161b22;--ink:#e6edf3;--muted:#9aa7b8;--line:#2d333b;--accent:#58a6ff}}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--ink);font:16px/1.75 -apple-system,BlinkMacSystemFont,"SF Pro Text","PingFang SC","Segoe UI",sans-serif}
main{max-width:860px;margin:0 auto;padding:40px 22px 80px}header{display:flex;justify-content:space-between;gap:16px;align-items:center;margin-bottom:26px;flex-wrap:wrap}
.brand{font-weight:800;letter-spacing:.2px}.nav a{color:var(--accent);text-decoration:none;margin-left:16px;font-size:14px}
.card{background:var(--card);border:1px solid var(--line);border-radius:18px;padding:30px 30px 20px;box-shadow:0 8px 30px rgba(15,23,42,.06)}
h1{font-size:30px;line-height:1.25;margin:0 0 8px}h2{font-size:21px;margin:30px 0 8px;padding-top:6px;border-top:1px solid var(--line)}
h3{font-size:17px;margin:20px 0 6px}p{margin:10px 0}ul,ol{margin:8px 0 12px;padding-left:24px}li{margin:5px 0}
.meta{color:var(--muted);font-size:14px;margin:0 0 18px}.lang{border-top:2px solid var(--line);margin-top:34px;padding-top:22px}
.lang-label{display:inline-block;font-size:12px;font-weight:700;letter-spacing:.08em;text-transform:uppercase;color:var(--accent);margin-bottom:4px}
.footer{margin-top:26px;color:var(--muted);font-size:13px}.footer a{color:var(--accent);text-decoration:none}
a{color:var(--accent)}.note{background:rgba(31,111,235,.08);border-left:3px solid var(--accent);padding:10px 14px;border-radius:8px}
@media (max-width:600px){main{padding:24px 14px 60px}.card{padding:22px 18px}}
'''


def inline(text: str) -> str:
    escaped = html.escape(text, quote=False)
    escaped = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", escaped)
    escaped = re.sub(r"`(.+?)`", r"<code>\1</code>", escaped)
    return escaped


def markdown_to_html(md: str) -> str:
    out, paragraph, bullets, numbered = [], [], [], []

    def flush():
        nonlocal paragraph, bullets, numbered
        if paragraph:
            out.append("<p>" + inline(" ".join(paragraph)) + "</p>")
            paragraph = []
        if bullets:
            out.append("<ul>" + "".join(f"<li>{inline(x)}</li>" for x in bullets) + "</ul>")
            bullets = []
        if numbered:
            out.append("<ol>" + "".join(f"<li>{inline(x)}</li>" for x in numbered) + "</ol>")
            numbered = []

    for raw in md.splitlines():
        line = raw.rstrip()
        if not line.strip():
            flush()
            continue
        if line.startswith("# "):
            flush(); out.append(f"<h1>{inline(line[2:])}</h1>")
        elif line.startswith("## "):
            flush(); out.append(f"<h2>{inline(line[3:])}</h2>")
        elif line.startswith("### "):
            flush(); out.append(f"<h3>{inline(line[4:])}</h3>")
        elif re.match(r"^[-*] ", line):
            if paragraph or numbered: flush()
            bullets.append(line[2:])
        elif re.match(r"^\d+[.)] ", line):
            if paragraph or bullets: flush()
            numbered.append(re.sub(r"^\d+[.)]\s*", "", line))
        else:
            if bullets or numbered: flush()
            paragraph.append(line.strip())
    flush()
    return "\n".join(out)


def page(title: str, zh_md: str, en_md: str, active: str) -> str:
    nav = {
        "privacy": ("隐私政策", "Privacy", "privacy.html"),
        "terms": ("用户协议", "Terms", "terms.html"),
        "support": ("支持", "Support", "support.html"),
    }
    links = "".join(
        f'<a href="{href}">{label if active == key else label + " / " + en}</a>'
        for key, (label, en, href) in nav.items()
    )
    return f'''<!doctype html>
<html lang="zh-Hans">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<title>{html.escape(title)} · WProxy / 无极代理</title>
<style>{CSS}</style>
</head>
<body><main>
<header><div class="brand">WProxy · 无极代理</div><nav class="nav">{links}</nav></header>
<section class="card">
<div class="lang-label">简体中文</div>
{markdown_to_html(zh_md)}
<div class="lang"><div class="lang-label">English</div>
{markdown_to_html(en_md)}
</div>
<div class="footer">© 2026 绍兴天穹网络科技有限公司 · <a href="support.html">支持 / Support</a></div>
</section>
</main></body></html>'''


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    privacy_zh = (ASSETS / "隐私政策.md").read_text()
    privacy_en = (ASSETS / "隐私政策-en.md").read_text()
    terms_zh = (ASSETS / "用户协议.md").read_text()
    terms_en = (ASSETS / "用户协议-en.md").read_text()
    support_zh = """# 支持 / Support

## 联系

如需帮助，请发送邮件至 **ji4ozhu@gmail.com**，并尽量附上：

- App 版本（设置 → 关于）
- iOS / iPadOS 版本
- 节点协议和大致错误现象（不要发送完整密码/UUID）

## 常见问题

### 为什么第一次连接会弹出两个系统权限？
需要允许「本地网络」和「VPN 配置」，否则系统无法建立隧道。若误点拒绝，请到 设置 → 隐私与安全性 → 本地网络 / 通用 → VPN 与设备管理 重新开启。

### 为什么添加节点后无法连接？
请确认节点参数、服务器可达性和协议配置；本 App 不提供服务器。可以先用节点页的测速/延迟测试确认服务器是否可达。

### 如何删除所有本地数据？
设置 → 清空数据。该操作会删除节点、订阅、设置和隧道配置，无法恢复。

### 是否收集我的数据？
不收集。详见[隐私政策](privacy.html)。
"""
    support_en = """# Support

## Contact

Email **ji4ozhu@gmail.com** and include:

- App version (Settings → About)
- iOS / iPadOS version
- Protocol and a short description of the issue (do not send full passwords/UUIDs)

## FAQ

### Why does the first launch ask for two permissions?
Allow Local Network and VPN Configuration so iOS can create the tunnel. If you denied them, re-enable them in Settings → Privacy & Security → Local Network and Settings → General → VPN & Device Management.

### Why can't I connect after adding a node?
Check the node parameters, server reachability, and protocol settings. This app does not provide servers. Use the latency test on the Nodes screen to check reachability.

### How do I delete all local data?
Settings → Clear Data. This removes nodes, subscriptions, settings, and tunnel configuration; it cannot be undone.

### Do you collect my data?
No. See the [Privacy Policy](privacy.html).
"""
    (OUT / "privacy.html").write_text(page("隐私政策 / Privacy Policy", privacy_zh, privacy_en, "privacy"))
    (OUT / "terms.html").write_text(page("用户协议 / Terms of Use", terms_zh, terms_en, "terms"))
    (OUT / "support.html").write_text(page("支持 / Support", support_zh, support_en, "support"))
    print("written", OUT)


if __name__ == "__main__":
    main()
