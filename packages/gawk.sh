#!/usr/bin/env zsh
# shellcheck shell=bash
# shellcheck disable=SC1091
set -euo pipefail

. "$ZSHSETUP_HOME/packages/helper.sh"

name="gawk"
local_bin="$XDG_BIN_HOME/gawk"

# check the currently installed version, echo "" if not installed
check() {
    2>/dev/null "$local_bin" --version | awk 'NR == 1 { sub(",", "", $3); print $3 }' || echo ""
}

# fetch the latest version
fetch() {
    curl --fail-with-body -sL "https://ftp.gnu.org/gnu/gawk/" \
        | grep -o 'gawk-[0-9.]*\.tar\.xz"' \
        | sed 's/^gawk-//; s/\.tar\.xz"$//' \
        | sort -t. -k1,1n -k2,2n -k3,3n \
        | tail -n 1
}

# install the most recent version
# GNU only ships sources, so build them with the system compiler or zig
install() {
    local version url tmpdir cc
    version="$1"
    if ! 2>/dev/null >/dev/null make --version; then
        echo "make is required to build $name" >&2
        return 1
    fi
    if 2>/dev/null >/dev/null cc --version; then
        cc="cc"
    elif 2>/dev/null >/dev/null zig version; then
        cc="zig cc"
    else
        echo "cc or zig is required to build $name" >&2
        return 1
    fi
    url="https://ftp.gnu.org/gnu/gawk/gawk-$version.tar.xz"
    tmpdir="$(mktemp -d)"
    trap 'rm -rf "$tmpdir"' EXIT INT TERM
    curl --fail-with-body -L "$url" | tar -x -J -C "$tmpdir"
    (
        cd "$tmpdir/gawk-$version"
        # zig cannot link the loadable extensions as macOS bundles
        CC="$cc" ./configure --disable-nls --disable-pma --disable-extensions \
            --without-readline --without-mpfr >/dev/null
        make -j4 >/dev/null
    )
    mv "$tmpdir/gawk-$version/gawk" "$local_bin"
    rm -rf "$tmpdir"
    trap - EXIT INT TERM
}

# uninstall the installed package
uninstall() {
    rm "$local_bin"
}

main "$name" "$@"
