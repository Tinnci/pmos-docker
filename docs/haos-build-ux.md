# HAOS Kukui Build UX and Reuse Plan

## Current Operator Interface

This repository currently exposes the HAOS Kukui build through three operator surfaces:

- `README.md`: human-facing runbook for local bring-up.
- `scripts/build-haos-local.sh`: non-interactive local Docker build wrapper.
- `.github/workflows/haos-build.yml`: manually dispatched GitHub Actions build.

There is no graphical UI. The practical UI is a small build console: workflow inputs,
shell scripts, logs, and uploaded artifacts.

## Useful Components to Add

The next layer should be small composable build components, not a monolithic script:

- `preflight`: check disk space, Docker availability, builder image, cache directory, and
  HAOS checkout state before any long build starts.
- `bootstrap`: clone or update `home-assistant/operating-system`, checkout the locked
  upstream ref, and initialize submodules.
- `patch`: apply the Kukui board integration and OTBR kernel fragment idempotently.
- `config`: run `make google_kukui-config` and verify generated Buildroot and Linux
  config values.
- `build`: run the full target build.
- `verify-artifacts`: check `kernel.img`, `.img.xz`, `.raucb`, ChromeOS kernel GPT GUIDs,
  RAUC custom backend, and expected DTB output.
- `export-artifacts`: copy images out of a Docker volume or CI workspace.
- `cache-warm`: prefetch unstable source archives or Go vendored tarballs into `dl/`.
- `diagnostics`: collect free space, Docker usage, Buildroot failed package logs, and
  last relevant build commands.

These components can be called locally and from GitHub Actions with the same arguments.

## GitHub Actions Build

Yes, GitHub Actions can build the whole system. The current workflow already supports a
manual full build with:

- `upstream_ref=17.3`
- `target=google_kukui`

For CI, the workflow should remain a thin orchestrator around the same scripts used
locally. That keeps local and CI behavior aligned.

Recommended workflow shape:

1. Prepare builder image.
2. Restore caches.
3. Bootstrap HAOS upstream.
4. Apply patches.
5. Run config validation.
6. Run full build.
7. Run artifact validation.
8. Upload image artifacts and diagnostic logs.

## Build Reuse Strategy

A full HAOS image is target-specific, so the final root filesystem and RAUC bundle should
still be produced per target. The speedups come from reusing expensive inputs and build
state around that final packaging step.

Reusable pieces:

- Builder Docker image with Debian/Buildroot host dependencies and `mkdepthcharge`.
- Buildroot download cache (`/cache/dl` or `output/dl`).
- Go vendored tarballs for packages such as `os-agent` and `tempio`.
- `ccache` for host and target compilation.
- Buildroot output directory or Docker volume for local incremental builds.
- Kernel source and object cache when the kernel fragment did not change.
- Prebuilt host tools inside the builder image when they are stable enough.

Pieces that should stay target-built:

- Kernel `.config`, `Image`, DTBs, and `kernel.img`.
- `rootfs.erofs`.
- Disk image layout.
- RAUC bundle and manifest.
- Board-specific boot backend and slot attributes.

## Do We Need to Build Every Package from Source?

Not every package needs to be downloaded and compiled from zero every time.
Buildroot uses stamps and caches locally, so an incremental local build should reuse
completed packages. In GitHub Actions, a clean runner starts from scratch unless caches
are restored.

For reliable CI speedups, prefer these in order:

1. Cache downloaded source archives.
2. Cache `ccache`.
3. Use a prebuilt builder image with host dependencies.
4. Split config validation from full image builds.
5. Keep full image builds manual or scheduled until the target is stable.

Avoid replacing Buildroot packages with arbitrary binary packages in v1. That usually
breaks reproducibility and target integration faster than it saves time. Use Buildroot's
own cache and stamp model first.
