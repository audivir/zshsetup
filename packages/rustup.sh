#!/usr/bin/env zsh
# shellcheck shell=bash
# shellcheck disable=SC1091
set -euo pipefail

. "$ZSHSETUP_HOME/packages/helper.sh"

name="rustup"
brew="rustup"
apt="rustup"
local_bin="$CARGO_HOME/bin/rustup"
musl_dir="$XDG_DATA_HOME/rustup-musl"

# checks the currently installed version, echoes "" if not installed
check() {
  2>/dev/null "$local_bin" --version | awk '{print $2}' || echo ""
}

# fetches the latest version
fetch() {
  require_cmd jq || return 1
  github_api "repos/rust-lang/rustup/tags" | jq -r '.[0].name'
}

# musl toolchains need libgcc_s and a cc, which bare Alpine lacks: GCC's libgcc_s from Alpine, and zig as cc
install_musl_support() {
  require_cmd zig || return 1
  local target apk_dir
  target="$(uname -m)-linux-musl"
  mkdir -p "$musl_dir/lib" "$musl_dir/bin"
  apk_dir="$(mktemp -d)"
  "$ZSHSETUP_HOME/packages/musl/apk-extract" "$apk_dir" libgcc
  cp "$apk_dir/usr/lib/libgcc_s.so.1" "$musl_dir/lib/"
  rm -rf "$apk_dir"
  # zig's linker rejects the cortex-a53 workaround flag rustc passes on aarch64
  # shellcheck disable=SC2016
  printf '%s\n' '#!/bin/sh' 'for a do' '  shift' '  case "$a" in' '    -Wl,--fix-cortex-a53-843419) ;;' \
    '    *) set -- "$@" "$a" ;;' '  esac' 'done' "exec zig cc -target $target \"\$@\"" >"$musl_dir/bin/cc"
  chmod +x "$musl_dir/bin/cc"
}

# installs the most recent version
install() {
  if [ "$(__libc)" = "musl" ]; then
    install_musl_support || return 1
  fi
  curl -fsSL "https://sh.rustup.rs" | sh -s -- \
    --default-toolchain "${ZSHSETUP_RUST_TOOLCHAIN:-stable}" \
    --no-update-default-toolchain \
    --no-modify-path -y
}

# upgrades rustup in place, since uninstall would also remove all toolchains
upgrade() {
  if [ -z "$(check)" ]; then
    echo "$name is not installed manually, update via package manager" >&2
    exit 0
  fi
  "$local_bin" self update
}

# uninstalls the installed package, including all toolchains and cargo binaries
uninstall() {
  "$local_bin" self uninstall -y
  rm -rf "$musl_dir"
}

main "$name" "$brew" "$apt" "$@"
