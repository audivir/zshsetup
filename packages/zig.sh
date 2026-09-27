#!/usr/bin/env zsh
# shellcheck shell=bash
# shellcheck disable=SC1091
set -euo pipefail

. "$ZSHSETUP_HOME/packages/helper.sh"

name="zig"
brew="zig"
apt=""
local_bin="$XDG_BIN_HOME/zig"
install_dir="$XDG_DATA_HOME/zig"
index_url="https://ziglang.org/download/index.json"

# checks the currently installed version, echoes "" if not installed
check() {
  2>/dev/null "$local_bin" version || echo ""
}

# fetches the latest version
# jq may not be installed yet, and the index lists the newest release first
fetch() {
  curl_or_wget "$index_url" \
    | grep -o 'https://ziglang.org/download/[0-9.]*/' \
    | awk -F/ 'NR == 1 {print $5}'
}

# installs the most recent version
install() {
  require_cmd python3 || return 1
  local version url tmpdir
  version="$1"
  set_os_arch "linux" "x86_64" "linux" "aarch64" "macos" "aarch64"
  url="https://ziglang.org/download/$version/zig-$arch-$os-$version.tar.xz"
  tmpdir="$(mktemp -d)"
  trap 'rm -rf "$tmpdir"' EXIT INT TERM
  curl_or_wget "$url" "$tmpdir/zig.tar.xz"
  python3 -m tarfile --filter data -e "$tmpdir/zig.tar.xz" "$tmpdir"
  rm -rf "$install_dir"
  mv "$tmpdir/zig-$arch-$os-$version" "$install_dir"
  rm -rf "$tmpdir"
  trap - EXIT INT TERM
  # zig resolves its bundled lib directory through the symlink
  ln -sf "$install_dir/zig" "$local_bin"
}

# uninstalls the installed package
uninstall() {
  rm "$local_bin"
  rm -r "$install_dir"
}

main "$name" "$brew" "$apt" "$@"
