#!/usr/bin/env zsh
# shellcheck shell=bash
# shellcheck disable=SC1091
set -euo pipefail

. "$ZSHSETUP_HOME/packages/helper.sh"

name="kv"
brew="kv"
apt=""
local_bin="$XDG_BIN_HOME/kv"

# checks the currently installed version, echoes "" if not installed
check() {
  2>/dev/null "$local_bin" --version | awk '{print $2}' || echo ""
}

# fetches the latest version
fetch() {
  local version
  version=$(get_latest_github "audivir/kv")
  echo "${version#v}"
}

# installs the most recent version
install() {
  local version url tmpfile
  version="$1"
  set_os_arch "unknown-linux-gnu" "x86_64" "unknown-linux-gnu" "aarch64" "apple-darwin" "aarch64"
  url="https://github.com/audivir/kv/releases/download/v$version/kv-$arch-$os"
  tmpfile="$(mktemp)"
  trap 'rm -f "$tmpfile"' EXIT INT TERM
  curl_or_wget "$url" "$tmpfile"
  chmod +x "$tmpfile"
  mv "$tmpfile" "$local_bin"
  trap - EXIT INT TERM
}

# uninstalls the installed package
uninstall() {
  rm "$local_bin"
}

main "$name" "$brew" "$apt" "$@"
