#!/usr/bin/env zsh
# shellcheck shell=bash
# shellcheck disable=SC1091
set -euo pipefail

. "$ZSHSETUP_HOME/packages/helper.sh"

name="curl"
brew=""
apt="curl"
local_bin="$XDG_BIN_HOME/curl"

# checks the currently installed version, echoes "" if not installed
check() {
  2>/dev/null "$local_bin" --version | awk '/Version/ {print $2}' || echo ""
}

# fetches the latest version
fetch() {
  get_latest_github "stunnel/static-curl"
}

# installs the most recent version
install() {
    local version url
    version="$1"
    set_os_arch "linux" "x86_64-glibc" "linux" "aarch64-glibc" "macos" "arm64"
    url="https://github.com/stunnel/static-curl/releases/download/$version/curl-$os-$arch-$version.tar.xz"
    tmpfile="$(mktemp)"
    trap 'rm -f "$tmpfile"' EXIT INT TERM
    curl_or_wget "$url" | tar -xJO "curl" >"$tmpfile"
    chmod +x "$tmpfile"
    mv "$tmpfile" "$local_bin"
    rm -f "$tmpfile"
    trap - EXIT INT TERM
}

# uninstalls the installed package
uninstall() {
  rm "$local_bin"
}

main "$name" "$brew" "$apt" "$@"
