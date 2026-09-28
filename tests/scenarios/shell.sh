#!/bin/sh
# full installation through .zshrc from the working tree: preinit, REQUIRE/DISABLE, failed installs, update
. "${ZSHSETUP_TEST_REPO:-/zshsetup}/tests/lib.sh"
setup_env
export ZSHSETUP_CHOICE=manual

# a git repo of the working tree to install from, with micro failing on purpose
src="$(mktemp -d)/zshsetup"
copy_tree "$src"
check "git installs for cloning" env ZSHSETUP_HOME="$src" sh "$src/packages/pmg" install git
# a release that does not exist
sed 's|^repo = "micro-editor/micro"$|repo = "micro-editor/micro-missing"|' "$src/packages/specs/micro.toml" \
  >"$src/packages/specs/micro.toml.new"
mv "$src/packages/specs/micro.toml.new" "$src/packages/specs/micro.toml"
git -C "$src" init -q
git -C "$src" add -A
git -C "$src" -c user.name=test -c user.email=test@test commit -q -m test

# rustup, go, micromamba, gawk, and bun are slow to install and covered elsewhere
export ZSHSETUP_REPO="$src" ZSHSETUP_REQUIRE_PATCHELF=1 ZSHSETUP_DISABLE_BUN=1 \
  ZSHSETUP_DISABLE_RUSTUP=1 ZSHSETUP_DISABLE_GO=1 ZSHSETUP_DISABLE_MICROMAMBA=1 ZSHSETUP_DISABLE_GAWK=1
unset ZSHSETUP_HOME
home="$HOME/.config/zshsetup"
check "zsh .zshrc install succeeds" zsh "$src/.zshrc" install
cp /tmp/check.log /tmp/install-zshrc.log

check "\$HOME/.zshrc links to the installed .zshrc" test "$(readlink "$HOME/.zshrc")" = "$home/.zshrc"
for setting in "ZSHSETUP_CHOICE=manual" "ZSHSETUP_REQUIRE_PATCHELF=1" "ZSHSETUP_DISABLE_BUN=1"; do
  check "preinit.zsh saves $setting" grep -qx "export $setting" "$home/preinit.zsh"
done
check "ZSHSETUP_REQUIRE_PATCHELF installs patchelf" test -e "$XDG_BIN_HOME/patchelf"
check "ZSHSETUP_DISABLE_BUN skips bun" test ! -e "$XDG_BIN_HOME/bun"
check "the pmg command is linked" test -L "$home/bin/pmg"
check "the completion of pmg is where zsh finds it" test -f "$XDG_DATA_HOME/zsh/site-functions/_pmg"
check "the uv bootstrapped for pmg is gone once uv is installed" test ! -e "$XDG_CACHE_HOME/zshsetup/uv"
check "a failed install leaves a marker" test -e "$home/failed/micro"
check "a failed install warns" grep -q "installing micro failed" /tmp/install-zshrc.log

# a new shell reads preinit.zsh, skips the failed package, and sets up the tools
clean_env="HOME=$HOME USER=$USER PATH=/usr/bin:/bin:$XDG_BIN_HOME TERM=dumb ZSHSETUP_GH_TOKEN=${ZSHSETUP_GH_TOKEN:-}"
# shellcheck disable=SC2016,SC2086
out="$(env -i $clean_env zsh -i -c 'echo "path1=$path[1]"; whence -w uvc; echo "capath=$GIT_SSL_CAPATH"' 2>&1)"
check "the next shell does not retry the failed install" lacks "$out" "Install micro via"
check "zshsetup's bin comes first on PATH" contains "$out" "path1=$home/bin"
check "uvc's shell function is loaded" contains "$out" "uvc: function"
if [ ! -e /etc/ssl/cert.pem ] && [ -z "$(ls -A /etc/ssl/certs 2>/dev/null)" ]; then
  check "git uses its bundled certificates without system ones" contains "$out" "capath=$XDG_DATA_HOME/git@.*/share/git-core/certs"
else
  check "git uses the system certificates" contains "$out" "capath=\$"
fi
check "the next shell does not reinstall disabled bun" lacks "$out" "Install bun via"

# shellcheck disable=SC2086
check "zsh ~/.zshrc update succeeds" env -i $clean_env zsh "$HOME/.zshrc" update
check "update removes the failed markers" test ! -e "$home/failed"

finish
