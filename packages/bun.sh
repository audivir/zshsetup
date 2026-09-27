#!/usr/bin/env zsh
# shellcheck shell=bash
# shellcheck disable=SC1091
set -euo pipefail

. "$ZSHSETUP_HOME/packages/helper.sh"

name="bun"
brew="bun"
apt=""
local_bin="$XDG_BIN_HOME/bun"
musl_lib="$XDG_DATA_HOME/bun-musl/lib"

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

# supplies libstdc++ and libgcc from Alpine's packages if the system lacks them
install_musl_libs() {
  local exe apk_dir
  exe="$1"
  [ -e /usr/lib/libstdc++.so.6 ] && return 0
  require_cmd patchelf || return 1
  apk_dir="$(mktemp -d)"
  "$ZSHSETUP_HOME/packages/musl/apk-extract" "$apk_dir" libstdc++ libgcc
  rm -rf "$musl_lib"
  mkdir -p "$musl_lib"
  cp -P "$apk_dir"/usr/lib/libstdc++.so.6* "$apk_dir/usr/lib/libgcc_s.so.1" "$musl_lib/"
  rm -rf "$apk_dir"
  # musl looks up a library's dependencies in its own RUNPATH
  # shellcheck disable=SC2016
  patchelf --set-rpath '$ORIGIN' "$(readlink -f "$musl_lib/libstdc++.so.6")"
  patchelf --set-rpath "$musl_lib" "$exe"
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
  if [ "$(__libc)" = "musl" ]; then
    install_musl_libs "$tmpdir/bun-$os-$arch/bun"
  fi
  mv "$tmpdir/bun-$os-$arch/bun" "$local_bin"
  rm -rf "$tmpdir"
  trap - EXIT INT TERM
}

# uninstalls the installed package
uninstall() {
  rm "$local_bin"
  rm -rf "${musl_lib%/*}"
}

main "$name" "$brew" "$apt" "$@"
