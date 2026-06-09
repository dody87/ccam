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

# ─── macOS Keychain token ─────────────────────────────────────────────────────
# Uses the same key derivation as Claude Code:
# sha256(config_dir)[:8] → keychain service name.
get_token() {
  local config_dir="$1"

  local hash
  hash=$(python3 -c "
import hashlib, sys
print(hashlib.sha256(sys.argv[1].encode()).hexdigest()[:8])
" "$config_dir" 2>/dev/null)

  [ -z "$hash" ] && { echo ""; return; }

  local svc="Claude Code-credentials-${hash}"
  local creds
  creds=$(security find-generic-password -s "$svc" -w 2>/dev/null) || { echo ""; return; }

  python3 -c "
import sys, json, time
try:
    d = json.load(sys.stdin)
    oauth = d.get('claudeAiOauth', {})
    expires = oauth.get('expiresAt', 0)
    token = oauth.get('accessToken', '')
    if token and int(time.time() * 1000) < expires:
        print(token)
except:
    pass
" <<< "$creds" 2>/dev/null
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
# Output: "pct|plan|active|reset_in"
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
    reset_at = fh.get('reset_at', '')
    plan = d.get('plan', {}).get('name', 'unknown')
    active = d.get('active_session', False)

    if reset_at:
        dt = datetime.fromisoformat(reset_at.replace('Z', '+00:00'))
        diff = dt - datetime.now(timezone.utc)
        mins = int(diff.total_seconds() / 60)
        if mins > 60:
            reset_str = f'{mins // 60}h {mins % 60}m'
        elif mins > 0:
            reset_str = f'{mins}m'
        else:
            reset_str = 'available now'
    else:
        reset_str = 'N/A'

    print(f'{pct}|{plan}|{active}|{reset_str}')
except:
    print('ERROR')
" "$json" 2>/dev/null
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
