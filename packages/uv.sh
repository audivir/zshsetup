#!/usr/bin/env zsh
# shellcheck shell=bash
# shellcheck disable=SC1091
set -euo pipefail

. "$ZSHSETUP_HOME/packages/helper.sh"

name="uv"
brew="uv"
apt=""
local_bin="$XDG_BIN_HOME/uv"

# checks the currently installed version, echoes "" if not installed
check() {
  2>/dev/null "$local_bin" --version | awk '{print $2}' || echo ""
}

# fetches the latest version
fetch() {
  get_latest_github "astral-sh/uv"
}

# installs the most recent version
install() {
  if [ -n "${ZSHSETUP_BOOTSTRAP_UV_DIR:-}" ] && [ -f "$ZSHSETUP_BOOTSTRAP_UV_DIR/uv" ]; then
    mv "$ZSHSETUP_BOOTSTRAP_UV_DIR/uv" "$XDG_BIN_HOME/uv"
    mv "$ZSHSETUP_BOOTSTRAP_UV_DIR/uvx" "$XDG_BIN_HOME/uvx"
    return 0
  fi
  local version url tmpdir
  version="$1"
  set_os_arch "unknown-linux-gnu" "x86_64" "unknown-linux-gnu" "aarch64" "apple-darwin" "aarch64"
  url="https://github.com/astral-sh/uv/releases/download/$version/uv-$arch-$os.tar.gz"
  tmpdir="$(mktemp -d)"
  trap 'rm -rf "$tmpdir"' EXIT INT TERM
  curl_or_wget "$url" | tar -xzC "$tmpdir"
  chmod +x "$tmpdir/uv-$arch-$os/uv" "$tmpdir/uv-$arch-$os/uvx"
  mv "$tmpdir/uv-$arch-$os/uv" "$XDG_BIN_HOME/uv"
  mv "$tmpdir/uv-$arch-$os/uvx" "$XDG_BIN_HOME/uvx"
  rm -rf "$tmpdir"
  trap - EXIT INT TERM
}

# uninstalls the installed package
uninstall() {
  rm "$local_bin" "$XDG_BIN_HOME/uvx"
}

main "$name" "$brew" "$apt" "$@"
