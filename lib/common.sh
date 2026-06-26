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

# ─── Refresh expired OAuth session ───────────────────────────────────────────
refresh_expired_session() {
  local config_dir="$1"

  if [ "${CLAUDE_STATUS_DISABLE_AUTO_REFRESH:-}" = "1" ]; then
    return 1
  fi

  python3 -c "
import os, shutil, subprocess, sys

config_dir = sys.argv[1]
timeout = int(os.environ.get('CLAUDE_STATUS_REFRESH_TIMEOUT', '20') or '20')
claude = os.environ.get('CLAUDE_STATUS_CLAUDE_CMD') or shutil.which('claude')

if not claude:
    sys.exit(1)

env = os.environ.copy()
env['CLAUDE_CONFIG_DIR'] = config_dir

try:
    result = subprocess.run(
        [
            claude,
            '-p',
            'Respond only: ok',
            '--no-session-persistence',
            '--max-budget-usd',
            '0.01',
            '--output-format',
            'json',
        ],
        cwd=os.path.expanduser('~'),
        env=env,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        timeout=timeout,
        check=False,
    )
except Exception:
    sys.exit(1)

sys.exit(0 if result.returncode == 0 else 1)
" "$config_dir" 2>/dev/null
}

# ─── Parse usage response ─────────────────────────────────────────────────────
# Output: "pct|reset_in|weekly_pct|weekly_reset_in"
parse_usage() {
  local json="$1"
  [ -z "$json" ] && { echo "ERROR"; return; }

  python3 -c "
import sys, json
from datetime import datetime, timezone

def format_reset(reset_at, now):
    if not reset_at:
        return 'N/A'

    dt = datetime.fromisoformat(reset_at.replace('Z', '+00:00'))
    diff = dt - now
    mins = int(diff.total_seconds() / 60)

    if mins >= 1440:
        days = mins // 1440
        hours = (mins % 1440) // 60
        return f'{days}d {hours}h'
    if mins >= 60:
        return f'{mins // 60}h {mins % 60}m'
    if mins > 0:
        return f'{mins}m'
    return 'available now'

try:
    d = json.loads(sys.argv[1])
    now_value = sys.argv[2]
    now = (
        datetime.fromisoformat(now_value.replace('Z', '+00:00'))
        if now_value
        else datetime.now(timezone.utc)
    )

    fh  = d.get('five_hour', {})
    pct = int(fh.get('utilization', 0))
    reset_at = fh.get('resets_at') or fh.get('reset_at', '')
    reset_str = format_reset(reset_at, now)

    weekly = {}
    for key in ('weekly', 'week', 'seven_day', 'seven_days'):
        value = d.get(key)
        if isinstance(value, dict):
            weekly = value
            break

    weekly_pct = ''
    weekly_reset = ''
    if weekly and weekly.get('utilization') is not None:
        weekly_pct = str(int(weekly.get('utilization', 0)))
        weekly_reset_at = weekly.get('resets_at') or weekly.get('reset_at', '')
        weekly_reset = format_reset(weekly_reset_at, now) if weekly_reset_at else ''

    print(f'{pct}|{reset_str}|{weekly_pct}|{weekly_reset}')
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
