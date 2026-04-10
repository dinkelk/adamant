#!/bin/bash
# Focused regression tests for redo bash completion on virtual target prefixes.
# Run inside an activated adamant environment:
#   source env/activate && bash redo/test/persistent_cache/test_redo_completion_virtual_prefix.sh

set -e

PASS=0
FAIL=0

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

COMP_DIR="${ADAMANT_DIR}/src/components/command_router"
if [ ! -d "$COMP_DIR" ]; then
    echo "ERROR: command_router component directory not found"
    exit 1
fi

set +e
source "$ADAMANT_DIR/env/redo_completion.sh" 2>/dev/null
set -e

run_completion() {
    COMPREPLY=()
    rm -f ~/.cache/redo/what_cache_lastdir.txt
    set +e
    __redo_completion redo "$1" "" 2>/dev/null
    local status=$?
    set -e
    return $status
}

echo "=== Virtual Prefix Completion Tests ==="
echo ""

cd "$COMP_DIR"
redo what >/dev/null 2>&1

# Test 1: exact repro stays fast and returns no matches
echo "Test 1: build/src/component-y no-match stays fast"
start_ms=$(date +%s%3N)
run_completion "build/src/component-y"
end_ms=$(date +%s%3N)
elapsed=$((end_ms - start_ms))
if [ "$elapsed" -lt 500 ]; then
    pass "completion finished in ${elapsed}ms"
else
    fail "completion took ${elapsed}ms"
fi
if [ "${#COMPREPLY[@]}" -eq 0 ]; then
    pass "returned 0 matches"
else
    fail "returned ${#COMPREPLY[@]} matches"
fi

# Test 2: deeper virtual path no-match stays fast
echo ""
echo "Test 2: doc/build/pdf no-match stays fast"
start_ms=$(date +%s%3N)
run_completion "doc/build/pdf/command_router_nope"
end_ms=$(date +%s%3N)
elapsed=$((end_ms - start_ms))
if [ "$elapsed" -lt 500 ]; then
    pass "deep completion finished in ${elapsed}ms"
else
    fail "deep completion took ${elapsed}ms"
fi
if [ "${#COMPREPLY[@]}" -eq 0 ]; then
    pass "deep completion returned 0 matches"
else
    fail "deep completion returned ${#COMPREPLY[@]} matches"
fi

# Test 3: positive virtual prefix still completes
echo ""
echo "Test 3: build/src/component- positive prefix returns matches"
run_completion "build/src/component-"
if [ "${#COMPREPLY[@]}" -gt 0 ]; then
    pass "returned ${#COMPREPLY[@]} matches"
else
    fail "returned 0 matches"
fi
all_prefixed=true
for r in "${COMPREPLY[@]}"; do
    trimmed="${r%% }"
    if [[ "$trimmed" != build/src/component-* ]]; then
        all_prefixed=false
        fail "unexpected completion prefix: $trimmed"
        break
    fi
done
if [ "$all_prefixed" = true ]; then
    pass "all matches preserve virtual path prefix"
fi

# Test 4: deeper positive virtual prefix still completes
echo ""
echo "Test 4: doc/build/pdf positive prefix returns matches"
start_ms=$(date +%s%3N)
run_completion "doc/build/pdf/command_router_"
end_ms=$(date +%s%3N)
elapsed=$((end_ms - start_ms))
if [ "$elapsed" -lt 500 ]; then
    pass "deep positive completion finished in ${elapsed}ms"
else
    fail "deep positive completion took ${elapsed}ms"
fi
if [ "${#COMPREPLY[@]}" -gt 0 ]; then
    pass "deep positive returned ${#COMPREPLY[@]} matches"
else
    fail "deep positive returned 0 matches"
fi
deep_prefixed=true
for r in "${COMPREPLY[@]}"; do
    trimmed="${r%% }"
    if [[ "$trimmed" != doc/build/pdf/command_router_* ]]; then
        deep_prefixed=false
        fail "unexpected deep completion prefix: $trimmed"
        break
    fi
done
if [ "$deep_prefixed" = true ]; then
    pass "all deep matches preserve virtual path prefix"
fi

# Test 5: real filesystem dirs still appear alongside target prefixes
echo ""
echo "Test 5: real directories still complete at the project root"
PROJECT_DIR="$ADAMANT_DIR"
cd "$PROJECT_DIR"
redo what >/dev/null 2>&1
run_completion "do"
found_doc_dir=false
for r in "${COMPREPLY[@]}"; do
    trimmed="${r%% }"
    if [ "$trimmed" = "doc/" ]; then
        found_doc_dir=true
        break
    fi
done
if [ "$found_doc_dir" = true ]; then
    pass "real directory completion still includes doc/"
else
    fail "real directory completion missing doc/"
fi


echo ""
echo "================================"
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
    echo "SOME TESTS FAILED"
    exit 1
else
    echo "ALL TESTS PASSED"
fi
