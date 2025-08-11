#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# Simple driver that runs Chaquopy Gradle tasks and collects assets.
# Usage:
#   ./build_via_gradle.sh --python 3.11 --package yt-dlp==2025.08.01 --abi arm64-v8a --abi x86_64

usage() {
  cat <<USAGE
Usage:
  $0 --python <major.minor> --package <pip_req> [--package <pip_req> ...] --abi <abi> [--abi <abi> ...]

Examples:
  ./scripts/build_via_gradle.sh --python 3.11 --package yt-dlp==2025.08.01 --abi arm64-v8a --abi x86_64
USAGE
  exit 1
}

# defaults from env if present
CHAQUOPY_REF="${CHAQUOPY_REF:-master}"
OUT_BASE="${OUT_BASE:-$(pwd)/bundle-output}"
EXTRA_INDEX="${EXTRA_INDEX:-https://chaquo.com/pypi-13.1}"
MIN_API="${MIN_API:-24}"

# parse args
PY_SHORT=""
PKGS=()
ABIS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --python) PY_SHORT="$2"; shift 2;;
    --package|--pkg) PKGS+=("$2"); shift 2;;
    --abi) ABIS+=("$2"); shift 2;;
    --help|-h) usage;;
    *) echo "Unknown arg: $1"; usage;;
  esac
done

if [[ -z "$PY_SHORT" || "${#PKGS[@]}" -eq 0 || "${#ABIS[@]}" -eq 0 ]]; then
  echo "Missing required args."
  usage
fi

echo "=== Build config ==="
echo "Python short: $PY_SHORT"
echo "Packages: ${PKGS[*]}"
echo "ABIs: ${ABIS[*]}"
echo "Chaquopy ref: $CHAQUOPY_REF"
echo "Out base: $OUT_BASE"
echo "Extra index: $EXTRA_INDEX"
echo "Min API: $MIN_API"
echo "===================="

TMPDIR="$(mktemp -d)"
LOG="$TMPDIR/gradle_build.log"
mkdir -p "$OUT_BASE"

# clone chaquopy if missing, else update
if [[ ! -d "chaquopy" ]]; then
  echo "Cloning Chaquopy..."
  git clone --depth 1 https://github.com/chaquo/chaquopy.git chaquopy
fi
pushd chaquopy >/dev/null
git fetch --depth 1 origin "$CHAQUOPY_REF" || true
git checkout "$CHAQUOPY_REF" || true
popd >/dev/null

# Run Gradle in chaquopy repo. Use the repo's gradlew.
GRADLEW="./chaquopy/gradlew"
if [[ ! -x "$GRADLEW" ]]; then
  echo "Gradle wrapper not found or not executable at $GRADLEW"
  exit 2
fi

# 1) build Python runtime for requested version (bootstrap, stdlib)
echo "Running Gradle: buildPython for Python $PY_SHORT (this may take several minutes)..."
set +e
"$GRADLEW" --no-daemon :product:runtime:buildPython -PpythonVersion="$PY_SHORT" --console=plain >"$LOG" 2>&1
RC_BP=$?
set -e
if [[ $RC_BP -ne 0 ]]; then
  echo "ERROR: Gradle buildPython failed (rc=$RC_BP). Showing tail of log:"
  tail -n 200 "$LOG" || true
  exit $RC_BP
fi
echo "buildPython OK."

# 2) generate requirements (pip install step inside Chaquopy build)
# pass the requirements as a single space-separated string via -Prequirements
REQ_STR="${PKGS[*]}"
ABI_STR="${ABIS[*]}"

echo "Running Gradle: generateRequirements (requirements: $REQ_STR ; abis: $ABI_STR)"
set +e
"$GRADLEW" --no-daemon :product:gradle-plugin:generateRequirements \
  -PpythonVersion="$PY_SHORT" \
  -Prequirements="$REQ_STR" \
  -PandroidAbis="$ABI_STR" \
  -PminApiLevel="$MIN_API" \
  -PextraIndexUrl="$EXTRA_INDEX" \
  --console=plain >>"$LOG" 2>&1
RC_REQ=$?
set -e

if [[ $RC_REQ -ne 0 ]]; then
  echo "ERROR: generateRequirements failed (rc=$RC_REQ). Attempting to parse actionable errors..."
  echo "---- tail of Gradle log (200 lines) ----"
  tail -n 200 "$LOG" || true
  echo "---- end log tail ----"
  # scan log for missing libs / headers and produce suggestions
  MISSING=()
  while IFS= read -r line; do
    if [[ "$line" =~ cannot\ find\ -l([A-Za-z0-9_@-]+) ]]; then
      MISSING+=("${BASH_REMATCH[1]}")
    elif [[ "$line" =~ "ld: library not found for -l([A-Za-z0-9_@-]+)" ]]; then
      MISSING+=("${BASH_REMATCH[1]}")
    elif [[ "$line" =~ fatal\ error:\ ([a-zA-Z0-9_/.-]+)\.h ]]; then
      hdr="${BASH_REMATCH[1]}"
      case "$hdr" in
        openssl/*|openssl) MISSING+=("crypto"); MISSING+=("ssl");;
        zlib) MISSING+=("z");;
        bzlib|bz2) MISSING+=("bz2");;
        sqlite3) MISSING+=("sqlite3");;
        gmp) MISSING+=("gmp");;
        lzma) MISSING+=("lzma");;
      esac
    fi
  done < <(grep -E "cannot find -l|ld: library not found|fatal error:" "$LOG" || true)

  if [[ ${#MISSING[@]} -gt 0 ]]; then
    # dedupe
    mapfile -t UNIQLIBS < <(printf "%s\n" "${MISSING[@]}" | awk '!seen[$0]++')
    echo
    echo "== Native build hints (from Gradle output) =="
    echo "Detected missing libraries/headers. Two options:"
    echo "  A) Install dev packages on the CI runner (recommended)."
    echo "     Examples (apt): libssl-dev zlib1g-dev libbz2-dev libsqlite3-dev libgmp-dev liblzma-dev"
    echo "  B) Provide prebuilt Android .so files manually and include them in the bundle under native/<abi>/"
    echo
    echo "Mapped missing libs -> suggested filenames:"
    for L in "${UNIQLIBS[@]}"; do
      echo "  - $L  -> lib${L}.so"
    done
    echo
    echo "If you choose option B, add these files into the final zip at (for each ABI):"
    for a in "${ABIS[@]}"; do
      for L in "${UNIQLIBS[@]}"; do
        echo "  native/${a}/lib${L}.so"
      done
    done
    echo
    echo "Full Gradle log is available at: $LOG"
    exit 3
  else
    echo "generateRequirements failed but we couldn't find missing-lib / header patterns in the log."
    echo "Please inspect: $LOG"
    exit $RC_REQ
  fi
fi

echo "generateRequirements OK."

# 3) collect built assets (.imy files, build.json, bootstrap-native etc.)
OUT_TS="$(date +%Y%m%d-%H%M%S)"
OUT_DIR="$OUT_BASE/py${PY_SHORT}-$OUT_TS"
mkdir -p "$OUT_DIR"
echo "Collecting build artifacts into: $OUT_DIR"

# search for all .imy and build.json files inside the chaquopy build tree and copy them
# preserve the path after the first '/assets/' segment so we reproduce Chaquopy asset layout.
find chaquopy -type f \( -name "*.imy" -o -name "build.json" -o -name "cacert.pem" \) | while read -r file; do
  # relative path after 'assets/' if present
  rel=$(echo "$file" | sed -n 's@.*assets/\(.*\)@\1@p')
  if [[ -z "$rel" ]]; then
    # if assets/ not in path, put under top-level folder in out
    rel=$(basename "$file")
  fi
  dest="$OUT_DIR/chaquopy/$rel"
  mkdir -p "$(dirname "$dest")"
  cp -f "$file" "$dest"
  echo "Copied: $file -> $dest"
done

# also copy any bootstrap-native dirs (native libs) found
find chaquopy -type d -name "bootstrap-native" -print | while read -r d; do
  # copy full structure under OUT_DIR/chaquopy/bootstrap-native
  dest="$OUT_DIR/chaquopy/$(basename "$d")"
  mkdir -p "$dest"
  rsync -a "$d/" "$OUT_DIR/chaquopy/bootstrap-native/" || true
  echo "Copied bootstrap-native from $d -> $OUT_DIR/chaquopy/bootstrap-native/"
done

# if no .imy were found, try copying any 'assets/chaquopy' directories directly
if [[ -z "$(find "$OUT_DIR" -type f -name '*.imy' -print -quit)" ]]; then
  echo "No .imy files found; attempting to copy any assets/chaquopy directories as fallback..."
  find chaquopy -type d -name "chaquopy" -path "*/build/*/assets/*" -print | while read -r d; do
    echo "Found candidate chaquopy dir: $d"
    rsync -a "$d/" "$OUT_DIR/chaquopy/" || true
  done
fi

# final sanity check
if [[ -z "$(find "$OUT_DIR" -type f -name '*.imy' -print -quit)" ]]; then
  echo "ERROR: no .imy files found in Chaquopy build outputs. See gradle log: $LOG"
  exit 4
fi

# 4) create zip artifact
BUNDLE_ZIP="$OUT_DIR/bundle-py${PY_SHORT}-$OUT_TS.zip"
pushd "$OUT_DIR" >/dev/null
zip -r "$BUNDLE_ZIP" "chaquopy" >/dev/null
popd >/dev/null

echo "Bundle created: $BUNDLE_ZIP"
echo "Artifacts located under: $OUT_DIR"
echo "Uploading/packaging finished."

# print short summary of files produced
echo
echo "=== Produce summary ==="
find "$OUT_DIR" -maxdepth 3 -type f -print
echo "=== End summary ==="