# libXray fork patches

`wuji-traffic-stats.patch` adds one invoke method to libXray (`apiVersion` 3):

```
method: "getTrafficStats"
payload: { "inboundTag": "tun-in" }        # optional, defaults to "tun-in"
data:    { "uplink": <int64 bytes>, "downlink": <int64 bytes> }
error:   "xray is not running" / "stats manager is not available"
```

It reads the Xray `stats` counters `inbound>>>tun-in>>>traffic>>>uplink|downlink`
that Xray creates when the tunnel config enables
`policy.system.statsInboundUplink/Downlink` (the Wuji config always does). The
counters are read from the managed `core.Instance` under the same lock as
`runXray`/`stopXray`, so it is safe to poll once per second from the extension.

`tools/build_libxray.sh` pins upstream libXray to commit
`5a0f7d8d1c28b34afb5727b04b26a10f6dbac7e3`, resets the checkout, applies every
`*.patch` in this directory and rebuilds `Frameworks/LibXray.xcframework`
(iOS device arm64 + iOS simulator arm64).

## Validation

```bash
tools/libxray-patch/validation/run_validation.sh
```

Compiles a macOS driver against the rebuilt macOS libXray slice plus a config
generator built from the real app sources, then checks that:

- the `getTrafficStats` method is registered (fork applied),
- every generated node config (VMess/VLESS/Trojan/SS, tcp/ws/grpc/xhttp, TLS and
  REALITY, rule/global routing, ~16k-CIDR bypass) is accepted by `testXray`,
- `getTrafficStats` reports real byte counters for traffic through a SOCKS
  inbound, and rejects polling after `stopXray`.
