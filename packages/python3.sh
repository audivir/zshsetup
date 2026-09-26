#!/usr/bin/env zsh
# shellcheck shell=bash
# shellcheck disable=SC1091
set -euo pipefail

. "$ZSHSETUP_HOME/packages/helper.sh"

name="python3"
brew=""
apt=""
local_bin="$XDG_BIN_HOME/python3"

# checks the currently installed version, echoes "" if not installed
check() {
  2>/dev/null "$local_bin" --version | awk '{print $2}' || echo ""
}

# fetches the latest version
fetch() {
  require_cmd uv || return 1
  local version
  version=$(uv python list --all-versions | grep -E '^cpython-3\.12\.[0-9]+' | head -n 1 | awk '{print $1}' | sed -E 's/^cpython-([0-9.]+).*/\1/')
  echo "$version"
}

# installs the most recent version
install() {
  require_cmd uv || return 1
  local version py_bin
  version="${1:-3.12}"
  uv python install "$version"
  py_bin="$(uv python find "$version")"
  ln -sf "$py_bin" "$local_bin"
  ln -sf "$py_bin" "$XDG_BIN_HOME/python"
}

# uninstalls the installed package
uninstall() {
  rm -f "$local_bin" "$XDG_BIN_HOME/python"
}

main "$name" "$brew" "$apt" "$@"
