# HAOS Kukui Build UX and Reuse Plan

## Current Operator Interface

This repository currently exposes the HAOS Kukui build through three operator surfaces:

- `README.md`: human-facing runbook for local bring-up.
- `scripts/haos-buildctl.sh`: the stable command interface for local and CI stages.
- `scripts/build-haos-local.sh`: the lower-level Docker make executor used by buildctl.
- `.github/workflows/haos-build.yml`: manually dispatched GitHub Actions build split into
  validation, config, build, and artifact verification jobs.
- `.github/workflows/haos-builder-image.yml`: GHCR builder-image publication.

There is no graphical UI. The practical UI is a small build console: workflow inputs,
shell scripts, logs, and uploaded artifacts.

## Useful Components to Add

The build is now decomposed into small composable components, exposed through
`scripts/haos-buildctl.sh`:

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
- `cache-warm`: prefetch unstable source archives or Go vendored tarballs into `/cache/dl`.
- `diagnostics`: collect free space, Docker usage, Buildroot failed package logs, and
  last relevant build commands.

These components can be called locally and from GitHub Actions with the same arguments.

Local command shape:

```sh
scripts/haos-buildctl.sh preflight
scripts/haos-buildctl.sh bootstrap
scripts/haos-buildctl.sh patch
scripts/haos-buildctl.sh config
scripts/haos-buildctl.sh cache-warm
scripts/haos-buildctl.sh build
scripts/haos-buildctl.sh export-artifacts
scripts/haos-buildctl.sh verify-artifacts
```

Default local cache and volume contract:

- Output volume: `haos-google_kukui-17-3-output`
- ccache volume: `haos-google_kukui-17-3-ccache`
- Download cache: `$HOME/hassos-cache/dl`
- Builder image: `hassos:local` locally, or
  `ghcr.io/Tinnci/haos-builder:kukui-17.3` when the prebuilt image is available.

CI can replace the ccache volume with a host path by setting
`HAOS_CCACHE_DIR=/tmp/haos-ccache`, which lets `actions/cache` persist it.

## GitHub Actions Build

Yes, GitHub Actions can build the whole system. The current workflow already supports a
manual full build with:

- `upstream_ref=17.3`
- `target=google_kukui`

For CI, the workflow should remain a thin orchestrator around the same scripts used
locally. That keeps local and CI behavior aligned.

Current workflow shape:

1. `validate-scripts`: shell syntax, buildctl tests, Kukui patch tests, workflow tests.
2. `config-google-kukui`: restore download and ccache caches, bootstrap HAOS, apply
   Kukui/OTBR patches, run `google_kukui-config`, upload diagnostics.
3. `build-google-kukui`: restore caches, bootstrap HAOS, apply patches, run config,
   warm package source cache, build the image, export artifacts, upload diagnostics.
4. `verify-artifacts`: download exported artifacts and verify `.img.xz`, `.raucb`,
   `kernel.img`, ChromeOS GPT GUIDs, and exported RAUC backend metadata.

The workflow intentionally does not cache the full Buildroot output directory on
GitHub-hosted runners. That cache is large, slow to restore, and easy to evict. Full
output reuse should wait for a self-hosted runner.

## Prebuilt Builder Image

The builder image lives at `docker/haos-builder/Dockerfile` and is published by
`.github/workflows/haos-builder-image.yml` as:

```text
ghcr.io/Tinnci/haos-builder:kukui-17.3
```

It preinstalls stable host-side dependencies such as compiler tools, `gdisk`, `ccache`,
`vboot-utils`, filesystem tools, and compression tools. The main image build workflow can
then avoid repeated apt setup and focus on HAOS/Buildroot work.

When running locally, use the prebuilt image by setting:

```sh
export HAOS_BUILDER_IMAGE=ghcr.io/Tinnci/haos-builder:kukui-17.3
```

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

## Long-Term Goals

The long-term goal is a reproducible HAOS Kukui build lane that can run locally,
on GitHub-hosted runners, and on a future self-hosted runner with the same stage
commands and artifact checks.

### Phase 1: Stabilize the Interface

- Done: keep `scripts/haos-buildctl.sh` as the only operator entrypoint.
- Done: keep `scripts/build-haos-local.sh` as the Docker make executor used by buildctl.
- Done: keep patch scripts idempotent and macOS/Linux-safe.
- Done: make every stage runnable independently.
- Next: add richer config assertions for Linux kernel deltas after each upstream bump.

### Phase 2: Add Fast, Cheap Reuse

- Done: cache Buildroot download archives under `/cache/dl`.
- Done: warm `dbus-glib`, `os-agent`, and `tempio` source targets.
- Done: add a local ccache volume and CI ccache host path.
- Done: keep Docker output in a named local volume for incremental rebuilds.
- Done: add a `resume-build` lane for direct Buildroot continuation after post-image or
  package failures.
- Next: record ccache hit rate in diagnostics.

### Phase 3: Prebuild the Builder

- Done: add `docker/haos-builder/Dockerfile`.
- Done: add `.github/workflows/haos-builder-image.yml`.
- Done: include `gdisk`, `vboot-utils`, `ccache`, filesystem tools, and compression tools.
- Done: make the main build workflow consume `ghcr.io/Tinnci/haos-builder:kukui-17.3`.
- Next: confirm the first GHCR image build on GitHub and pin package additions if needed.

### Phase 4: Split CI by Confidence Level

- Done: split CI into script validation, config, full build, and artifact verification.
- Done: upload diagnostics on failure even when image artifacts are missing.
- Next: add scheduled full builds after the first green GHCR builder image exists.
- Next: promote successful full builds into retained release artifacts.

### Phase 5: Self-Hosted Incremental Builds

- Add a self-hosted runner profile once the target is stable.
- Persist Buildroot output, downloads, ccache, and Docker layers across runs.
- Keep GitHub-hosted full builds as clean-room reproducibility checks.
- Use self-hosted runs for fast iteration and GitHub-hosted runs for release confidence.

### Phase 6: Package-Level Optimization

- Review the inherited `generic_aarch64` package and kernel module surface.
- Remove unneeded firmware and modules only after Kukui boot logs prove what the
  tablet actually needs.
- Keep target-specific kernel, DTBs, `kernel.img`, rootfs, image layout, and RAUC
  bundle built by Buildroot.
- Avoid ad-hoc binary package substitution unless it is represented as a controlled
  Buildroot package or cache input.
