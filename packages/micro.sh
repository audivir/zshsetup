#!/usr/bin/env zsh
# shellcheck shell=bash
# shellcheck disable=SC1091
set -euo pipefail

. "$ZSHSETUP_HOME/packages/helper.sh"

name="micro"
brew="micro"
apt="micro"
local_bin="$XDG_BIN_HOME/micro"

# checks the currently installed version, echoes "" if not installed
check() {
  2>/dev/null "$local_bin" --version | grep "Version" | awk '{print $2}' || echo ""
}

# fetches the latest version
fetch() {
  local version
  version=$(get_latest_github "micro-editor/micro")
  echo "${version#v}"
}

# installs the most recent version
install() {
  require_cmd tar || return 1
  local version url
  version="$1"
  set_os_arch "linux" "64" "linux" "-arm64" "macos" "-arm64"
  url="https://github.com/micro-editor/micro/releases/download/v$version/micro-$version-$os$arch.tar.gz"
  tmpfile="$(mktemp)"
  trap 'rm -f "$tmpfile"' EXIT INT TERM
  curl_or_wget "$url" | tar -xzO "micro-$version/micro" >"$tmpfile"
  chmod +x "$tmpfile"
  mv "$tmpfile" "$XDG_BIN_HOME/micro"
  rm -f "$tmpfile"
  trap - EXIT INT TERM
}

# uninstalls the installed package
uninstall() {
  rm "$local_bin"
}

main "$name" "$brew" "$apt" "$@"
