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
  2>/dev/null "$local_bin" --version | awk 'NR == 1 {print $2}' || echo ""
}

# fetches the latest version
fetch() {
  if [ -z "$(check)" ]; then
    echo "8.22.0"
  else
    get_latest_github "stunnel/static-curl"
  fi
}

# installs the most recent version
install() {
  require_cmd python3 || return 1
  local version url tmpdir
  version="${1:-8.22.0}"
  set_os_arch "linux" "x86_64-glibc" "linux" "aarch64-glibc" "macos" "arm64" "linux" "musl"
  url="https://github.com/stunnel/static-curl/releases/download/$version/curl-$os-$arch-$version.tar.xz"
  tmpdir="$(mktemp -d)"
  trap 'rm -rf "$tmpdir"' EXIT INT TERM
  curl_or_wget "$url" "$tmpdir/curl.tar.xz"
  python3 -m tarfile --filter data -e "$tmpdir/curl.tar.xz" "$tmpdir"
  chmod +x "$tmpdir/curl"
  mv "$tmpdir/curl" "$local_bin"
  rm -rf "$tmpdir"
  trap - EXIT INT TERM
}

# uninstalls the installed package
uninstall() {
  rm "$local_bin"
}

main "$name" "$brew" "$apt" "$@"
