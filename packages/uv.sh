#!/usr/bin/env zsh
# shellcheck shell=bash
# shellcheck disable=SC1091
set -euo pipefail

. "$ZSHSETUP_HOME/packages/helper.sh"

name="uv"
local_bin="$XDG_BIN_HOME/uv"

# check the currently installed version, echo "" if not installed
check() {
  2>/dev/null "$local_bin" --version | awk '{print $2}' || echo ""
}

# fetch the latest version
fetch() {
  get_latest_github "astral-sh/uv"
}

# install the most recent version
install() {
  local version url
  version="$1"
  set_os_arch "unknown-linux-gnu" "x86_64" "unknown-linux-gnu" "aarch64" "apple-darwin" "x86_64" "apple-darwin" "aarch64"
  url="https://github.com/astral-sh/uv/releases/download/$version/uv-$arch-$os.tar.gz"
  tmpdir="$(mktemp -d)"
  trap 'rm -rf "$tmpdir"' EXIT INT TERM
  curl --fail-with-body -L "$url" | tar -x -z -C "$tmpdir"
  chmod +x "$tmpdir/uv-$arch-$os/uv" "$tmpdir/uv-$arch-$os/uvx"
  mv "$tmpdir/uv-$arch-$os/uv" "$XDG_BIN_HOME/uv"
  mv "$tmpdir/uv-$arch-$os/uvx" "$XDG_BIN_HOME/uvx"
  rm -rf "$tmpdir"
  trap - EXIT INT TERM
}

# uninstall the installed package
uninstall() {
  rm "$local_bin" "$XDG_BIN_HOME/uvx"
}

main "$name" "$@"
