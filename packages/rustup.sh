#!/usr/bin/env zsh
# shellcheck shell=bash
# shellcheck disable=SC1091
set -euo pipefail

. "$ZSHSETUP_HOME/packages/helper.sh"

name="rustup"
brew="rustup"
apt="rustup"
local_bin="$CARGO_HOME/bin/rustup"

# checks the currently installed version, echoes "" if not installed
check() {
  2>/dev/null "$local_bin" --version | awk '{print $2}' || echo ""
}

# fetches the latest version
fetch() {
  require_cmd jq || return 1
  local url
  url="https://api.github.com/repos/rust-lang/rustup/tags"
  curl_or_wget "$url" | jq -r '.[0].name'
}

# installs the most recent version
install() {
  curl_or_wget "https://sh.rustup.rs" | sh -s -- \
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
}

main "$name" "$brew" "$apt" "$@"
