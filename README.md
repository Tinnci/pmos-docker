# pmos-docker

Google Kukui (MT8183) build tooling for Home Assistant OS. The legacy
postmarketOS kernel workflow is still present, but HAOS is the primary path.

## What This Builds

The HAOS path patches `home-assistant/operating-system` with a `google_kukui`
target:

- Buildroot br2-external integration.
- ChromeOS Depthcharge boot artifacts and kernel partition GUIDs.
- RAUC custom A/B slot backend.
- MT8183/Kukui in-tree DTBs.
- OTBR/Matter kernel config deltas.

Defaults:

- Upstream: `https://github.com/home-assistant/operating-system.git`
- Ref: `17.3`
- Target: `google_kukui`
- Builder image: `ghcr.io/tinnci/haos-builder:kukui-17.3`

## Local HAOS Build

```sh
export HAOS_DIR="$PWD/work/haos"
export HAOS_REPO=https://github.com/home-assistant/operating-system.git
export HAOS_REF=17.3
export HAOS_TARGET=google_kukui
export HAOS_BUILDER_IMAGE=ghcr.io/tinnci/haos-builder:kukui-17.3

scripts/haos-buildctl.sh source-probe
scripts/haos-buildctl.sh layer-source
scripts/haos-buildctl.sh layer-builder
scripts/haos-buildctl.sh layer-download
scripts/haos-buildctl.sh layer-compile
scripts/haos-buildctl.sh layer-artifact
```

Useful recovery commands:

```sh
scripts/haos-buildctl.sh diagnostics
scripts/haos-buildctl.sh resume-build
```

Local defaults:

- Output volume: `haos-google_kukui-17-3-output`
- ccache volume: `haos-google_kukui-17-3-ccache`
- Download cache: `$HOME/hassos-cache/dl`

## GitHub Actions

- `HAOS validate and upstream probe`: push/PR/scheduled validation for scripts,
  workflow wiring, upstream drift, builder smoke checks, and target config.
- `Build HAOS builder image`: publishes the GHCR builder image and attests the
  image digest.
- `Build HAOS image (OTBR)`: manual full HAOS image build. It exports,
  verifies, uploads, and attests the final artifact set.
- `Build pmos kernel (google-kukui)`: legacy postmarketOS kernel APK build. It
  uploads APKs with `SHA256SUMS` and provenance attestation.

Full HAOS builds produce `work/haos-artifacts`, including:

- `kernel.img`
- `haos_google-kukui-*.img.xz`
- `haos_google-kukui-*.raucb`
- `mt8183-kukui*.dtb`
- `verification/SHA256SUMS`
- `verification/build-metadata.env`

Attestations are created for the HAOS release artifacts, build metadata, GHCR
builder image digest, and kernel APKs. Verify an artifact with:

```sh
gh attestation verify <artifact> --repo Tinnci/pmos-docker
```

Operational details: [`docs/haos-build-ux.md`](docs/haos-build-ux.md).

## Legacy postmarketOS Kernel

The older workflow builds `linux-postmarketos-mediatek-mt81` for google-kukui
with OTBR/OpenThread multicast routing options.

```sh
docker compose up -d
docker exec -it pmos-builder sh
```

Inside the container:

```sh
sh /scripts/bootstrap-pmbootstrap.sh
sh /scripts/init-pmbootstrap.sh
sh /scripts/patch-kernel-otbr.sh
su -s /bin/sh pmbuild -c \
  "export HOME=/work/pmbootstrap; pmbootstrap build linux-postmarketos-mediatek-mt81"
```

## Minimal Krane Kernel (mainline)

`kernel/krane.config` is one config fragment for Krane (MT8183): hardware
drivers, Thread/OTBR/Matter networking, Bluetooth LE and BlueZ mesh crypto,
and the HAOS/Docker host options. It is applied to `allnoconfig`, so only what
Krane needs is built.

```sh
scripts/build-krane-kernel.sh   # Image + krane sku0/sku176 DTBs, ~4 min on 20 cores
```

The script warns about fragment options the kernel dropped for unmet
dependencies; with kernel 6.18.13 none are dropped. This has not been
boot-tested on hardware. Local kernel patches in `kernel/patches/` are applied automatically (currently
an MT8183 AFE spurious-interrupt fix, carried over from the
`mt8183-afe-spurious-irq-rfc` branch; it is an RFC without a `Signed-off-by`).
HAOS still builds its own kernel via Buildroot; feed
this fragment to that build rather than replacing it.
