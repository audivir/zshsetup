#!/usr/bin/env zsh
# shellcheck shell=bash
# shellcheck disable=SC1091
set -euo pipefail

. "$ZSHSETUP_HOME/packages/helper.sh"

name="jq"
local_bin="$XDG_BIN_HOME/jq"

# check the currently installed version, echo "" if not installed
check() {
    local version
    version=$(2>/dev/null "$local_bin" --version) || return 0
    echo "${version%-apple}"
}

# fetch the latest version
fetch() {
    local url jq_tmpdir
    if ! jq --help >/dev/null 2>&1; then
        set_os_arch "linux" "amd64" "linux" "arm64" "macos" "amd64" "macos" "arm64"
        url="https://github.com/jqlang/jq/releases/download/jq-1.8.0/jq-$os-$arch"
        jq_tmpdir=$(mktemp -d)
        trap 'rm -rf "$jq_tmpdir"' EXIT INT TERM
        curl --fail-with-body -L "$url" -o "$jq_tmpdir/jq"
        chmod +x "$jq_tmpdir/jq"
        export PATH="$jq_tmpdir:$PATH"
    fi
    get_latest_github jqlang/jq
    if [ -n "$jq_tmpdir" ]; then
        rm -rf "$jq_tmpdir"
        trap - EXIT INT TERM
    fi
}

# install the most recent version
install() {
    local version url
    version="$1"
    set_os_arch "linux" "amd64" "linux" "arm64" "macos" "amd64" "macos" "arm64"
    url="https://github.com/jqlang/jq/releases/download/$version/jq-$os-$arch"
    tmpfile=$(mktemp)
    trap 'rm -f "$tmpfile"' EXIT INT TERM
    curl --fail-with-body -L "$url" -o "$tmpfile"
    chmod +x "$tmpfile"
    mv "$tmpfile" "$XDG_BIN_HOME/jq"
    trap - EXIT INT TERM
}

# uninstall the installed package
uninstall() {
    rm "$local_bin"
}

main "$name" "$@"
