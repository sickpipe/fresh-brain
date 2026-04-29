#!/usr/bin/env bash
# test-python-detection.sh — self-test for setup.sh's Python detection logic.
#
# We don't run the whole setup.sh (it touches Postgres, writes .env, starts
# daemons). Instead we extract the detection block and exercise it in
# isolation with mocked `uname` and `python3` per test case, plus an
# overridden find_brew_py312 that points at fixture paths inside a tmpdir
# (so tests don't depend on what brew has actually installed).
#
# Run:
#   ./scripts/test-python-detection.sh
# Exits 0 on all-pass, 1 on any failure.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SETUP_SH="$SCRIPT_DIR/../setup.sh"

if [ ! -f "$SETUP_SH" ]; then
    echo "FAIL: cannot find setup.sh at $SETUP_SH" >&2
    exit 2
fi

RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'

PASS=0
FAIL=0

# Extract detection block: from the "Platform-aware Python selection."
# header comment to (but not including) the next "# Schema files exist"
# marker. sed-based to avoid macOS awk's quirks with multi-line -v.
extract_block_to() {
    local out="$1"
    sed -n '/^# Platform-aware Python selection\./,/^# Schema files exist/p' "$SETUP_SH" \
        | sed '$d' > "$out"
    [ -s "$out" ] || { echo "FAIL: could not extract detection block" >&2; exit 2; }
}

# run_case <name> <fake_os> <fake_py_ver> <fake_py_arch> <brew_layout> <expect>
#   fake_os:        Darwin | Linux
#   fake_py_ver:    e.g. 3.13 | 3.11 | 3.9
#   fake_py_arch:   x86_64 | arm64
#   brew_layout:    none | arm64 | intel | both
#   expect:         fallback | nofallback | failhard
run_case() {
    local name="$1" fake_os="$2" fake_py_ver="$3" fake_py_arch="$4" \
          brew_layout="$5" expect="$6"

    local tmp; tmp=$(mktemp -d)

    # uname shim
    cat > "$tmp/uname" <<EOF
#!/usr/bin/env bash
case "\$1" in
    -s) echo "$fake_os" ;;
    -m) echo "$fake_py_arch" ;;
    *)  echo "$fake_os" ;;
esac
EOF
    chmod +x "$tmp/uname"

    # python3 shim — answers --version, sys.version_info, platform.machine()
    cat > "$tmp/python3" <<EOF
#!/usr/bin/env bash
if [ "\$1" = "--version" ]; then
    echo "Python $fake_py_ver.0"; exit 0
fi
if [ "\$1" = "-c" ]; then
    case "\$2" in
        *sys.version_info*) echo "$fake_py_ver"; exit 0 ;;
        *platform.machine*) echo "$fake_py_arch"; exit 0 ;;
    esac
fi
exit 0
EOF
    chmod +x "$tmp/python3"

    # Fake brew prefixes — populate per requested layout
    case "$brew_layout" in
        none) ;;
        arm64)
            mkdir -p "$tmp/arm64"; : > "$tmp/arm64/python3"; chmod +x "$tmp/arm64/python3" ;;
        intel)
            mkdir -p "$tmp/intel"; : > "$tmp/intel/python3"; chmod +x "$tmp/intel/python3" ;;
        both)
            mkdir -p "$tmp/arm64" "$tmp/intel"
            : > "$tmp/arm64/python3"; chmod +x "$tmp/arm64/python3"
            : > "$tmp/intel/python3"; chmod +x "$tmp/intel/python3" ;;
    esac

    # Build the program file:
    #   1. helpers (ok/warn/info/fail with non-system-exiting fail)
    #   2. detection block (with find_brew_py312 body replaced via sed)
    #   3. final result echo
    local prog="$tmp/run.sh"
    {
        cat <<'EOF'
ok()   { echo "[OK]   $1"; }
warn() { echo "[WARN] $1"; }
info() { echo "[INFO] $1"; }
fail() { echo "[FAIL] $1"; exit 99; }
EOF
        # Extract a fresh copy of the detection block, then use sed to
        # rewrite the loop list inside find_brew_py312 to point at the
        # fixture paths in $tmp. The function body is exactly:
        #   for p in /opt/homebrew/.../python3 \
        #            /usr/local/.../python3; do
        # We replace those two literal paths with our fixtures.
        local block="$tmp/block.sh"
        extract_block_to "$block"
        sed \
            -e "s|/opt/homebrew/opt/python@3.12/libexec/bin/python3|$tmp/arm64/python3|g" \
            -e "s|/usr/local/opt/python@3.12/libexec/bin/python3|$tmp/intel/python3|g" \
            "$block"
        echo 'echo "RESULT_PYTHON_BIN=$PYTHON_BIN"'
    } > "$prog"

    # Execute with PATH containing only our shims plus minimal system bins
    # (sed/awk/grep aren't called from the block, but bash builtins suffice).
    local out rc=0
    out=$(PATH="$tmp:/usr/bin:/bin" bash "$prog" 2>&1) || rc=$?

    local got=""
    if [ "$rc" -eq 99 ]; then
        got="failhard"
    elif echo "$out" | grep -q "RESULT_PYTHON_BIN=python3$"; then
        got="nofallback"
    elif echo "$out" | grep -qE "RESULT_PYTHON_BIN=$tmp/(arm64|intel)/python3$"; then
        got="fallback"
    else
        got="UNKNOWN(rc=$rc)"
    fi

    if [ "$got" = "$expect" ]; then
        echo -e "${GREEN}PASS${NC} $name"
        PASS=$((PASS + 1))
    else
        echo -e "${RED}FAIL${NC} $name"
        echo "      expected: $expect"
        echo "      got:      $got"
        echo "      output:"
        echo "$out" | sed 's/^/        /'
        FAIL=$((FAIL + 1))
    fi

    rm -rf "$tmp"
}

echo ""
echo "===== Python detection self-tests ====="
echo ""

# Case 1 (the original bug): macOS + x86_64 Python 3.13
run_case "macOS x86_64 + Py3.13 + arm64-brew py312"          Darwin 3.13 x86_64 arm64 fallback
run_case "macOS x86_64 + Py3.13 + intel-brew py312"          Darwin 3.13 x86_64 intel fallback
run_case "macOS x86_64 + Py3.13 + both prefixes have py312"  Darwin 3.13 x86_64 both  fallback
run_case "macOS x86_64 + Py3.13 + no brew py312 -> failhard" Darwin 3.13 x86_64 none  failhard

# Native Apple Silicon Python 3.13 — torch supports it, no fallback
run_case "macOS arm64 + Py3.13 (native, no fallback)"        Darwin 3.13 arm64  both  nofallback

# x86_64 Python 3.11 — torch 2.2.x has 3.11 wheels, no fallback
run_case "macOS x86_64 + Py3.11 (torch 2.2.x has wheels)"    Darwin 3.11 x86_64 both  nofallback

# Sibling bug: too-old Python on Apple Silicon
run_case "macOS arm64 + Py3.9 (too old, sibling fix)"        Darwin 3.9  arm64  arm64 fallback
run_case "macOS arm64 + Py3.9 + no brew py312 -> failhard"   Darwin 3.9  arm64  none  failhard

# Right at the minimum supported version
run_case "macOS arm64 + Py3.10 (at minimum, no fallback)"    Darwin 3.10 arm64  both  nofallback

# Linux: never trigger fallback (Linux has wheels for all combos)
run_case "Linux x86_64 + Py3.13"                             Linux  3.13 x86_64 none  nofallback
run_case "Linux arm64 + Py3.9"                               Linux  3.9  arm64  none  nofallback

echo ""
echo "===== Results: $PASS passed, $FAIL failed ====="
echo ""

[ "$FAIL" -gt 0 ] && exit 1
exit 0
