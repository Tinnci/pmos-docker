# Home Assistant kiosk UI for Nura / postmarketOS

`pmaports-overlay/postmarketos-ui-ha-kiosk` is a pmaports UI meta-package that
boots a Krane tablet straight into a fullscreen Home Assistant dashboard:

- `cage` (single-app Wayland compositor) started by `greetd`
- Chromium in kiosk mode, pointed at `HA_URL`
- `elogind` for the seat, `wlr-randr` for optional rotation

It follows the structure of `postmarketos-ui-phosh` (separate `-openrc` and
`-systemd` subpackages, greetd config selected via `cfgfile`).

## Use

```sh
scripts/install-ha-kiosk-ui.sh      # copies the package into pmaports, selects the UI
pmbootstrap install
```

Edit `/etc/ha-kiosk/ha-kiosk.conf` (or `~/.config/ha-kiosk.conf`) to set
`HA_URL`, `OUTPUT_TRANSFORM` and extra Chromium flags.

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
- Auto-rotation (`iio-sensor-proxy` is only recommended).
- Chromium rendering speed on the Mali-G72 with Panfrost is unmeasured.
- The package keeps the `postmarketos-ui-*` name; check whether Nura has
  renamed the UI package convention.
