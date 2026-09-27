#!/usr/bin/env zsh
# shellcheck shell=bash
# shellcheck disable=SC1091
set -euo pipefail

. "$ZSHSETUP_HOME/packages/helper.sh"

name="go"
brew="go"
apt="golang"
local_bin="$XDG_DATA_HOME/golang/bin/go"

# checks the currently installed version, echoes "" if not installed
check() {
  2>/dev/null "$local_bin" version | awk '{print $3}' || echo ""
}

# fetches the latest version
fetch() {
  local url
  url="https://go.dev/VERSION?m=text"
  curl -fsSL "$url" | head -n 1
}

# installs the most recent version
install() {
  local version url
  version="$1"
  set_os_arch "linux" "amd64" "linux" "arm64" "darwin" "arm64"
  url="https://go.dev/dl/$version.$os-$arch.tar.gz"
  tmpdir="$(mktemp -d)"
  trap 'rm -rf "$tmpdir"' EXIT INT TERM
  curl -fsSL "$url" | tar -xzC "$tmpdir"
  mv "$tmpdir/go" "$XDG_DATA_HOME/golang"
  rm -rf "$tmpdir"
  trap - EXIT INT TERM
}

# uninstalls the installed package
uninstall() {
  rm -r "$XDG_DATA_HOME/golang"
}

main "$name" "$brew" "$apt" "$@"
