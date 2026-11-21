# WProxy Privacy Policy

Effective date: November 20, 2026
Operator: the WProxy / 无极代理 developer
Contact: ji4ozhu@gmail.com

## 1. Summary
WProxy is a client for connecting to **your own proxy server**. We do not operate proxy servers, provide nodes, require an account, or collect, sell, or share your personal data. Your nodes, subscriptions, and settings are stored on your device by default.

## 2. Data stored on your device
The app stores the following locally (SQLite database and App Group container):
- Node profiles: name, protocol, server address, port, UUID/password/SOCKS5 credentials, transport and TLS settings.
- Subscriptions: URL, name, last update status, traffic and expiry metadata.
- Settings: routing mode, DNS mode, language, bypassed countries/regions, LAN option, latency test URL, active node.
- Runtime state: current tunnel configuration, connection state, session traffic counters.
- GeoIP/geosite data files.

We do not upload this data to our servers. You can remove it with “Settings → Clear Data”; uninstalling the app normally removes local data, but iOS may retain the App Group container, so clear data in the app first.

## 3. Network requests and third parties
The app does not send usage data, analytics, crash reports, or advertising identifiers to us. Actual network requests include:

- **Proxy connections**: when connected, traffic goes through the iOS VPN tunnel to the server you configured. That server is operated by you or a third party, not by us; we cannot see your traffic.
- **Subscription updates**: the app requests the subscription URL you entered directly; the subscription provider sees your request and IP. A subscription URL may contain an access token—keep it private.
- **Latency tests**: the app opens a TCP connection to a node and, while connected, requests your configured test URL (default `https://www.gstatic.com/generate_204`). Results stay on the device.
- **DNS**:
  - Remote DoH mode: Chinese domains are resolved directly via `223.5.5.5` / `119.29.29.29`; other domains use `1.1.1.1` / `8.8.8.8` DoH through the proxy.
  - Local DNS mode: queries go directly to `8.8.8.8` / `1.1.1.1`.
  - Those public resolvers see the queries; the proxy server may also see the DoH destination. We do not receive or log them.
- **GeoIP updates**: the app downloads public GeoIP/geosite data from v2fly/geoip mirrors (e.g. jsDelivr, GitHub); no account or device data is included.
- **Apple services**: purchases, TestFlight, and system diagnostics are handled by Apple under its policies; we cannot access your Apple ID payment details.

Third parties may be located outside your country/region. Evaluate the risks of the proxy, subscription, and public DNS services you choose.

## 4. Permissions
- **VPN / Network Extension**: creates the system VPN tunnel and forwards traffic to your server.
- **Local Network**: completes iOS local-network/VPN authorization and supports the “bypass LAN” option; we do not scan, collect, or upload LAN content.
- **Camera**: only when you choose to scan a QR code.
- **Photos**: only when you choose a QR image or save a QR code.
- We do not request notifications, location, contacts, or microphone access.

## 5. Data we do not collect
We do not collect accounts, names, phone numbers, email addresses (except when you contact support), device identifiers, precise location, contacts, browsing history, connection logs, or advertising identifiers. The app contains no advertising, analytics, or third-party tracking SDKs.

## 6. Security
Node credentials and configuration are stored locally in iOS data-protected containers. The running tunnel configuration uses file protection and is deleted after disconnect. The local database is not additionally encrypted; use a device passcode and protect your device. The security, trustworthiness, and privacy of any proxy protocol depend on the server you choose; we make no guarantees.

## 7. Retention and deletion
Local data remains until you delete it. You can clear data in the app or uninstall it. Subscription providers, DNS resolvers, and proxy servers retain data under their own policies; we cannot delete it for you.

## 8. Children
The app is not directed to children under 13 and we do not knowingly collect children’s data.

## 9. Changes
We may update this policy. Material changes will be noted in release notes or in-app; continued use means you accept the updated policy.

## 10. Contact
Privacy questions: ji4ozhu@gmail.com
