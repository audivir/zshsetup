#!/usr/bin/env zsh
# shellcheck shell=bash
# shellcheck disable=SC1091
set -euo pipefail

. "$ZSHSETUP_HOME/packages/helper.sh"

name="bat"
brew="bat"
apt="bat"
local_bin="$XDG_BIN_HOME/bat"

# checks the currently installed version, echoes "" if not installed
check() {
  2>/dev/null "$local_bin" --version | awk '{print "v"$2}' || echo ""
}

# fetches the latest version
fetch() {
  get_latest_github "sharkdp/bat"
}

# installs the most recent version
install() {
  local version url
  version="$1"
  set_os_arch "unknown-linux-gnu" "x86_64" "unknown-linux-gnu" "aarch64" "apple-darwin" "aarch64" "unknown-linux-musl"
  url="https://github.com/sharkdp/bat/releases/download/$version/bat-$version-$arch-$os.tar.gz"
  tmpdir="$(mktemp -d)"
  trap 'rm -rf "$tmpdir"' EXIT INT TERM
  curl -fsSL "$url" | tar -xzC "$tmpdir"
  chmod +x "$tmpdir/bat-$version-$arch-$os/bat"
  mv "$tmpdir/bat-$version-$arch-$os/bat" "$XDG_BIN_HOME/bat"
  rm -rf "$tmpdir"
  trap - EXIT INT TERM
}

# uninstalls the installed package
uninstall() {
  rm "$local_bin"
}

main "$name" "$brew" "$apt" "$@"
