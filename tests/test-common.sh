#!/bin/bash

set -eu

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/lib/common.sh"

failures=0

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

future_ms=$(( ($(date +%s) + 3600) * 1000 ))
past_ms=$(( ($(date +%s) - 3600) * 1000 ))

valid=$(printf '{"claudeAiOauth":{"accessToken":"secret","refreshToken":"refresh","expiresAt":%s,"subscriptionType":"pro"}}' "$future_ms")
expired=$(printf '{"claudeAiOauth":{"accessToken":"secret","refreshToken":"refresh","expiresAt":%s,"subscriptionType":"team"}}' "$past_ms")

assert_equal "valid|Claude Pro|secret" "$(parse_credentials "$valid")" "valid Pro credential"
assert_equal "expired|Claude Team|" "$(parse_credentials "$expired")" "expired Team credential"
assert_equal "invalid|Unknown|" "$(parse_credentials '{}')" "missing OAuth credential"
assert_equal "valid|custom|secret" "$(parse_credentials "$(printf '{"claudeAiOauth":{"accessToken":"secret","expiresAt":%s,"subscriptionType":"custom"}}' "$future_ms")")" "unknown plan value"

export CLAUDE_STATUS_NOW="2026-06-11T00:00:00+00:00"
assert_equal "61|1h 30m" "$(parse_usage '{"five_hour":{"utilization":61.9,"resets_at":"2026-06-11T01:30:00+00:00"}}')" "current resets_at field"
assert_equal "61|1h 30m" "$(parse_usage '{"five_hour":{"utilization":61.9,"reset_at":"2026-06-11T01:30:00+00:00"}}')" "legacy reset_at field"
assert_equal "20|available now" "$(parse_usage '{"five_hour":{"utilization":20,"resets_at":"2026-06-10T23:00:00+00:00"}}')" "past reset"
assert_equal "20|N/A" "$(parse_usage '{"five_hour":{"utilization":20}}')" "missing reset"
assert_equal "ERROR" "$(parse_usage 'not-json')" "invalid usage response"
unset CLAUDE_STATUS_NOW

security() {
  echo "security: The specified item could not be found in the keychain." >&2
  return 44
}

set +e
get_credentials "/tmp/missing-account" >/dev/null
missing_status=$?
set -e
assert_equal "1" "$missing_status" "missing Keychain credential"

security() {
  echo "security: User interaction is not allowed." >&2
  return 36
}

set +e
get_credentials "/tmp/unavailable-keychain" >/dev/null
keychain_error_status=$?
set -e
assert_equal "2" "$keychain_error_status" "Keychain access error"

if [ "$failures" -ne 0 ]; then
  exit 1
fi
