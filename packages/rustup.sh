#!/usr/bin/env zsh
# shellcheck shell=bash
# shellcheck disable=SC1091
set -euo pipefail

. "$ZSHSETUP_HOME/packages/helper.sh"

name="rustup"
brew="rustup"
apt="rustup"
local_bin="$CARGO_HOME/bin/rustup"
cc_dir="$XDG_DATA_HOME/rustup-cc"

# checks the currently installed version, echoes "" if not installed
check() {
  2>/dev/null "$local_bin" --version | awk '{print $2}' || echo ""
}

# fetches the latest version
fetch() {
  require_cmd jq || return 1
  github_api "repos/rust-lang/rustup/tags" | jq -r '.[0].name'
}

# Rust links with cc, which bare systems lack, so a zig wrapper serves as one;
# musl toolchains also need libgcc_s, see packages/musl-libs.sh
install_linux_support() {
  if [ "$(__libc)" = "musl" ] && [ ! -e /usr/lib/libgcc_s.so.1 ]; then
    require_cmd musl-libs || return 1
  fi
  __available_cmd cc && return 0
  require_cmd zig || return 1
  mkdir -p "$cc_dir/bin"
  # zig's linker rejects the cortex-a53 workaround flag rustc passes on aarch64
  # shellcheck disable=SC2016
  printf '%s\n' '#!/bin/sh' 'for a do' '  shift' '  case "$a" in' '    -Wl,--fix-cortex-a53-843419) ;;' \
    '    *) set -- "$@" "$a" ;;' '  esac' 'done' "exec $(zig_cc) \"\$@\"" >"$cc_dir/bin/cc"
  chmod +x "$cc_dir/bin/cc"
}

# installs the most recent version
install() {
  if [ "$(uname)" = "Linux" ]; then
    install_linux_support || return 1
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
  rm -rf "$cc_dir"
}

main "$name" "$brew" "$apt" "$@"
