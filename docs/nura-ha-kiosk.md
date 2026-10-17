# Home Assistant kiosk UI for Nura / postmarketOS

`pmaports-overlay/postmarketos-ui-ha-kiosk` is a pmaports UI package that boots
a Krane tablet straight into a fullscreen Home Assistant dashboard (Chromium in
kiosk mode).

It builds on `postmarketos-base-ui-cage`, the same base as the stock
`postmarketos-ui-cage`, so it inherits:

- the `tinydm` Cage-UI Wayland session, `seatd`/`elogind`, audio and network setup
- **auto-rotation from the panel's DRM orientation** (`cage-ui-autorotate.sh`)
- the `/etc/cage-ui/*.sh` hook directory

This package only adds the app: `/etc/cage-ui/10-ha-kiosk.sh` sets
`CAGE_UI_COMMAND=/usr/libexec/ha-kiosk-session`, which waits for Home
Assistant and starts Chromium. It deliberately does not run its own display
manager or compositor config.

## Use

```sh
scripts/install-ha-kiosk-ui.sh      # copies the package into pmaports, selects the UI
pmbootstrap install
```

Edit `/etc/ha-kiosk/ha-kiosk.conf` (or `~/.config/ha-kiosk.conf`) to set
`HA_URL` and extra Chromium flags.

## What runs where

This package only provides the screen. Alpine has no packages for
`wyoming-satellite`, `openwakeword` or `otbr-agent`, so run Home Assistant
Core (if the tablet is the hub), OTBR, Matter Server and the wake-word
services as containers (`podman`/`docker` are available).

## Status and known gaps

Written against the pmaports tree as of 2026-10-17 and Alpine edge package
names; **not built or booted**. Not handled yet:

- On-screen keyboard (cage has no layer-shell, so common OSKs may not work).
- Screen blanking and wake on touch/voice.
- Chromium rendering speed on the Mali-G72 with Panfrost is unmeasured.
- Auto-rotation depends on the Krane device tree exposing a panel orientation.
- The package keeps the `postmarketos-ui-*` name; check whether Nura has
  renamed the UI package convention.
