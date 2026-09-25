#!/usr/bin/env zsh
# shellcheck shell=bash
# shellcheck disable=SC1091
set -euo pipefail

. "$ZSHSETUP_HOME/packages/helper.sh"

name="zig"
local_bin="$XDG_BIN_HOME/zig"
install_dir="$XDG_DATA_HOME/zig"
index_url="https://ziglang.org/download/index.json"

# check the currently installed version, echo "" if not installed
check() {
    2>/dev/null "$local_bin" version || echo ""
}

# fetch the latest version
# jq may not be installed yet, and the index lists the newest release first
fetch() {
    curl --fail-with-body -sL "$index_url" \
        | grep -o 'https://ziglang.org/download/[0-9.]*/' \
        | head -n 1 \
        | awk -F/ '{print $5}'
}

# install the most recent version
install() {
    local version url tmpdir
    version="$1"
    set_os_arch "linux" "x86_64" "linux" "aarch64" "macos" "x86_64" "macos" "aarch64"
    url="https://ziglang.org/download/$version/zig-$arch-$os-$version.tar.xz"
    tmpdir="$(mktemp -d)"
    trap 'rm -rf "$tmpdir"' EXIT INT TERM
    curl --fail-with-body -L "$url" | tar -x -J -C "$tmpdir"
    mv "$tmpdir/zig-$arch-$os-$version" "$install_dir"
    rm -rf "$tmpdir"
    trap - EXIT INT TERM
    # zig resolves its bundled lib directory through the symlink
    ln -sf "$install_dir/zig" "$local_bin"
}

# uninstall the installed package
uninstall() {
    rm "$local_bin"
    rm -r "$install_dir"
}

main "$name" "$@"
