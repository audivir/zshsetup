#!/usr/bin/env zsh
# shellcheck shell=bash
# shellcheck disable=SC1091
set -euo pipefail

. "$ZSHSETUP_HOME/packages/helper.sh"

name="..."
local_bin="..."

# check the currently installed version, echo "" if not installed
check() {
  2>/dev/null "$local_bin" --version | awk '{print $2}' || echo ""
}

# fetch the latest version
fetch() {
  : # ...
}

# install the most recent version
install() {
  : # ...
}

# uninstall the installed package
uninstall() {
  rm "$local_bin"
}

main "$name" "$@"
