#!/bin/bash

set -eu

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

failures=0

assert_contains() {
  local output="$1"
  local expected="$2"
  local description="$3"

  if [[ "$output" != *"$expected"* ]]; then
    printf 'FAIL: %s\n  missing: %s\n' "$description" "$expected"
    failures=$((failures + 1))
  else
    printf 'PASS: %s\n' "$description"
  fi
}

assert_equal() {
  local expected="$1"
  local actual="$2"
  local description="$3"

  if [ "$expected" != "$actual" ]; then
    printf 'FAIL: %s\n' "$description"
    failures=$((failures + 1))
  else
    printf 'PASS: %s\n' "$description"
  fi
}

mkdir -p "$TMP_DIR/home/.claude-test" "$TMP_DIR/bin"
cat > "$TMP_DIR/bin/security" << EOF
#!/bin/bash
touch "$TMP_DIR/security-called"
exit 1
EOF
chmod +x "$TMP_DIR/bin/security"

switch_long=$(HOME="$TMP_DIR/home" "$ROOT/bin/claude-switch" --help)
switch_short=$(HOME="$TMP_DIR/home" "$ROOT/bin/claude-switch" -h)

assert_equal "$switch_long" "$switch_short" "claude-switch help aliases match"
assert_contains "$switch_long" "Usage:" "claude-switch shows usage"
assert_contains "$switch_long" "--remove <name>" "claude-switch documents account removal"
assert_contains "$switch_long" "Permanently delete an inactive account" "claude-switch explains removal constraint"

status_long=$(HOME="$TMP_DIR/home" PATH="$TMP_DIR/bin:$PATH" "$ROOT/bin/claude-status" --help)
status_short=$(HOME="$TMP_DIR/home" PATH="$TMP_DIR/bin:$PATH" "$ROOT/bin/claude-status" -h)

assert_equal "$status_long" "$status_short" "claude-status help aliases match"
assert_contains "$status_long" "Usage:" "claude-status shows usage"
assert_contains "$status_long" "Show usage for all detected Claude Code accounts" "claude-status describes the command"

if [ -e "$TMP_DIR/security-called" ]; then
  printf 'FAIL: claude-status help accessed the Keychain\n'
  failures=$((failures + 1))
else
  printf 'PASS: claude-status help skips the Keychain\n'
fi

if [ "$failures" -ne 0 ]; then
  exit 1
fi
