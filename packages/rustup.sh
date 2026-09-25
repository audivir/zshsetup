#!/usr/bin/env zsh
# shellcheck shell=bash
# shellcheck disable=SC1091
set -euo pipefail

. "$ZSHSETUP_HOME/packages/helper.sh"

name="rustup"
local_bin="$CARGO_HOME/bin/rustup"

# check the currently installed version, echo "" if not installed
check() {
  2>/dev/null "$local_bin" --version | awk '{print $2}' || echo ""
}

# fetch the latest version
fetch() {
  local url
  url="https://api.github.com/repos/rust-lang/rustup/tags"
  curl --fail-with-body -sL "$url" | jq -r '.[0].name'
}

# install the most recent version
install() {
  curl --fail-with-body -L "https://sh.rustup.rs" | sh -s -- \
    --default-toolchain "${ZSHSETUP_RUST_TOOLCHAIN:-stable}" \
    --no-update-default-toolchain \
    --no-modify-path -y
}

# upgrade rustup in place, since uninstall would also remove all toolchains
upgrade() {
  if [ -z "$(check)" ]; then
    echo "$name is not installed manually, update via package manager" >&2
    exit 0
  fi
  "$local_bin" self update
}

# uninstall the installed package, including all toolchains and cargo binaries
uninstall() {
  "$local_bin" self uninstall -y
}

main "$name" "$@"
