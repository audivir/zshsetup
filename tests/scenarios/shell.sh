#!/bin/sh
# full installation through .zshrc from the working tree: preinit, REQUIRE/DISABLE, failed installs, update
. "${ZSHSETUP_TEST_REPO:-/zshsetup}/tests/lib.sh"
setup_env
export ZSHSETUP_CHOICE=manual

# a git repo of the working tree to install from, with kv failing on purpose
src="$(mktemp -d)/zshsetup"
copy_tree "$src"
check "git installs for cloning" env ZSHSETUP_HOME="$src" sh "$src/packages/pmg" install git
# a release that does not exist
sed 's|^repo = "audivir/kv"$|repo = "audivir/kv-missing"|' "$src/packages/specs/kv.toml" \
  >"$src/packages/specs/kv.toml.new"
mv "$src/packages/specs/kv.toml.new" "$src/packages/specs/kv.toml"
check "the spec of kv points to a missing release" grep -q '^repo = "audivir/kv-missing"$' \
  "$src/packages/specs/kv.toml"
git -C "$src" init -q
git -C "$src" add -A
git -C "$src" -c user.name=test -c user.email=test@test commit -q -m test

# micromamba and gawk are slow to install and covered elsewhere
export ZSHSETUP_REPO="$src" ZSHSETUP_REQUIRE_PATCHELF=1 ZSHSETUP_DISABLE_MICROMAMBA=1 \
  ZSHSETUP_DISABLE_GAWK=1
unset ZSHSETUP_HOME
home="$HOME/.config/zshsetup"
check "zsh .zshrc install succeeds" zsh "$src/.zshrc" install
cp /tmp/check.log /tmp/install-zshrc.log

check "\$HOME/.zshrc links to the installed .zshrc" test "$(readlink "$HOME/.zshrc")" = "$home/.zshrc"
for setting in "ZSHSETUP_CHOICE=manual" "ZSHSETUP_REQUIRE_PATCHELF=1" "ZSHSETUP_DISABLE_GAWK=1"; do
  check "preinit.zsh saves $setting" grep -qx "export $setting" "$home/preinit.zsh"
done
check "ZSHSETUP_REQUIRE_PATCHELF installs patchelf" test -e "$XDG_BIN_HOME/patchelf"
check "ZSHSETUP_DISABLE_GAWK skips gawk" test ! -e "$XDG_BIN_HOME/gawk"
check "the pmg command is linked" test -L "$home/bin/pmg"
source_file="$XDG_DATA_HOME/zshsetup/pmg/.source"
# shellcheck disable=SC2016
check "pmg is installed at a tag not older than the minimum" env ZSHSETUP_INSTALL_LIB=1 \
  sh -c ". '$home/install.sh' && __version_at_least \"\$(cat '$source_file')\" \"\$__PMG_TAG\""
echo v1.0.0 >"$source_file"
check "pmg reinstalls a tag older than the minimum" "$home/bin/pmg" version
check "the reinstalled tag is newer" test "$(cat "$source_file")" != v1.0.0
check "pmg self-upgrade keeps the latest tag" contains "$("$home/bin/pmg" self-upgrade 2>&1)" "is the latest"
check "pmg runs from its own venv" test -x "$XDG_DATA_HOME/zshsetup/pmg/bin/python"
check "the completion of pmg is where zsh finds it" test -f "$XDG_DATA_HOME/zsh/site-functions/_pmg"
check "the uv bootstrapped for pmg is gone once uv is installed" test ! -e "$XDG_CACHE_HOME/zshsetup/uv"
check "a failed install leaves a marker" test -e "$home/failed/kv"
check "a failed install warns" grep -q "installing kv failed" /tmp/install-zshrc.log

# a new shell reads preinit.zsh, skips the failed package, and sets up the tools; the dir of the
# completions is missing where pmg never installed a package
rm -rf "$XDG_DATA_HOME/zsh/site-functions"
clean_env="HOME=$HOME USER=$USER PATH=/usr/bin:/bin:$XDG_BIN_HOME TERM=dumb PMG_GH_TOKEN=${PMG_GH_TOKEN:-}"
# shellcheck disable=SC2016,SC2086
out="$(env -i $clean_env zsh -i -c 'echo "path1=$path[1]"; whence -w uvc; echo "capath=$GIT_SSL_CAPATH"' 2>&1)"
check "the next shell does not retry the failed install" lacks "$out" "Install kv via"
check "zshsetup's bin comes first on PATH" contains "$out" "path1=$home/bin"
check "uvc's shell function is loaded" contains "$out" "uvc: function"
if [ ! -e /etc/ssl/cert.pem ] && [ -z "$(ls -A /etc/ssl/certs 2>/dev/null)" ]; then
  check "git uses its bundled certificates without system ones" contains "$out" "capath=$XDG_DATA_HOME/pmg/packages/git@.*/share/git-core/certs"
else
  check "git uses the system certificates" contains "$out" "capath=\$"
fi
check "the next shell does not reinstall disabled gawk" lacks "$out" "Install gawk via"
check "the next shell writes the completion of pmg" test -s "$XDG_DATA_HOME/zsh/site-functions/_pmg"
# shellcheck disable=SC2016,SC2086
out="$(env -i $clean_env zsh -i -c 'true; print -P "ok:$PROMPT"; (exit 12); print -P "failed:$PROMPT"' 2>&1)"
check "the prompt shows the exit code if it is not 0" contains "$out" "failed:.*⟨12⟩"
check "the prompt hides the exit code if it is 0" lacks "$out" "ok:.*⟨"

# update upgrades with the pulled .zshrc, as the steps of the running shell may be outdated
awk '{ print } /^__upgrade_zshsetup\(\) \{$/ { print "  touch /tmp/upgraded-by-pulled-zshrc" }' "$src/.zshrc" \
  >"$src/.zshrc.new"
mv "$src/.zshrc.new" "$src/.zshrc"
git -C "$src" -c user.name=test -c user.email=test@test commit -q -am "upgrade marker"

# shellcheck disable=SC2086
check "zsh ~/.zshrc update succeeds" env -i $clean_env zsh "$HOME/.zshrc" update
check "update removes the failed markers" test ! -e "$home/failed"
check "update upgrades with the pulled .zshrc" test -e /tmp/upgraded-by-pulled-zshrc

finish
