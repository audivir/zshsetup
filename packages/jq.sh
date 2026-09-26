#!/usr/bin/env zsh
# shellcheck shell=bash
# shellcheck disable=SC1091
set -euo pipefail

. "$ZSHSETUP_HOME/packages/helper.sh"

name="jq"
brew="jq"
apt="jq"
local_bin="$XDG_BIN_HOME/jq"

# checks the currently installed version, echoes "" if not installed
check() {
  local version
  version=$(2>/dev/null "$local_bin" --version) || return 0
  echo "${version%-apple}"
}

# fetches the latest version
fetch() {
  local url jq_tmpdir
  if ! command -v jq >/dev/null 2>&1; then
    jq_tmpdir=$(mktemp -d)
    trap 'rm -rf "$jq_tmpdir"' EXIT INT TERM
    local_bin="$jq_tmpdir/jq" install jq-1.8.0
    export PATH="$jq_tmpdir:$PATH"
  fi
  get_latest_github "jqlang/jq"
  if [ -n "$jq_tmpdir" ]; then
    rm -rf "$jq_tmpdir"
    trap - EXIT INT TERM
  fi
}

# installs the most recent version
install() {
  local version url
  version="$1"
  set_os_arch "linux" "amd64" "linux" "arm64" "macos" "arm64"
  url="https://github.com/jqlang/jq/releases/download/$version/jq-$os-$arch"
  tmpfile=$(mktemp)
  trap 'rm -f "$tmpfile"' EXIT INT TERM
  curl_or_wget "$url" "$tmpfile"
  chmod +x "$tmpfile"
  mv "$tmpfile" "$local_bin"
  trap - EXIT INT TERM
}

# uninstalls the installed package
uninstall() {
  rm "$local_bin"
}

main "$name" "$brew" "$apt" "$@"
