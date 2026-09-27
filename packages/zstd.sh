#!/usr/bin/env zsh
# shellcheck shell=bash
# shellcheck disable=SC1091
set -euo pipefail

. "$ZSHSETUP_HOME/packages/helper.sh"

name="zstd"
brew="zstd"
apt="zstd"
local_bin="$XDG_BIN_HOME/zstd"

# checks the currently installed version, echoes "" if not installed
check() {
  2>/dev/null "$local_bin" --version | grep -o 'v[0-9.]*[0-9]' || echo ""
}

# fetches the latest version
fetch() {
  get_latest_github "facebook/zstd"
}

# installs the most recent version
# upstream only ships sources for Linux and macOS, so build them with zig
install() {
  require_cmd make zig || return 1
  local version url tmpdir cc
  version="$1"
  cc="$(zig_cc)"
  url="https://github.com/facebook/zstd/releases/download/$version/zstd-${version#v}.tar.gz"
  tmpdir="$(mktemp -d)"
  trap 'rm -rf "$tmpdir"' EXIT INT TERM
  curl_or_wget "$url" | tar -xzC "$tmpdir"
  make -C "$tmpdir/zstd-${version#v}/programs" -j4 zstd CC="$cc" AR="zig ar" \
    HAVE_ZLIB=0 HAVE_LZMA=0 HAVE_LZ4=0 >/dev/null
  mv "$tmpdir/zstd-${version#v}/programs/zstd" "$local_bin"
  rm -rf "$tmpdir"
  trap - EXIT INT TERM
}

# uninstalls the installed package
uninstall() {
  rm "$local_bin"
}

main "$name" "$brew" "$apt" "$@"
