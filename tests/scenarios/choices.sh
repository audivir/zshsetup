#!/bin/sh
# per-package choices with apt, the apt postinstall, the fallback to pmg, and the interactive menu
. "${ZSHSETUP_TEST_REPO:-/zshsetup}/tests/lib.sh"
has_apt || skip "choices need apt"
setup_zshsetup
export ZSHSETUP_CHOICE=manual
# shellcheck disable=SC2329
apt_installed() { dpkg -s "$1" 2>/dev/null | grep -q 'ok installed'; }
# __package_manager of .zshrc with the functions it calls
functions="$(zshrc_function __eprint)
$(install_functions)
$(zshrc_function __package_manager)"
# shellcheck disable=SC2329
apt_lists() { find /var/lib/apt/lists -maxdepth 1 -type f ! -name lock | head -n 1; }

# curl from apt brings its certificates, and nothing lands in ~/.local/bin
check "the image has no apt lists" test -z "$(apt_lists)"
check "curl installs with ZSHSETUP_CHOICE_CURL=apt" env ZSHSETUP_CHOICE_CURL=apt zsh -c "$functions
__package_manager curl && __clean_metadata"
check "curl comes from apt" apt_installed curl
check "ca-certificates come with curl from apt" apt_installed ca-certificates
check "no pmg curl in \$XDG_BIN_HOME" test ! -e "$XDG_BIN_HOME/curl"
check "the apt lists downloaded for curl are removed" test -z "$(apt_lists)"

# Debian and Ubuntu name bat batcat, the postinstall links it in zshsetup's bin
check "bat installs with ZSHSETUP_CHOICE_BAT=apt" env ZSHSETUP_CHOICE_BAT=apt zsh -c "$functions
__package_manager bat"
check "bat is linked in \$ZSHSETUP_HOME/bin" test -L "$ZSHSETUP_HOME/bin/bat"
check "bat runs" bat --version

# apt falls back to pmg for packages without an apt package
check "uv installs with ZSHSETUP_CHOICE=apt" env ZSHSETUP_CHOICE=apt zsh -c "$functions
__package_manager uv"
check "uv is installed by pmg" test -L "$XDG_BIN_HOME/uv"

# the interactive menu, answered through a terminal
if command -v script >/dev/null 2>&1; then
  printf '%s\n__package_manager micro\n' "$functions" >/tmp/menu.zsh
  out="$( (
    sleep 10
    printf '2\n'
  ) | ZSHSETUP_CHOICE='' script -qec "zsh /tmp/menu.zsh" /dev/null 2>&1 | tr -d '\r')"
  check "the menu lists apt and manual" contains "$out" "1) apt.*2) manual"
  check "answering 2 installs with pmg" test -L "$XDG_BIN_HOME/micro"
else
  echo "  skip  interactive menu (no script command)"
fi

finish
