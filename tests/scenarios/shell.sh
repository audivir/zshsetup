#!/bin/sh
# full installation through .zshrc from the working tree: preinit, REQUIRE/DISABLE, failed installs, update
. "${ZSHSETUP_TEST_REPO:-/zshsetup}/tests/lib.sh"
setup_env
# git (for oh-my-zsh) verifies with the system's certificates, unlike the bootstrapped curl
install_ca_certificates
export ZSHSETUP_CHOICE=manual

# a git repo of the working tree to install from, with micro failing on purpose
src="$(mktemp -d)/zshsetup"
copy_tree "$src"
check "git installs for cloning" env ZSHSETUP_HOME="$src" "$src/packages/git.sh" install
awk '{ print } /^install\(\) \{$/ { print "  return 1" }' "$src/packages/micro.sh" >"$src/packages/micro.sh.new"
mv "$src/packages/micro.sh.new" "$src/packages/micro.sh"
chmod +x "$src/packages/micro.sh"
git -C "$src" init -q
git -C "$src" add -A
git -C "$src" -c user.name=test -c user.email=test@test commit -q -m test

# rustup, go, micromamba, gawk, and bun are slow to install and covered elsewhere
export ZSHSETUP_REPO="$src" ZSHSETUP_REQUIRE_PYTHON3=1 ZSHSETUP_DISABLE_JQ=1 ZSHSETUP_DISABLE_BUN=1 \
  ZSHSETUP_DISABLE_RUSTUP=1 ZSHSETUP_DISABLE_GO=1 ZSHSETUP_DISABLE_MICROMAMBA=1 ZSHSETUP_DISABLE_GAWK=1
unset ZSHSETUP_HOME
home="$HOME/.config/zshsetup"
check "zsh .zshrc install succeeds" zsh "$src/.zshrc" install
cp /tmp/check.log /tmp/install-zshrc.log

check "\$HOME/.zshrc links to the installed .zshrc" test "$(readlink "$HOME/.zshrc")" = "$home/.zshrc"
for setting in "ZSHSETUP_CHOICE=manual" "ZSHSETUP_REQUIRE_PYTHON3=1" "ZSHSETUP_DISABLE_BUN=1"; do
  check "preinit.zsh saves $setting" grep -qx "export $setting" "$home/preinit.zsh"
done
check "ZSHSETUP_REQUIRE_PYTHON3 installs python3" test -e "$XDG_BIN_HOME/python3"
check "ZSHSETUP_DISABLE_BUN skips bun" test ! -e "$XDG_DATA_HOME/bun/bin/bun"
check "ZSHSETUP_DISABLE_JQ still installs jq as a dependency" test -x "$XDG_BIN_HOME/jq"
check "a failed install leaves a marker" test -e "$home/failed/micro"
check "a failed install warns" grep -q "installing micro failed" /tmp/install-zshrc.log

# a new shell reads preinit.zsh, skips the failed package, and sets up the tools
clean_env="HOME=$HOME USER=$USER PATH=/usr/bin:/bin:$XDG_BIN_HOME TERM=dumb ZSHSETUP_GH_TOKEN=${ZSHSETUP_GH_TOKEN:-}"
# shellcheck disable=SC2016,SC2086
out="$(env -i $clean_env zsh -i -c 'echo "path1=$path[1]"; whence -w uvc' 2>&1)"
check "the next shell does not retry the failed install" lacks "$out" "Install micro via"
check "zshsetup's bin comes first on PATH" contains "$out" "path1=$home/bin"
check "uvc's shell function is loaded" contains "$out" "uvc: function"
check "the next shell does not reinstall disabled bun" lacks "$out" "Install bun via"

# shellcheck disable=SC2086
check "zsh ~/.zshrc update succeeds" env -i $clean_env zsh "$HOME/.zshrc" update
check "update removes the failed markers" test ! -e "$home/failed"

finish
