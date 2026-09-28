#!/bin/sh
# install, upgrade without changes, and uninstall with pmg
. "${ZSHSETUP_TEST_REPO:-/zshsetup}/tests/lib.sh"
setup_zshsetup

for p in bat micro uv git; do
  check "$p installs" pmg install "$p"
  # e.g. git of the macOS developer tools is found instead, which pmg only records
  if pmg list | grep -q "^$p@external "; then
    echo "  info  $p is external"
    check "$p uninstalls" pmg uninstall "$p"
    continue
  fi
  out="$(pmg upgrade "$p" 2>&1)"
  check "$p upgrade keeps the current version" contains "$out" "is up to date"
  check "$p uninstalls" pmg uninstall "$p"
  check "$p is gone" test ! -e "$XDG_BIN_HOME/$p"
done
check "git uninstall removes its package dir" sh -c "! ls -d '$XDG_DATA_HOME'/git@* 2>/dev/null"
out="$(pmg upgrade micro 2>&1)"
check "upgrading a package that is not installed is a no-op" test -z "$out"

finish
