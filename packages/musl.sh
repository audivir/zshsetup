#!/usr/bin/env zsh
# shellcheck shell=bash
# shellcheck disable=SC1091
set -euo pipefail

. "$ZSHSETUP_HOME/packages/helper.sh"

# user-space musl for glibc hosts, from Alpine's package; musl programs need
# `patchelf --set-interpreter` to use it, see packages/kv.sh
name="musl"
brew=""
apt=""
install_dir="$XDG_DATA_HOME/musl"

# checks the currently installed version, echoes "" if not installed
check() {
  cat "$install_dir/version" 2>/dev/null || echo ""
}

# fetches the latest version
fetch() {
  "$ZSHSETUP_HOME/packages/musl/apk-extract" --version musl
}

# installs the most recent version
install() {
  if [ "$(__libc)" != "gnu" ]; then
    echo "$name is only for glibc hosts" >&2
    return 1
  fi
  local apk_dir
  apk_dir="$(mktemp -d)"
  trap 'rm -rf "$apk_dir"' EXIT INT TERM
  "$ZSHSETUP_HOME/packages/musl/apk-extract" "$apk_dir" musl
  rm -rf "$install_dir"
  mkdir -p "$install_dir"
  # the loader is also the libc
  cp "$apk_dir"/lib/ld-musl-*.so.1 "$install_dir/"
  rm -rf "$apk_dir"
  trap - EXIT INT TERM
  echo "$1" >"$install_dir/version"
}

# uninstalls the installed package
uninstall() {
  rm -rf "$install_dir"
}

main "$name" "$brew" "$apt" "$@"
