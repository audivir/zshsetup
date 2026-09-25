#!/usr/bin/env zsh
# shellcheck shell=bash
# shellcheck disable=SC1091
set -euo pipefail

. "$ZSHSETUP_HOME/packages/helper.sh"

name="make"
local_bin="$XDG_BIN_HOME/make"

# check the currently installed version, echo "" if not installed
check() {
    2>/dev/null "$local_bin" --version | awk 'NR == 1 {print $3}' || echo ""
}

# fetch the latest version
fetch() {
    curl --fail-with-body -sL "https://ftp.gnu.org/gnu/make/" \
        | grep -o 'make-[0-9.]*\.tar\.gz"' \
        | sed 's/^make-//; s/\.tar\.gz"$//' \
        | sort -t. -k1,1n -k2,2n -k3,3n \
        | tail -n 1
}

# install the most recent version
# build.sh bootstraps make without an existing make, using the system compiler or zig
install() {
    local version url tmpdir cc
    version="$1"
    if 2>/dev/null >/dev/null cc --version; then
        cc="cc"
    elif 2>/dev/null >/dev/null zig version; then
        cc="zig cc"
    else
        echo "cc or zig is required to build $name" >&2
        return 1
    fi
    url="https://ftp.gnu.org/gnu/make/make-$version.tar.gz"
    tmpdir="$(mktemp -d)"
    trap 'rm -rf "$tmpdir"' EXIT INT TERM
    curl --fail-with-body -L "$url" | tar -x -z -C "$tmpdir"
    (
        cd "$tmpdir/make-$version"
        CC="$cc" ./configure --disable-nls --without-guile >/dev/null
        sh build.sh >/dev/null
    )
    mv "$tmpdir/make-$version/make" "$local_bin"
    rm -rf "$tmpdir"
    trap - EXIT INT TERM
}

# uninstall the installed package
uninstall() {
    rm "$local_bin"
}

main "$name" "$@"
