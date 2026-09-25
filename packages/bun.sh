#!/usr/bin/env zsh
# shellcheck shell=bash
# shellcheck disable=SC1091
set -euo pipefail

. "$ZSHSETUP_HOME/packages/helper.sh"

name="bun"
local_bin="$XDG_BIN_HOME/bun"

# check the currently installed version, echo "" if not installed
check() {
  2>/dev/null "$local_bin" --version || echo ""
}

# fetch the latest version
fetch() {
  local version
  version=$(get_latest_github "oven-sh/bun")
  echo "${version#bun-v}"
}

# install the most recent version
install() {
  local version url tmpdir
  version="$1"
  set_os_arch "linux" "x64" "linux" "aarch64" "darwin" "x64" "darwin" "aarch64"
  url="https://github.com/oven-sh/bun/releases/download/bun-v$version/bun-$os-$arch.zip"
  tmpdir="$(mktemp -d)"
  trap 'rm -rf "$tmpdir"' EXIT INT TERM
  curl --fail-with-body -L "$url" -o "$tmpdir/bun.zip"
  unzip -q "$tmpdir/bun.zip" -d "$tmpdir"
  chmod +x "$tmpdir/bun-$os-$arch/bun"
  mv "$tmpdir/bun-$os-$arch/bun" "$local_bin"
  rm -rf "$tmpdir"
  trap - EXIT INT TERM
}

# uninstall the installed package
uninstall() {
  rm "$local_bin"
}

main "$name" "$@"
