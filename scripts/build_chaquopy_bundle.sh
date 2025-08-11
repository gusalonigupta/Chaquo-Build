#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

usage() {
  cat <<-USAGE
  Usage:
    $0 --python 3.11 --package "yt-dlp==2025.08.01" [--package "other==x"] --abi arm64-v8a [--abi armeabi-v7a ...]
  Environment vars:
    CHAQUOPY_REF   (optional) git ref to checkout; default: master
    OUT_BASE       (optional) output base dir; default: ./bundle-output
    EXTRA_INDEX    (optional) extra index URL; default: https://chaquo.com/pypi-13.1
    MIN_API        (optional) android min api level; default: 24
  Example:
    ./build_chaquopy_bundle.sh --python 3.11 --package yt-dlp==2025.08.01 --abi arm64-v8a --abi armeabi-v7a
USAGE
  exit 1
}

# defaults
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
    --package) PKGS+=("$2"); shift 2;;
    --pkg) PKGS+=("$2"); shift 2;;
    --abi) ABIS+=("$2"); shift 2;;
    --help|-h) usage;;
    *) echo "Unknown arg: $1"; usage;;
  esac
done

if [[ -z "$PY_SHORT" || "${#PKGS[@]}" -eq 0 || "${#ABIS[@]}" -eq 0 ]]; then
  usage
fi

echo "Build config:"
echo "  Python (short): $PY_SHORT"
echo "  Packages: ${PKGS[*]}"
echo "  ABIs: ${ABIS[*]}"
echo "  Chaquopy ref: $CHAQUOPY_REF"
echo "  Output base: $OUT_BASE"
echo "  Extra index: $EXTRA_INDEX"
echo "  Min API: $MIN_API"

TMP="$(mktemp -d)"
TARGET_DIR="$TMP/pip_target"
LOG="$TMP/pip_install.log"
mkdir -p "$TARGET_DIR" "$OUT_BASE"

# clone chaquopy if not present
if [[ ! -d "chaquopy" ]]; then
  echo "Cloning Chaquopy..."
  git clone --depth 1 https://github.com/chaquo/chaquopy.git chaquopy
fi
pushd chaquopy >/dev/null
git fetch --depth 1 origin "$CHAQUOPY_REF" || true
git checkout "$CHAQUOPY_REF" || true
popd >/dev/null

# ensure host python is the requested short version (warning if mismatch)
PY_BIN=python
PY_FULL=$($PY_BIN - <<'PY'
import sys
print("%d.%d.%d" % (sys.version_info.major, sys.version_info.minor, sys.version_info.micro))
PY
)
PY_SHORT_HOST=$($PY_BIN - <<'PY'
import sys
print("%d.%d" % (sys.version_info.major, sys.version_info.minor))
PY
)
echo "Host Python: $PY_FULL (short $PY_SHORT_HOST)"
if [[ "$PY_SHORT_HOST" != "$PY_SHORT" ]]; then
  echo "Warning: host python $PY_SHORT_HOST != requested $PY_SHORT. Use actions/setup-python on CI."
fi

# pip install editable chaquopy into host python
echo "Installing Chaquopy package into host python (editable)..."
$PY_BIN -m pip install --upgrade pip setuptools wheel >/dev/null
$PY_BIN -m pip install -e ./chaquopy >/dev/null

# build the chaquopy.pip_install command
CMD=( "$PY_BIN" -m chaquopy.pip_install --target "$TARGET_DIR" --min-api-level "$MIN_API" )
CMD+=( --android-abis )
for a in "${ABIS[@]}"; do CMD+=( "$a" ); done
for r in "${PKGS[@]}"; do CMD+=( --req "$r" ); done

# internal pip options after --
CMD+=( -- --disable-pip-version-check --extra-index-url "$EXTRA_INDEX" --implementation cp )

# Provide full python-version and abi strings to chaquopy helper
# Use host PY_FULL to set python-version (approx match). User should ensure host python matches.
CMD+=( --python-version "$PY_FULL" --abi "cp${PY_SHORT//./}" --no-compile )

echo "Running chaquopy.pip_install..."
printf '%q ' "${CMD[@]}"
echo
# run and capture logs
set +e
"${CMD[@]}" >"$LOG" 2>&1
RC=$?
set -e

if [[ $RC -ne 0 ]]; then
  echo "ERROR: chaquopy.pip_install failed (rc=$RC). Showing tail of log and attempting to parse actionables."
  echo "---- LOG (tail 200 lines) ----"
  tail -n 200 "$LOG" || true
  echo "---- END LOG ----"
  # parse for linker/header errors -> map to lib names
  MISSING_LIBS=()
  while IFS= read -r line; do
    if [[ "$line" =~ cannot\ find\ -l([A-Za-z0-9_@-]+) ]]; then
      MISSING_LIBS+=("${BASH_REMATCH[1]}")
    elif [[ "$line" =~ "ld: library not found for -l([A-Za-z0-9_@-]+)" ]]; then
      MISSING_LIBS+=("${BASH_REMATCH[1]}")
    elif [[ "$line" =~ fatal\ error:\ ([a-zA-Z0-9_/.-]+)\.h ]]; then
      hdr="${BASH_REMATCH[1]}"
      case "$hdr" in
        openssl/*|openssl) MISSING_LIBS+=("crypto"); MISSING_LIBS+=("ssl");;
        zlib) MISSING_LIBS+=("z");;
        bzlib|bz2) MISSING_LIBS+=("bz2");;
        sqlite3) MISSING_LIBS+=("sqlite3");;
        gmp) MISSING_LIBS+=("gmp");;
        lzma) MISSING_LIBS+=("lzma");;
      esac
    fi
  done < <(grep -E "cannot find -l|ld: library not found|fatal error:" "$LOG" || true)

  # dedupe
  if [[ ${#MISSING_LIBS[@]} -gt 0 ]]; then
    mapfile -t UNIQLIBS < <(printf "%s\n" "${MISSING_LIBS[@]}" | awk '!seen[$0]++')
    echo
    echo "== Native build hints =="
    echo "Detected missing native libs/headers; you can either:"
    echo "  1) Install -dev packages in CI (recommended)."
    echo "     Example apt packages: libssl-dev zlib1g-dev libbz2-dev libsqlite3-dev libgmp-dev liblzma-dev"
    echo "  2) Provide prebuilt Android .so files and place them into the bundle under native/<abi>/lib<name>.so"
    echo
    echo "Missing libs (mapped):"
    for L in "${UNIQLIBS[@]}"; do
      echo "  - $L    -> suggested filename: lib${L}.so"
    done
    echo
    echo "If you choose option 2, place each lib into the following paths inside the final zip (for each ABI):"
    for abi in "${ABIS[@]}"; do
      for L in "${UNIQLIBS[@]}"; do
        echo "  native/${abi}/lib${L}.so"
      done
    done
    echo
    echo "Full log saved at: $LOG"
    exit 3
  else
    echo "pip_install failed but no obvious missing-link/header errors found. Check log: $LOG"
    exit $RC
  fi
fi

echo "pip_install succeeded; packaging outputs..."

# run packer (python helper)
mkdir -p "$OUT_BASE"
OUT_DIR="$OUT_BASE/py${PY_SHORT}-$(date +%Y%m%d-%H%M%S)"
python3 "$(dirname "$0")/pack_imy.py" "$TARGET_DIR" "$OUT_DIR" "${PY_SHORT}" "${ABIS[*]}"
echo "Artifacts written to: $OUT_DIR"
echo "Done."