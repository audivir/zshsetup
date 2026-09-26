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
  2>/dev/null sha256sum "$local_bin" | awk '{print $1}' || echo ""
}

# fetches the latest version
fetch() {
  # TODO: where is sha256sum from?
  require_cmd sha256sum || return 1
  local url
  url="https://github.com/audivir/uvc/raw/refs/heads/main/uvc"
  curl_or_wget "$url" | sha256sum | awk '{print $1}'
}

# installs the most recent version
install() {
  local url
  url="https://github.com/audivir/uvc/raw/refs/heads/main/uvc"
  tmpfile=$(mktemp)
  trap 'rm -f "$tmpfile"' EXIT INT TERM
  curl_or_wget "$url" -o "$tmpfile"
  chmod +x "$tmpfile"
  mv "$tmpfile" "$XDG_BIN_HOME/uvc"
  trap - EXIT INT TERM
}

# uninstalls the installed package
uninstall() {
  rm "$local_bin"
}

main "$name" "$brew" "$apt" "$@"
