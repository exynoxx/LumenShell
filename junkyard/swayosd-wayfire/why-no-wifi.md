# Why Wayfire doesn't auto-connect to WiFi (but KDE Plasma does)

## Short answer

The WiFi password is stored in your **KDE keyring (KWallet)**, not in NetworkManager's
system store. KDE Plasma starts the agents needed to unlock it; Wayfire does not.

## What's happening

When you saved the network in KDE, Plasma's NetworkManager applet stored the
connection with `psk-flags=1` ("agent-owned"). That means the `.nmconnection`
file in `/etc/NetworkManager/system-connections/` contains everything *except*
the PSK — the password lives in KWallet, encrypted with your login password.

NetworkManager itself runs as a system service and tries to autoconnect at boot
regardless of DE. But when the profile is agent-owned, NM has to ask a
**Secret Service agent** (running in your user session) for the password.

- No agent → no password → no connection.

### Why KDE works

- Plasma's session starts `kwalletd`, unlocks it via PAM with your login password.
- `plasma-nm` registers as both a Secret Service agent and a polkit agent.
- NetworkManager asks, KWallet answers, you're online.

### Why Wayfire doesn't

- Wayfire is a bare compositor — it starts no keyring, no secret agent, no
  polkit agent.
- NM asks for the secret, nobody answers, the connection sits in
  "needs secrets" state.

## Confirm the diagnosis

```sh
nmcli -s connection show "<SSID>" | grep psk
```

If you see `802-11-wireless-security.psk-flags: 1 (agent-owned)`, that's the
cause.

## Fixes (easiest to most invasive)

### 1. Make the secret system-owned (simplest for a single-user machine)

```sh
sudo nmcli connection modify "<SSID>" wifi-sec.psk-flags 0
sudo nmcli connection modify "<SSID>" wifi-sec.psk "<password>"
```

`psk-flags=0` stores the PSK in the root-readable `.nmconnection` file, so NM
can autoconnect with no user session at all.

### 2. Run a secret agent + keyring in your Wayfire session

Add to your Wayfire autostart:

```sh
/usr/bin/gnome-keyring-daemon --start --components=secrets,pkcs11,ssh
/usr/libexec/polkit-gnome-authentication-agent-1 &
nm-applet &
```

Pair with `pam_gnome_keyring.so` in `/etc/pam.d/login` (or your display manager)
so the keyring unlocks automatically with your login password.

KDE equivalents: `kwalletd6`, standalone `plasma-nm`,
`polkit-kde-authentication-agent-1`.

## Recommendation

Option 1 is the right answer for a single-user laptop. Option 2 is right if
you want per-user secrets.

## Background: who controls WiFi on Linux

| Layer | Component | Job |
|-------|-----------|-----|
| Kernel | `cfg80211` / `mac80211` + driver | The radio itself |
| Auth | `wpa_supplicant` / `iwd` | WPA/WPA2/WPA3 handshake |
| Policy | `NetworkManager` | Profile storage, autoconnect, DHCP, DNS |
| UI | `plasma-nm`, `nm-applet`, `nmcli`, `nmtui` | Frontends only |

Saved connections live in `/etc/NetworkManager/system-connections/*.nmconnection`.
At boot/wake/interface-up, NetworkManager scans, intersects results with
profiles that have `autoconnect=true`, picks one (by
`connection.autoconnect-priority`, then recency/signal), hands off to
`wpa_supplicant` for auth, then runs DHCP.
