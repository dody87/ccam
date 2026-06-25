#!/bin/bash

set -eu

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

failures=0

assert_contains() {
  local needle="$1"
  local haystack="$2"
  local description="$3"

  if [[ "$haystack" != *"$needle"* ]]; then
    printf 'FAIL: %s\n  missing: %s\n' "$description" "$needle"
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
    printf 'FAIL: %s\n  expected: %s\n  actual:   %s\n' \
      "$description" "$expected" "$actual"
    failures=$((failures + 1))
  else
    printf 'PASS: %s\n' "$description"
  fi
}

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

fake_home="$tmp_dir/home"
fake_bin="$tmp_dir/bin"
mkdir -p "$fake_home/.claude-work" "$fake_bin"

future_ms=$(( ($(date +%s) + 3600) * 1000 ))
past_ms=$(( ($(date +%s) - 3600) * 1000 ))
expired_creds=$(printf '{"claudeAiOauth":{"accessToken":"old","refreshToken":"refresh","expiresAt":%s,"subscriptionType":"team"}}' "$past_ms")
valid_creds=$(printf '{"claudeAiOauth":{"accessToken":"new-token","refreshToken":"refresh","expiresAt":%s,"subscriptionType":"team"}}' "$future_ms")

cat > "$fake_bin/security" <<'EOF'
#!/bin/bash
if [ -f "$CLAUDE_REFRESH_MARKER" ]; then
  printf '%s' "$CLAUDE_VALID_CREDS"
else
  printf '%s' "$CLAUDE_EXPIRED_CREDS"
fi
EOF
chmod +x "$fake_bin/security"

cat > "$fake_bin/claude" <<'EOF'
#!/bin/bash
printf '%s\n' "$CLAUDE_CONFIG_DIR" > "$CLAUDE_REFRESH_LOG"
touch "$CLAUDE_REFRESH_MARKER"
exit 0
EOF
chmod +x "$fake_bin/claude"

cat > "$fake_bin/curl" <<'EOF'
#!/bin/bash
printf '{"five_hour":{"utilization":42,"resets_at":"2026-06-11T01:30:00+00:00"}}'
EOF
chmod +x "$fake_bin/curl"

export HOME="$fake_home"
export PATH="$fake_bin:$PATH"
export CLAUDE_EXPIRED_CREDS="$expired_creds"
export CLAUDE_VALID_CREDS="$valid_creds"
export CLAUDE_REFRESH_MARKER="$tmp_dir/refreshed"
export CLAUDE_REFRESH_LOG="$tmp_dir/refresh.log"
export CLAUDE_STATUS_NOW="2026-06-11T00:00:00+00:00"
export CLAUDE_STATUS_REFRESH_TIMEOUT=2

output=$("$ROOT/bin/claude-status")
assert_contains "42%" "$output" "expired account refreshes and shows usage percentage"
assert_contains "used" "$output" "expired account refreshes and shows usage label"
assert_contains "Plan:" "$output" "refreshed account keeps plan output"
assert_equal "$fake_home/.claude-work" "$(cat "$CLAUDE_REFRESH_LOG")" "status refresh uses account config dir"

rm -f "$CLAUDE_REFRESH_MARKER" "$CLAUDE_REFRESH_LOG"
export CLAUDE_STATUS_DISABLE_AUTO_REFRESH=1
disabled_output=$("$ROOT/bin/claude-status")
assert_contains "Session expired" "$disabled_output" "disabled auto-refresh shows expired session"

if [ -f "$CLAUDE_REFRESH_LOG" ]; then
  refresh_calls="$(cat "$CLAUDE_REFRESH_LOG")"
else
  refresh_calls=""
fi
assert_equal "" "$refresh_calls" "disabled auto-refresh does not run claude"

if [ "$failures" -ne 0 ]; then
  exit 1
fi
