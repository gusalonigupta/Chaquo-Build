# Chaquopy minimal bundle-builder

This repo builds minimal Chaquopy-compatible module bundles (e.g. `yt-dlp` + deps) per ABI using Chaquopy's `chaquopy.pip_install` helper.

## Quick overview

- **What it does**: CI runs `chaquopy.pip_install` to fetch/build packages for Android ABIs and packages the result into `requirements-*.imy` files and a `bundle-*.zip` with `native/<abi>/` if there are .so files.
- **You don't pre-supply packages** — CI fetches them from PyPI / Chaquopy index.
- **If native build fails**: script parses the log and suggests either apt `-dev` packages to install in CI or exact `native/<abi>/lib*.so` filenames and paths to provide manually.

## How to use (locally)
1. Clone this repo.
2. Ensure Python host matches the requested Python (e.g. `3.11`).
3. Install build-essential and dev libs (zlib1g-dev libssl-dev etc).
4. Run:
   ```bash
   ./scripts/build_chaquopy_bundle.sh --python 3.11 --package "yt-dlp==2025.08.01" --abi arm64-v8a --abi x86_64

5. Artifacts will be in bundle-output/.



CI

Use .github/workflows/build.yml. Trigger via GitHub UI or gh CLI with inputs.

Notes

The script runs pip install -e ./chaquopy (cloned automatically) and uses python -m chaquopy.pip_install.

Ensure your CI runner has necessary -dev packages installed to successfully build native wheels.

The produced bundle is intentionally minimal (package code + native .so under native/<abi>/ + build.json) because your app includes the Chaquopy runtime and standard library already.