# HAOS Kukui Build Operations

This is the maintenance runbook for the HAOS `google_kukui` build lane. It keeps
the current contracts in one place and replaces older phase-by-phase planning
notes.

## Operating Model

`scripts/haos-buildctl.sh` is the stable interface. Workflows should stay thin
and call this script rather than duplicating build logic.

Default lane:

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

Recovery commands:

```sh
scripts/haos-buildctl.sh diagnostics
scripts/haos-buildctl.sh resume-build
```

Local reuse defaults:

- Output volume: `haos-google_kukui-17-3-output`
- ccache volume: `haos-google_kukui-17-3-ccache`
- Download cache: `$HOME/hassos-cache/dl`

CI sets `HAOS_CCACHE_DIR=/tmp/haos-ccache` so `actions/cache` can persist ccache
without relying on a Docker volume.

## Stage Contracts

- `source-probe`: fail closed when upstream repo/ref, submodules, required paths,
  or patch anchors drift.
- `layer-source`: prepare the HAOS checkout, apply Kukui and OTBR patches, and
  write source/build metadata.
- `layer-builder`: verify the builder image tools before long builds start.
- `layer-download`: create target config and warm selected Buildroot source
  downloads under `/cache/dl`.
- `layer-compile`: run `google_kukui-config` and the full `google_kukui` build.
- `layer-artifact`: export, checksum, verify, and prepare final artifacts.

Lower-level commands (`bootstrap`, `patch`, `config`, `cache-warm`, `build`,
`export-artifacts`, `verify-artifacts`) exist for targeted recovery only.

## CI Lanes

| Workflow | Trigger | Purpose |
| --- | --- | --- |
| `HAOS validate and upstream probe` | push, PR, schedule, manual | Fast checks for scripts, workflow wiring, upstream drift, builder smoke, and target config. |
| `Build HAOS builder image` | builder changes, manual | Publish GHCR builder image and attest the image digest. |
| `Build HAOS image (OTBR)` | manual | Full image build, export, verification, upload, and attestation. |
| `Build pmos kernel (google-kukui)` | push, PR, manual, release call | Legacy kernel APK build with checksum and attestation. |

The full HAOS image workflow stays manual because it is long-running. Use the
validate workflow for normal push confidence; dispatch the full build when the
builder, patches, or upstream baseline need end-to-end proof.

## Artifact And Attestation Contract

`layer-artifact` exports `work/haos-artifacts` with final images and metadata:

- `kernel.img`
- `haos_google-kukui-*.img.xz`
- `haos_google-kukui-*.raucb`
- `mt8183-kukui*.dtb`
- `verification/SHA256SUMS`
- `verification/build-metadata.env`
- `verification/artifact-modes.txt`

`verify-artifacts` checks artifact presence, RAUC custom depthcharge backend
metadata, the pre-upload executable mode recorded in `artifact-modes.txt`, and
ChromeOS kernel partition GUIDs. Do not rely on downloaded GitHub artifact file
modes for executable-bit checks.

Attested subjects:

- GHCR builder image digest.
- HAOS artifacts listed in `verification/SHA256SUMS`.
- HAOS `verification/build-metadata.env`, `verification/SHA256SUMS`, and
  `verification/artifact-modes.txt`.
- Legacy kernel APKs listed in `artifacts/SHA256SUMS`.

`build-metadata.env` should keep the inputs needed for later diagnosis:

- HAOS repo/ref/resolved commit and target.
- Builder image tag and resolved digest.
- Patch script SHA256 values.
- Output, ccache, and cache identity.
- GitHub run/ref/SHA/job and runner image metadata.

Verify a downloaded artifact with:

```sh
gh attestation verify <artifact> --repo Tinnci/pmos-docker
```

Do not attest full logs, caches, Docker volumes, or every generated object. Upload
logs as diagnostics and record important digests or summaries in metadata.

## Builder Contract

The builder image is:

```text
ghcr.io/tinnci/haos-builder:kukui-17.3
```

`layer-builder` must keep smoke-checking the tools that have broken or are needed
late in the HAOS build:

- `skopeo`
- `sudo`
- `docker` and `dockerd`
- `mkdepthcharge`
- `sgdisk`
- `xz`, `zstd`, `mkfs.erofs`, `mksquashfs`, `mkfs.ext4`, `mkfs.vfat`
- ChromeOS vboot tooling

The entrypoint starts `dockerd`, supports root and mapped builder-user execution,
and must preserve:

- `BR2_DL_DIR`
- `CCACHE_DIR`
- `FORCE_UNSAFE_CONFIGURE`

## Known Failure Boundaries

Preserve these contracts when changing CI:

- Buildroot host tools may reject root configure; keep
  `FORCE_UNSAFE_CONFIGURE=1` on Docker make invocations.
- HAOS packaging uses `skopeo`.
- HAOS post-image generation uses `mkdepthcharge`.
- Host-side artifact verification uses `file` and `xz`.
- HAOS data partition creation needs `sudo`, Docker CLI, and working DinD.
- Root execution should bypass `sudo`; non-root execution must preserve the
  Buildroot cache/config environment.
- Upstream drift should fail in `source-probe`, not during a multi-hour build.

When a full build fails:

1. Pull the log with `gh run view <run-id> --log`.
2. Inspect diagnostics artifacts and failed Buildroot stamps.
3. Use `resume-build` only when source, output volume, and caches are still valid.
4. Fix source-probe expectations first for upstream path/ref/patch-anchor drift.
5. Preserve generated artifacts and metadata when failure occurs after image export.

## Reuse Policy

Safe reuse:

- GHCR builder image.
- Buildroot download cache under `/cache/dl`.
- `ccache`.
- Local Buildroot output Docker volume.
- CI ccache host path.

Avoid for GitHub-hosted CI:

- Full Buildroot output cache. It is large, slow to restore, and unreliable on
  ephemeral runners.
- Binary package substitution outside Buildroot. It weakens reproducibility and
  hides integration problems.

Always keep target-built:

- Kernel `.config`, `Image`, DTBs, and `kernel.img`.
- `rootfs.erofs`.
- Disk image layout.
- RAUC bundle and manifest.
- Board-specific boot backend and slot attributes.

## Maintenance Checklist

When changing HAOS CI:

1. Change `scripts/haos-buildctl.sh` first.
2. Update `tests/haos_buildctl_test.sh` for command contracts.
3. Update `tests/haos_workflow_test.sh` for workflow wiring.
4. If artifact boundaries change, update `SHA256SUMS`, metadata, and attestation
   subjects together.
5. If builder contents change, let `Build HAOS builder image` publish and
   smoke-check before dispatching a full HAOS build.
6. Run:

   ```sh
   for file in tests/*.sh; do sh "$file"; done
   for file in scripts/*.sh tests/*.sh docker/haos-builder/*.sh; do sh -n "$file"; done
   git diff --check
   actionlint
   ```
