#!/bin/sh
# per-package choices with apt, the apt postinstall, python3 by choice, and the interactive menu
. "${ZSHSETUP_TEST_REPO:-/zshsetup}/tests/lib.sh"
has_apt || skip "choices need apt"
setup_zshsetup
export ZSHSETUP_CHOICE=manual
# shellcheck disable=SC2329
apt_installed() { dpkg -s "$1" 2>/dev/null | grep -q 'ok installed'; }

# curl from apt brings its certificates, and nothing lands in ~/.local/bin
check "jq installs with ZSHSETUP_CHOICE_CURL=apt" env ZSHSETUP_CHOICE_CURL=apt "$ZSHSETUP_HOME/packages/jq.sh" install
check "curl comes from apt" apt_installed curl
check "ca-certificates come with curl from apt" apt_installed ca-certificates
check "no manual curl in \$XDG_BIN_HOME" test ! -e "$XDG_BIN_HOME/curl"
check "jq runs" jq --version

# Debian and Ubuntu name bat batcat, the postinstall links it in zshsetup's bin
check "bat installs with ZSHSETUP_CHOICE_BAT=apt" env ZSHSETUP_CHOICE_BAT=apt "$ZSHSETUP_HOME/packages/bat.sh" package
check "bat is linked in \$ZSHSETUP_HOME/bin" test -L "$ZSHSETUP_HOME/bin/bat"
check "bat runs" bat --version

# python3 is installed by its own choice when a package needs it
check "uvc installs with ZSHSETUP_CHOICE_PYTHON3=apt" env ZSHSETUP_CHOICE_PYTHON3=apt "$ZSHSETUP_HOME/packages/uvc.sh" package
check "python3 comes from apt" apt_installed python3

# apt falls back to manual for packages without an apt package
check "uv installs with ZSHSETUP_CHOICE=apt" env ZSHSETUP_CHOICE=apt "$ZSHSETUP_HOME/packages/uv.sh" package
check "uv is a manual install" test -x "$XDG_BIN_HOME/uv"

# the interactive menu, answered through a terminal
if command -v script >/dev/null 2>&1; then
  out="$( (
    sleep 2
    printf '2\n'
  ) | ZSHSETUP_CHOICE='' script -qec "$ZSHSETUP_HOME/packages/micro.sh package" /dev/null 2>&1 | tr -d '\r')"
  check "the menu lists apt and manual" contains "$out" "1) apt.*2) manual"
  check "answering 2 installs manually" test -x "$XDG_BIN_HOME/micro"
else
  echo "  skip  interactive menu (no script command)"
fi

finish
