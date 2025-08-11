# Chaquopy bundle-builder (Gradle-based)

This repo builds Chaquopy-compatible requirement bundles using Chaquopy's own Gradle build system.

## What it does
- Clones Chaquopy.
- Runs Chaquopy Gradle tasks to build the interpreter (bootstrap/stdlib) and to run `pip_install` for requested pip packages (per ABI).
- Collects the resulting assets (`*.imy`, `build.json`, `bootstrap-native`) into `bundle-output/py<ver>-<timestamp>/chaquopy`.
- Zips the collected assets to `bundle-*.zip`.

## Usage
- Locally:
  - Install Java JDK 17 and Python (matching `--python`).
  - `chmod +x scripts/build_via_gradle.sh`
  - `./scripts/build_via_gradle.sh --python 3.11 --package yt-dlp==2025.08.01 --abi arm64-v8a --abi x86_64`

- On GitHub Actions:
  - Push/PR to `main` or run workflow_dispatch with inputs.

## Notes
- If a native dependency fails to build, the script attempts to parse the Gradle log and emits helpful suggestions:
  - apt packages to install on CI, and/or
  - exact `.so` filenames and `native/<abi>/lib<name>.so` paths to include in the bundle manually.
- The action is intentionally conservative: it uses Gradle tasks Chaquopy already provides (no manual reimplementation).