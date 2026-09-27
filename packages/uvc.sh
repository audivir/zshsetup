#!/usr/bin/env zsh
# shellcheck shell=bash
# shellcheck disable=SC1091
set -euo pipefail

. "$ZSHSETUP_HOME/packages/helper.sh"

name="uvc"
brew="uvc"
apt=""
local_bin="$XDG_BIN_HOME/uvc"

# checks the currently installed version, echoes "" if not installed
check() {
  2>/dev/null sha256 "$local_bin" || echo ""
}

# fetches the latest version
fetch() {
  require_cmd python3 || return 1
  local url
  url="https://github.com/audivir/uvc/raw/refs/heads/main/uvc"
  curl_or_wget "$url" | sha256
}

# installs the most recent version
install() {
  local url
  url="https://github.com/audivir/uvc/raw/refs/heads/main/uvc"
  tmpfile=$(mktemp)
  trap 'rm -f "$tmpfile"' EXIT INT TERM
  curl_or_wget "$url" "$tmpfile"
  chmod +x "$tmpfile"
  mv "$tmpfile" "$XDG_BIN_HOME/uvc"
  trap - EXIT INT TERM
}

# uninstalls the installed package
uninstall() {
  rm "$local_bin"
}

main "$name" "$brew" "$apt" "$@"
