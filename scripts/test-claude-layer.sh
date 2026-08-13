#!/usr/bin/env bash
# test-claude-layer.sh — self-test for scripts/lib/claude-layer.sh.
#
# Every case runs against a throwaway HOME created with `mktemp -d`. The real
# ~/.claude is never written to; the last test asserts that (a live install
# holds a customized global CLAUDE.md and months of memory files, so a stray
# write here would be destructive).
#
# setup.sh is never invoked — it creates databases, starts daemons and
# registers MCP servers. Only the library is sourced.
#
# Run:
#   ./scripts/test-claude-layer.sh
# Exits 0 on all-pass, 1 on any failure.
#
# bash 3.2 compatible (macOS /bin/bash).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
LIB="$REPO/scripts/lib/claude-layer.sh"
REAL_HOME="$HOME"

if [ ! -f "$LIB" ]; then
    echo "FAIL: cannot find claude-layer.sh at $LIB" >&2
    exit 2
fi

WORK="$(mktemp -d "${TMPDIR:-/tmp}/fbtest.XXXXXX")"
HOMES=""
PASS=0
FAILN=0

# Fingerprint the real global CLAUDE.md before anything runs, so the safety
# test at the bottom can prove this harness never wrote to it.
REAL_CLAUDE_MD_SUM_BEFORE=""
if [ -f "$REAL_HOME/.claude/CLAUDE.md" ]; then
    REAL_CLAUDE_MD_SUM_BEFORE=$(shasum "$REAL_HOME/.claude/CLAUDE.md" | awk '{print $1}')
fi

cleanup() {
    local h
    for h in $HOMES; do rm -rf "$h"; done
    rm -rf "$WORK"
}
trap cleanup EXIT

# new_home — a fresh throwaway HOME, registered for cleanup.
new_home() {
    local h; h="$(mktemp -d "${TMPDIR:-/tmp}/fbhome.XXXXXX")"
    HOMES="$HOMES $h"
    echo "$h"
}

# run_lib <home> <function> [args...] — source the library under a redirected
# HOME in a subshell and call one of its entry points. stdin is closed so an
# accidental prompt fails loudly instead of hanging CI.
run_lib() {
    local h="$1"; shift
    ( export HOME="$h"; . "$LIB"; "$@" ) < /dev/null 2>&1
}

chk() { # chk <desc> <cmd...>
    local desc="$1"; shift
    if "$@" >/dev/null 2>&1; then
        echo "  PASS  $desc"; PASS=$((PASS + 1))
    else
        echo "  FAIL  $desc"; FAILN=$((FAILN + 1))
    fi
}

# Marker helpers — kept out of the library's own constants on purpose, so a
# marker string change has to be made deliberately in both places.
BEGIN_RE='<!-- FRESH BRAIN: BEGIN'
END_RE='<!-- FRESH BRAIN: END'

count_lines() { grep -Fc "$1" "$2" 2>/dev/null | tr -d ' '; }

# well_formed <file> — exactly one BEGIN, at least one END, END after BEGIN.
well_formed() {
    local f="$1" nb ne bline eline
    nb=$(count_lines "$BEGIN_RE" "$f"); ne=$(count_lines "$END_RE" "$f")
    [ "$nb" = "1" ] || return 1
    [ "$ne" -ge 1 ] || return 1
    bline=$(grep -Fn "$BEGIN_RE" "$f" | head -1 | cut -d: -f1)
    eline=$(grep -Fn "$END_RE" "$f" | tail -1 | cut -d: -f1)
    [ "$eline" -gt "$bline" ]
}

backup_count() { ls "$1"/CLAUDE.md.pre-fresh-brain-*.bak 2>/dev/null | wc -l | tr -d ' '; }
latest_backup() { ls "$1"/CLAUDE.md.pre-fresh-brain-*.bak 2>/dev/null | tail -1; }

echo ""
echo "===== Claude Code layer self-tests ====="
echo "bash version: $BASH_VERSION"
echo "repo:         $REPO"
echo ""

# ─────────────────────────────────────────────────────────────
echo "=== TEST 1: fresh create (no ~/.claude at all) ==="
T1="$(new_home)"
run_lib "$T1" install_claude_layer "$REPO" auto
echo "--- tree ---"
find "$T1" -type f | sed "s|$T1|\$HOME|" | sort
echo "--- \$HOME/.claude/CLAUDE.md ---"
cat "$T1/.claude/CLAUDE.md"
echo "--- assertions ---"
chk "global CLAUDE.md exists"        test -f "$T1/.claude/CLAUDE.md"
chk "BEGIN marker present"           grep -Fq "$BEGIN_RE" "$T1/.claude/CLAUDE.md"
chk "END marker present"             grep -Fq "$END_RE" "$T1/.claude/CLAUDE.md"
chk "routing map present"            grep -Fq "Database routing" "$T1/.claude/CLAUDE.md"
chk "brain skill installed"          test -f "$T1/.claude/skills/brain/SKILL.md"
chk "end-session skill installed"    test -f "$T1/.claude/skills/end-session/SKILL.md"
SLUG1=$(printf '%s' "$T1" | tr '/' '-')
chk "memory index seeded"            test -f "$T1/.claude/projects/$SLUG1/memory/MEMORY.md"
chk "memory seed file seeded"        test -f "$T1/.claude/projects/$SLUG1/memory/reference_fresh_brain_databases.md"
chk "no backups dir (nothing to back up)" test '!' -d "$T1/.claude/backups"
echo ""

# ─────────────────────────────────────────────────────────────
echo "=== TEST 2: append to a pre-existing custom CLAUDE.md (must preserve verbatim) ==="
T2="$(new_home)"
mkdir -p "$T2/.claude"
cat > "$T2/.claude/CLAUDE.md" <<'ORIG'
# Working with Claude here

Concise. Direct questions expect direct answers.

## Style
- Answer first. No preamble.
- Default ceiling ~4 sentences.
ORIG
printf '%s' "MY LAST LINE HAS NO TRAILING NEWLINE" >> "$T2/.claude/CLAUDE.md"
cp "$T2/.claude/CLAUDE.md" "$WORK/t2-orig.md"
echo "--- original ---"
cat "$WORK/t2-orig.md"; echo ""
run_lib "$T2" install_claude_layer "$REPO" auto
echo "--- resulting \$HOME/.claude/CLAUDE.md ---"
cat "$T2/.claude/CLAUDE.md"
echo "--- assertions ---"
BAK2="$(latest_backup "$T2/.claude/backups")"
echo "backup: ${BAK2:-<none>}"
chk "backup was created"                   test -n "$BAK2"
chk "backup is byte-identical to original"  cmp -s "$WORK/t2-orig.md" "${BAK2:-/nonexistent}"
head -c "$(wc -c < "$WORK/t2-orig.md")" "$T2/.claude/CLAUDE.md" > "$WORK/t2-head.md"
chk "operator content survives verbatim as file prefix" cmp -s "$WORK/t2-orig.md" "$WORK/t2-head.md"
chk "block appended"                        grep -Fq "$BEGIN_RE" "$T2/.claude/CLAUDE.md"
echo ""

# ─────────────────────────────────────────────────────────────
echo "=== TEST 3: idempotency (second run must be byte-identical) ==="
cp "$T2/.claude/CLAUDE.md" "$WORK/t3-run1.md"
run_lib "$T2" install_claude_layer "$REPO" auto
echo "--- diff run1 vs run2 (global CLAUDE.md) ---"
diff "$WORK/t3-run1.md" "$T2/.claude/CLAUDE.md" && echo "(no diff)"
chk "global CLAUDE.md byte-identical after 2nd run" cmp -s "$WORK/t3-run1.md" "$T2/.claude/CLAUDE.md"
chk "no second backup created (block now managed)"  test "$(backup_count "$T2/.claude/backups")" = "1"
echo ""

# ─────────────────────────────────────────────────────────────
echo "=== TEST 4: memory is never clobbered ==="
SLUG2=$(printf '%s' "$T2" | tr '/' '-')
MEM="$T2/.claude/projects/$SLUG2/memory"
echo "OPERATOR EDIT — 6 months of accumulated knowledge" >> "$MEM/MEMORY.md"
echo "OPERATOR EDIT inside the seed file" >> "$MEM/reference_fresh_brain_databases.md"
cp "$MEM/MEMORY.md" "$WORK/t4-index-before.md"
cp "$MEM/reference_fresh_brain_databases.md" "$WORK/t4-seed-before.md"
echo "--- third run output (memory only) ---"
run_lib "$T2" seed_auto_memory
chk "MEMORY.md unchanged"                      cmp -s "$WORK/t4-index-before.md" "$MEM/MEMORY.md"
chk "seed file unchanged"                      cmp -s "$WORK/t4-seed-before.md" "$MEM/reference_fresh_brain_databases.md"
chk "operator edit still present in MEMORY.md" grep -Fq "OPERATOR EDIT" "$MEM/MEMORY.md"
echo ""

# ─────────────────────────────────────────────────────────────
echo "=== TEST 5: skill drift is repaired non-interactively, with a backup ==="
echo "OPERATOR HACKED THIS SKILL" >> "$T2/.claude/skills/brain/SKILL.md"
echo "--- run (must NOT prompt; stdin closed) ---"
run_lib "$T2" install_operator_skills "$REPO" auto
chk "skill restored to repo version" diff -q "$REPO/skills/brain/SKILL.md" "$T2/.claude/skills/brain/SKILL.md"
SBAK=$(ls -d "$T2/.claude/backups/skills"/brain.pre-fresh-brain-* 2>/dev/null | head -1)
echo "skill backup: ${SBAK:-<none>}"
chk "old skill backed up"        test -n "$SBAK"
chk "backup holds operator edit" grep -Fq "OPERATOR HACKED THIS SKILL" "${SBAK:-/nonexistent}/SKILL.md"
echo ""

# ─────────────────────────────────────────────────────────────
# Regression cases below: MALFORMED marker layouts. The original harness only
# exercised well-formed input, which is how the unterminated-block data loss
# shipped. Every one of these asserts (a) no operator line is lost, (b) a
# backup exists, (c) the file converges to a valid, idempotent state.
# ─────────────────────────────────────────────────────────────

# malformed_case <label> <home> <fixture-file>
#   Installs against a HOME whose ~/.claude/CLAUDE.md is the given fixture,
#   then runs the shared malformed-input assertions. The fixture is the
#   pre-run file, so it doubles as the expected backup content.
#   LAST_RUN_OUT is left pointing at the captured install output so a case can
#   assert on what the operator was told.
malformed_case() {
    local label="$1" h="$2" fixture="$3"
    local bak run1

    mkdir -p "$h/.claude"
    cp "$fixture" "$h/.claude/CLAUDE.md"
    LAST_RUN_OUT="$WORK/$(basename "$h")-install.out"
    echo "--- before ---"
    cat "$h/.claude/CLAUDE.md"
    echo "--- install run ---"
    run_lib "$h" install_global_claude_md > "$LAST_RUN_OUT" 2>&1
    cat "$LAST_RUN_OUT"
    echo "--- after ---"
    cat "$h/.claude/CLAUDE.md"
    echo "--- assertions ---"

    bak="$(latest_backup "$h/.claude/backups")"
    echo "backup: ${bak:-<none>}"
    chk "$label: backup was taken"                    test -n "$bak"
    chk "$label: backup is byte-identical to pre-run file" cmp -s "$fixture" "${bak:-/nonexistent}"

    # Every non-marker line of the fixture must still be present afterwards.
    local missing=0 line
    while IFS= read -r line; do
        case "$line" in
            "$BEGIN_RE"*|"$END_RE"*) continue ;;
        esac
        [ -n "$line" ] || continue
        grep -Fqx "$line" "$h/.claude/CLAUDE.md" || { missing=$((missing + 1)); echo "      LOST: $line"; }
    done < "$fixture"
    chk "$label: every operator line survived"        test "$missing" = "0"
    chk "$label: block is well-formed after repair"   well_formed "$h/.claude/CLAUDE.md"
    chk "$label: managed body present"                grep -Fq "Database routing" "$h/.claude/CLAUDE.md"

    # Converges: a second run changes nothing and takes no further backup.
    run1="$WORK/$(basename "$h")-run1.md"
    cp "$h/.claude/CLAUDE.md" "$run1"
    run_lib "$h" install_global_claude_md >/dev/null
    chk "$label: second run is byte-identical"        cmp -s "$run1" "$h/.claude/CLAUDE.md"
    chk "$label: second run took no extra backup"     test "$(backup_count "$h/.claude/backups")" = "1"
}

echo "=== TEST 6: UNTERMINATED block — BEGIN with no END (the data-loss bug) ==="
cat > "$WORK/fx-unterminated.md" <<'FX'
<!-- FRESH BRAIN: BEGIN (managed — edits inside this block are overwritten) -->
stale managed body
# MY IRREPLACEABLE RULES
line A
line B
FX
T6="$(new_home)"
malformed_case "unterminated" "$T6" "$WORK/fx-unterminated.md"
chk "unterminated: irreplaceable rules survived" grep -Fq "MY IRREPLACEABLE RULES" "$T6/.claude/CLAUDE.md"
chk "unterminated: operator told what happened"  grep -Fq "UNTERMINATED" "$LAST_RUN_OUT"
echo ""

echo "=== TEST 7: END marker with no BEGIN (mirror case) ==="
cat > "$WORK/fx-orphan-end.md" <<'FX'
# MY RULES
line A
<!-- FRESH BRAIN: END -->
line B
FX
T7="$(new_home)"
malformed_case "orphan-END" "$T7" "$WORK/fx-orphan-end.md"
echo ""

echo "=== TEST 8: two BEGIN markers with operator content between BEGIN#2 and END ==="
cat > "$WORK/fx-multi-begin.md" <<'FX'
# HEADER I WROTE
<!-- FRESH BRAIN: BEGIN (managed — edits inside this block are overwritten) -->
stale managed body
<!-- FRESH BRAIN: BEGIN (managed — edits inside this block are overwritten) -->
RULES TRAPPED BETWEEN BEGIN2 AND END
another trapped line
<!-- FRESH BRAIN: END -->
# FOOTER I WROTE
FX
T8="$(new_home)"
malformed_case "multi-BEGIN" "$T8" "$WORK/fx-multi-begin.md"
chk "multi-BEGIN: trapped operator lines survived" grep -Fq "RULES TRAPPED BETWEEN BEGIN2 AND END" "$T8/.claude/CLAUDE.md"
chk "multi-BEGIN: operator told what happened"     grep -Fq "MORE THAN ONE" "$LAST_RUN_OUT"
echo ""

echo "=== TEST 9: duplicated well-formed blocks (double paste) ==="
cat > "$WORK/fx-double-block.md" <<'FX'
<!-- FRESH BRAIN: BEGIN (managed — edits inside this block are overwritten) -->
stale managed body
<!-- FRESH BRAIN: END -->
# OPERATOR NOTES BETWEEN THE BLOCKS
<!-- FRESH BRAIN: BEGIN (managed — edits inside this block are overwritten) -->
stale managed body
<!-- FRESH BRAIN: END -->
FX
T9="$(new_home)"
malformed_case "double-block" "$T9" "$WORK/fx-double-block.md"
chk "double-block: exactly one BEGIN remains" test "$(count_lines "$BEGIN_RE" "$T9/.claude/CLAUDE.md")" = "1"
echo ""

echo "=== TEST 10: stale body in a well-formed block is backed up before rewrite ==="
T10="$(new_home)"
mkdir -p "$T10/.claude"
cat > "$T10/.claude/CLAUDE.md" <<'FX'
# MY RULES ABOVE THE BLOCK
<!-- FRESH BRAIN: BEGIN (managed — edits inside this block are overwritten) -->
OLD BODY FROM AN EARLIER VERSION
<!-- FRESH BRAIN: END -->
# MY RULES BELOW THE BLOCK
FX
cp "$T10/.claude/CLAUDE.md" "$WORK/t10-orig.md"
echo "--- install run ---"
run_lib "$T10" install_global_claude_md
echo "--- after ---"
cat "$T10/.claude/CLAUDE.md"
echo "--- assertions ---"
BAK10="$(latest_backup "$T10/.claude/backups")"
echo "backup: ${BAK10:-<none>}"
chk "stale-body: in-place rewrite took a backup"    test -n "$BAK10"
chk "stale-body: backup matches pre-run file"       cmp -s "$WORK/t10-orig.md" "${BAK10:-/nonexistent}"
chk "stale-body: old body replaced"                 test "$(count_lines 'OLD BODY FROM AN EARLIER VERSION' "$T10/.claude/CLAUDE.md")" = "0"
chk "stale-body: fresh body installed"              grep -Fq "Database routing" "$T10/.claude/CLAUDE.md"
chk "stale-body: content above block preserved"     grep -Fqx "# MY RULES ABOVE THE BLOCK" "$T10/.claude/CLAUDE.md"
chk "stale-body: content below block preserved"     grep -Fqx "# MY RULES BELOW THE BLOCK" "$T10/.claude/CLAUDE.md"
echo ""

# ─────────────────────────────────────────────────────────────
echo "=== SAFETY: the real \$HOME/.claude must be untouched ==="
echo "real HOME = $REAL_HOME"
if [ -f "$REAL_HOME/.claude/CLAUDE.md" ]; then
    REAL_SUM_NOW=$(shasum "$REAL_HOME/.claude/CLAUDE.md" | awk '{print $1}')
    echo "real ~/.claude/CLAUDE.md sha1 before: ${REAL_CLAUDE_MD_SUM_BEFORE:-<absent>}"
    echo "real ~/.claude/CLAUDE.md sha1 after:  $REAL_SUM_NOW"
    chk "real global CLAUDE.md unchanged during this run" \
        test "$REAL_SUM_NOW" = "$REAL_CLAUDE_MD_SUM_BEFORE"
else
    echo "(no real ~/.claude/CLAUDE.md on this machine)"
fi
echo "entries under real ~/.claude modified in the last 10 minutes:"
find "$REAL_HOME/.claude" -maxdepth 2 -newermt '-10 minutes' -not -path '*/projects/*' 2>/dev/null | head -20
echo "(Claude Code's own runtime dirs may appear; no CLAUDE.md / backups / skills entries should)"
echo ""

echo "===== Results: $PASS passed, $FAILN failed ====="
echo ""
[ "$FAILN" -gt 0 ] && exit 1
exit 0
