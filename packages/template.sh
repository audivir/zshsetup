#!/usr/bin/env zsh
# shellcheck shell=bash
# shellcheck disable=SC1091
set -euo pipefail

. "$ZSHSETUP_HOME/packages/helper.sh"

name="..."
brew="..."
apt="..."
local_bin="..."

# checks the currently installed version, echoes "" if not installed
check() {
  2>/dev/null "$local_bin" --version | awk '{print $2}' || echo ""
}

# fetches the latest version
fetch() {
  : # ...
}

# installs the most recent version
install() {
  : # ...
}

# uninstalls the installed package
uninstall() {
  rm "$local_bin"
}

main "$name" "$brew" "$apt" "$@"
