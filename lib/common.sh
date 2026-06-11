#!/bin/bash
# lib/common.sh — shared helpers used by all commands

# ─── Colors ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

# ─── Discover accounts ────────────────────────────────────────────────────────
# Scans ~/.claude-* and returns "label:path" pairs, one per line.
# Excludes ~/.claude (Claude Code's default dir, no suffix).
get_accounts() {
  local dirs=()
  while IFS= read -r d; do
    dirs+=("$d")
  done < <(find "$HOME" -maxdepth 1 -type d -name '.claude-*' | sort)

  if [ ${#dirs[@]} -eq 0 ]; then
    return
  fi

  for dir in "${dirs[@]}"; do
    local label
    label="${dir##*/.claude-}"   # strip ~/.claude- prefix
    echo "${label}:${dir}"
  done
}

# ─── macOS Keychain credentials ───────────────────────────────────────────────
# Uses the same key derivation as Claude Code:
# sha256(config_dir)[:8] → keychain service name.
get_credentials() {
  local config_dir="$1"

  local hash
  hash=$(python3 -c "
import hashlib, sys
print(hashlib.sha256(sys.argv[1].encode()).hexdigest()[:8])
" "$config_dir" 2>/dev/null)

  [ -z "$hash" ] && return 2

  local svc="Claude Code-credentials-${hash}"
  local creds
  local error_file
  error_file=$(mktemp)

  if ! creds=$(security find-generic-password -s "$svc" -w 2>"$error_file"); then
    local error
    error=$(cat "$error_file")
    rm -f "$error_file"

    if [[ "$error" == *"could not be found in the keychain"* ]]; then
      return 1
    fi

    return 2
  fi

  rm -f "$error_file"
  printf '%s' "$creds"
}

# Output: "valid|expired|invalid|plan|access_token"
parse_credentials() {
  local credentials="$1"

  python3 -c "
import sys, json, time
try:
    d = json.loads(sys.argv[1])
    oauth = d.get('claudeAiOauth', {})
    token = oauth.get('accessToken', '')
    refresh_token = oauth.get('refreshToken', '')
    expires = int(oauth.get('expiresAt', 0) or 0)
    subscription = str(oauth.get('subscriptionType', '') or '')

    plan_names = {
        'pro': 'Claude Pro',
        'team': 'Claude Team',
        'max': 'Claude Max',
        'enterprise': 'Claude Enterprise',
    }
    plan = plan_names.get(subscription.lower(), subscription or 'Unknown')

    if token and int(time.time() * 1000) < expires:
        status = 'valid'
    elif refresh_token:
        status = 'expired'
        token = ''
    else:
        status = 'invalid'
        token = ''

    print(f'{status}|{plan}|{token}')
except:
    print('invalid|Unknown|')
" "$credentials" 2>/dev/null
}

# ─── Query usage API ──────────────────────────────────────────────────────────
fetch_usage() {
  local token="$1"
  [ -z "$token" ] && { echo ""; return; }

  curl -sf "https://api.anthropic.com/api/oauth/usage" \
    -H "Authorization: Bearer $token" \
    -H "anthropic-beta: oauth-2025-04-20" \
    -H "User-Agent: claude-code/2.0.32" 2>/dev/null
}

# ─── Parse usage response ─────────────────────────────────────────────────────
# Output: "pct|reset_in"
parse_usage() {
  local json="$1"
  [ -z "$json" ] && { echo "ERROR"; return; }

  python3 -c "
import sys, json
from datetime import datetime, timezone

try:
    d = json.loads(sys.argv[1])
    fh  = d.get('five_hour', {})
    pct = int(fh.get('utilization', 0))
    reset_at = fh.get('resets_at') or fh.get('reset_at', '')

    if reset_at:
        dt = datetime.fromisoformat(reset_at.replace('Z', '+00:00'))
        now_value = sys.argv[2]
        now = (
            datetime.fromisoformat(now_value.replace('Z', '+00:00'))
            if now_value
            else datetime.now(timezone.utc)
        )
        diff = dt - now
        mins = int(diff.total_seconds() / 60)
        if mins >= 60:
            reset_str = f'{mins // 60}h {mins % 60}m'
        elif mins > 0:
            reset_str = f'{mins}m'
        else:
            reset_str = 'available now'
    else:
        reset_str = 'N/A'

    print(f'{pct}|{reset_str}')
except:
    print('ERROR')
" "$json" "${CLAUDE_STATUS_NOW:-}" 2>/dev/null
}

# ─── Progress bar ─────────────────────────────────────────────────────────────
render_bar() {
  local pct="$1"
  local width="${2:-20}"
  local filled=$(( pct * width / 100 ))
  local empty=$(( width - filled ))
  local bar=""
  for ((i=0; i<filled; i++)); do bar+="█"; done
  for ((i=0; i<empty; i++)); do bar+="░"; done
  echo "$bar"
}

# ─── Color by percentage ──────────────────────────────────────────────────────
color_for_pct() {
  local pct="$1"
  if   [ "$pct" -ge 90 ]; then echo "$RED"
  elif [ "$pct" -ge 70 ]; then echo "$YELLOW"
  else                         echo "$GREEN"
  fi
}

# ─── Active account (symlink ~/.claude → config dir) ─────────────────────────
get_active_dir() {
  local target
  target=$(readlink "$HOME/.claude" 2>/dev/null)
  echo "$target"
}

is_active() {
  local config_dir="$1"
  local active_dir
  active_dir=$(get_active_dir)
  [ "$config_dir" = "$active_dir" ]
}
