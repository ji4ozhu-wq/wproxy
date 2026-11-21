# Privacy Policy — WProxy

**Effective date:** November 20, 2026
**Operator:** WProxy (developer of the WProxy iOS app)
**Contact:** ji4ozhu@gmail.com

## 1. Summary

WProxy is a client app. Everything you add — servers, subscriptions, settings, latency results — is stored only on your device. We do not operate a backend, and we do not collect, receive, sell, or share your data.

## 2. Data Stored on Your Device

- Server profiles (protocol, address, port, credentials you enter).
- Subscription URLs, names, and cached node lists.
- Routing preferences, test results, and app settings.

These records live in the app's local database and are removed when you delete them in Settings or uninstall the app.

## 3. Network Requests

- When you add or update a subscription, the app requests the subscription URL you provided. That request goes directly from your device to that server.
- When you connect, network traffic is sent to the server you configured, through the iOS VPN tunnel created by the app's Network Extension.
- When you test latency, the app opens a TCP connection to your selected server and to the configured test URL (default: a standard connectivity check endpoint).

WProxy does not send usage data, analytics, diagnostics, or crash reports to us or to any third party.

## 3a. DNS and Country-Routing Data

- **DNS resolution:** While the VPN tunnel is active, the device's DNS queries are
  answered through your proxy connection by a public DNS-over-HTTPS resolver
  (Cloudflare 1.1.1.1). The resolver sees the queries; we do not receive or log them.
- **Country routing data:** To keep selected regions direct, the app uses a
  country-to-IP-range dataset derived from the GeoIP data published by the v2fly
  project (based on DB-IP Lite, CC BY 4.0; distributed as CC BY-SA 4.0). The dataset
  ships with the app and refreshes over HTTPS from the public v2fly/geoip release
  while the VPN is connected. The update is public data and contains no account,
  device, or usage information about you.

## 4. What We Do Not Collect

We do not collect account identifiers, personal profiles, browsing history, connection logs, destination addresses, or device identifiers. WProxy contains no advertising SDK, analytics SDK, or third-party tracking SDK.

## 5. Permissions

- **Network Extension (VPN):** required to create the system VPN tunnel that routes traffic to your server.
- **Camera:** used only when you choose to scan a server QR code.
- **Photo Library:** used only when you choose a photo to recognize a QR code, or save a QR code image you asked to save.

## 6. Sharing

We do not sell, rent, or share personal data. Because your traffic never passes through our systems, we have no ability to see what you connect to.

## 7. Retention and Deletion

Data stays on your device until you delete it. You can clear all app data in Settings, and uninstalling the app removes all local data.

## 8. Children

WProxy is not directed to children under 13, and we do not knowingly collect data from children.

## 9. Changes

We may update this policy. The effective date above reflects the current version; material changes will be noted in release notes.

## 10. Contact

Questions about privacy: ji4ozhu@gmail.com
