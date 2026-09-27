#!/bin/sh
# install, upgrade without changes, and uninstall of manual packages
. "${ZSHSETUP_TEST_REPO:-/zshsetup}/tests/lib.sh"
setup_zshsetup
export ZSHSETUP_CHOICE=manual

for p in bat micro uv git; do
  script="$ZSHSETUP_HOME/packages/$p.sh"
  check "$p installs" "$script" install
  out="$("$script" upgrade 2>&1)"
  check "$p upgrade keeps the current version" lacks "$out" "Upgrading"
  check "$p uninstalls" "$script" uninstall
  check "$p is gone" test ! -e "$XDG_BIN_HOME/$p"
done
check "git uninstall removes libexec/git-core" test ! -e "$HOME/.local/libexec/git-core"
out="$("$ZSHSETUP_HOME/packages/micro.sh" upgrade 2>&1)"
check "upgrading a package that is not installed manually is a no-op" contains "$out" "not installed manually"

finish
