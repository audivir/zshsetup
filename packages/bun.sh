#!/usr/bin/env zsh
# shellcheck shell=bash
# shellcheck disable=SC1091
set -euo pipefail

. "$ZSHSETUP_HOME/packages/helper.sh"

name="bun"
brew="bun"
apt=""
local_bin="$XDG_BIN_HOME/bun"

# checks the currently installed version, echoes "" if not installed
check() {
  2>/dev/null "$local_bin" --version || echo ""
}

# fetches the latest version
fetch() {
  local version
  version=$(get_latest_github "oven-sh/bun")
  echo "${version#bun-v}"
}

# installs the most recent version
install() {
  require_cmd python3 || return 1
  local version url tmpdir
  version="$1"
  set_os_arch "linux" "x64" "linux" "aarch64" "darwin" "aarch64" "linux" "musl"
  url="https://github.com/oven-sh/bun/releases/download/bun-v$version/bun-$os-$arch.zip"
  tmpdir="$(mktemp -d)"
  trap 'rm -rf "$tmpdir"' EXIT INT TERM
  curl -fsSL "$url" -o "$tmpdir/bun.zip"
  python3 -m zipfile -e "$tmpdir/bun.zip" "$tmpdir"
  chmod +x "$tmpdir/bun-$os-$arch/bun"
  mv "$tmpdir/bun-$os-$arch/bun" "$local_bin"
  rm -rf "$tmpdir"
  trap - EXIT INT TERM
}

# uninstalls the installed package
uninstall() {
  rm "$local_bin"
}

main "$name" "$brew" "$apt" "$@"
