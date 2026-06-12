# pmos-docker

Google Kukui (MT8183) build tooling for HAOS and the older postmarketOS OTBR
kernel experiment.

The current primary path is HAOS. The postmarketOS workflow remains available as
a legacy kernel build path.

## HAOS Kukui

This repository patches `home-assistant/operating-system` with a `google_kukui`
target using:

- Buildroot/br2-external integration
- ChromeOS Depthcharge boot images
- ChromeOS kernel partition GUIDs
- RAUC custom A/B slot backend
- MT8183/Kukui in-tree DTBs
- OTBR/Matter kernel config deltas

Default baseline:

- HAOS upstream ref: `17.3`
- Target: `google_kukui`
- Builder image: `ghcr.io/tinnci/haos-builder:kukui-17.3`

Local build:

```sh
export HAOS_DIR="$PWD/work/haos"
export HAOS_BUILDER_IMAGE=ghcr.io/tinnci/haos-builder:kukui-17.3

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

Local cache/volume defaults:

- Output: `haos-google_kukui-17-3-output`
- ccache: `haos-google_kukui-17-3-ccache`
- Downloads: `$HOME/hassos-cache/dl`

GitHub Actions:

- `Build HAOS builder image`: builds/pushes the GHCR builder image on relevant
  Dockerfile/workflow changes.
- `Build HAOS image (OTBR)`: manual full HAOS image build with validation,
  config, build, export, and artifact verification jobs.

More detail: [`docs/haos-build-ux.md`](docs/haos-build-ux.md).

## Legacy postmarketOS Kernel

The original workflow builds a postmarketOS kernel package for google-kukui with
OTBR/OpenThread multicast routing options.

Start the container:

```sh
docker compose up -d
docker exec -it pmos-builder sh
```

Inside the container:

```sh
sh /scripts/bootstrap-pmbootstrap.sh
sh /scripts/init-pmbootstrap.sh
sh /scripts/patch-kernel-otbr.sh
su -s /bin/sh pmbuild -c "export HOME=/work/pmbootstrap; pmbootstrap build linux-postmarketos-mediatek-mt81"
```

Flash through pmbootstrap:

```sh
docker exec pmos-builder sh -c \
  'su -s /bin/sh pmbuild -c "export HOME=/work/pmbootstrap; pmbootstrap flasher flash_kernel --device google-kukui"'
```
