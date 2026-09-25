#!/usr/bin/env zsh
# shellcheck shell=bash
# shellcheck disable=SC1091
set -euo pipefail

. "$ZSHSETUP_HOME/packages/helper.sh"

name="bat"
local_bin="$XDG_BIN_HOME/bat"

# check the currently installed version, echo "" if not installed
check() {
  2>/dev/null "$local_bin" --version | awk '{print "v"$2}' || echo ""
}

# fetch the latest version
fetch() {
  get_latest_github "sharkdp/bat"
}

# install the most recent version
install() {
  local version url
  version="$1"
  set_os_arch "unknown-linux-gnu" "x86_64" "unknown-linux-gnu" "aarch64" "apple-darwin" "x86_64" "apple-darwin" "aarch64"
  url="https://github.com/sharkdp/bat/releases/download/$version/bat-$version-$arch-$os.tar.gz"
  tmpdir="$(mktemp -d)"
  trap 'rm -rf "$tmpdir"' EXIT INT TERM
  curl --fail-with-body -L "$url" | tar -x -z -C "$tmpdir"
  chmod +x "$tmpdir/bat-$version-$arch-$os/bat"
  mv "$tmpdir/bat-$version-$arch-$os/bat" "$XDG_BIN_HOME/bat"
  rm -rf "$tmpdir"
  trap - EXIT INT TERM
}

# uninstall the installed package
uninstall() {
  rm "$local_bin"
}

main "$name" "$@"
