#!/usr/bin/env zsh
# shellcheck shell=bash
# shellcheck disable=SC1091
set -euo pipefail

. "$ZSHSETUP_HOME/packages/helper.sh"

name="uvc"
local_bin="$XDG_BIN_HOME/uvc"

# check the currently installed version, echo "" if not installed
check() {
  2>/dev/null sha256sum "$local_bin" | awk '{print $1}' || echo ""
}

# fetch the latest version
fetch() {
  local url
  url="https://github.com/audivir/uvc/raw/refs/heads/main/uvc"
  curl --fail-with-body -sL "$url" | sha256sum | awk '{print $1}'
}

# install the most recent version
install() {
  local url
  url="https://github.com/audivir/uvc/raw/refs/heads/main/uvc"
  tmpfile=$(mktemp)
  trap 'rm -f "$tmpfile"' EXIT INT TERM
  curl --fail-with-body -L "$url" -o "$tmpfile"
  chmod +x "$tmpfile"
  mv "$tmpfile" "$XDG_BIN_HOME/uvc"
  trap - EXIT INT TERM
}

# uninstall the installed package
uninstall() {
  rm "$local_bin"
}

main "$name" "$@"
