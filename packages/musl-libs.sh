#!/usr/bin/env zsh
# shellcheck shell=bash
# shellcheck disable=SC1091
set -euo pipefail

. "$ZSHSETUP_HOME/packages/helper.sh"

# GCC's libstdc++ and libgcc_s for musl hosts without them (bun, Rust), from Alpine's packages
name="musl-libs"
brew=""
apt=""
install_dir="$XDG_DATA_HOME/musl-libs"

# checks the currently installed version, echoes "" if not installed
check() {
  cat "$install_dir/version" 2>/dev/null || echo ""
}

# fetches the latest version
fetch() {
  "$ZSHSETUP_HOME/packages/musl/apk-extract" --version libstdc++
}

# installs the most recent version
install() {
  if [ "$(__libc)" != "musl" ]; then
    echo "$name is only for musl hosts" >&2
    return 1
  fi
  require_cmd patchelf || return 1
  local apk_dir
  apk_dir="$(mktemp -d)"
  trap 'rm -rf "$apk_dir"' EXIT INT TERM
  "$ZSHSETUP_HOME/packages/musl/apk-extract" "$apk_dir" libstdc++ libgcc
  rm -rf "$install_dir"
  mkdir -p "$install_dir/lib"
  cp -P "$apk_dir"/usr/lib/libstdc++.so.6* "$apk_dir/usr/lib/libgcc_s.so.1" "$install_dir/lib/"
  rm -rf "$apk_dir"
  trap - EXIT INT TERM
  # musl looks up a library's dependencies in its own RUNPATH
  # shellcheck disable=SC2016
  patchelf --set-rpath '$ORIGIN' "$(readlink -f "$install_dir/lib/libstdc++.so.6")"
  echo "$1" >"$install_dir/version"
}

# uninstalls the installed package
uninstall() {
  rm -rf "$install_dir"
}

main "$name" "$brew" "$apt" "$@"
