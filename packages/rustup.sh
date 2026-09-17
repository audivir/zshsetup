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
        --default-toolchain "nightly-2026-01-28" \
        --no-update-default-toolchain \
        --no-modify-path -y
}

# uninstall the installed package
uninstall() {
    rm "$local_bin"
}

main "$name" "$@"
#!/usr/bin/env zsh
# shellcheck shell=bash
set -euo pipefail
