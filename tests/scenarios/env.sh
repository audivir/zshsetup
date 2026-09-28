#!/bin/sh
# environment variables and small helpers: choices, preinit settings, /scratch, GitHub token
. "${ZSHSETUP_TEST_REPO:-/zshsetup}/tests/lib.sh"
setup_zshsetup

# a fake pmg, so choices can be checked without installing anything
fake="$(mktemp -d)"
cat >"$fake/pmg" <<'EOF'
#!/bin/sh
case "$1" in
  external) echo "apt fakeapt" ;;
  install) echo "fake install $2" ;;
esac
EOF
chmod +x "$fake/pmg"
choose() { # env assignments, then runs __package_manager of .zshrc for fake-pkg
  env PATH="$fake:$PATH" "$@" zsh -c "$(zshrc_function __eprint)
$(zshrc_function __available)
$(zshrc_function __package_manager)
__package_manager fake-pkg" </dev/null 2>&1
}

out="$(choose ZSHSETUP_CHOICE=manual)"
check "ZSHSETUP_CHOICE=manual installs with pmg" contains "$out" "fake install fake-pkg"
out="$(choose ZSHSETUP_CHOICE=brew)"
check "an unavailable choice falls back to manual" contains "$out" "fake install fake-pkg"
out="$(choose ZSHSETUP_CHOICE=apt ZSHSETUP_CHOICE_FAKE_PKG=manual)"
check "ZSHSETUP_CHOICE_<PACKAGE> overrides ZSHSETUP_CHOICE (dashes become underscores)" contains "$out" "fake install"
out="$(choose ZSHSETUP_CHOICE= ZSHSETUP_CHOICE_FAKE_PKG=)"
check "no choice and no terminal stops with a hint" contains "$out" "set ZSHSETUP_CHOICE or ZSHSETUP_CHOICE_FAKE_PKG"

# settings given at installation are saved to preinit.zsh
preinit_home="$(mktemp -d)"
env -i HOME="$HOME" PATH="$PATH" ZSHSETUP_HOME="$preinit_home" ZSHSETUP_CHOICE=manual ZSHSETUP_CHOICE_CURL=apt \
  ZSHSETUP_REQUIRE_ZIG=1 ZSHSETUP_DISABLE_BUN=1 ZSHSETUP_RUST_TOOLCHAIN="1.80 beta" ZSHSETUP_GH_TOKEN=secret \
  zsh -c "$(zshrc_function __save_settings)
__save_settings"
for setting in "ZSHSETUP_CHOICE=manual" "ZSHSETUP_CHOICE_CURL=apt" "ZSHSETUP_REQUIRE_ZIG=1" "ZSHSETUP_DISABLE_BUN=1"; do
  check "preinit.zsh saves $setting" grep -qx "export $setting" "$preinit_home/preinit.zsh"
done
check "preinit.zsh quotes values" zsh -c ". $preinit_home/preinit.zsh; [ \"\$ZSHSETUP_RUST_TOOLCHAIN\" = '1.80 beta' ]"
check "preinit.zsh does not save ZSHSETUP_GH_TOKEN" sh -c "! grep -q GH_TOKEN $preinit_home/preinit.zsh"
check "preinit.zsh is executable" test -x "$preinit_home/preinit.zsh"

# the cache moves to /scratch when it exists, unless ignored
if mkdir -p /scratch 2>/dev/null; then
  init_cache() { # HOME, then env assignments
    cache_home="$1"
    shift
    env HOME="$cache_home" "$@" zsh -c "$(zshrc_function __eprint)
$(zshrc_function __assure_dir)
$(zshrc_function __assure_link)
$(zshrc_function __init_cache)
__init_cache" 2>&1
  }
  h="$(mktemp -d)"
  init_cache "$h" >/dev/null
  check "\$HOME/.cache links to /scratch/\$USER/.cache when /scratch exists" test -L "$h/.cache"
  h="$(mktemp -d)"
  init_cache "$h" ZSHSETUP_IGNORESCRATCH=1 >/dev/null
  check "ZSHSETUP_IGNORESCRATCH keeps \$HOME/.cache" test ! -L "$h/.cache"
  h="$(mktemp -d)"
  mkdir -p "$h/.cache" && touch "$h/.cache/.zshsetup_do_not_use_scratch"
  init_cache "$h" >/dev/null
  check "the .zshsetup_do_not_use_scratch file keeps \$HOME/.cache" test ! -L "$h/.cache"
  h="$(mktemp -d)"
  mkdir -p "$h/.cache"
  out="$(init_cache "$h")"
  check "an existing \$HOME/.cache stops with instructions" contains "$out" "zshsetup stopped: /scratch exists"
else
  echo "  skip  /scratch tests (cannot create /scratch)"
fi

# ZSHSETUP_GH_TOKEN reaches pmg as PMG_GH_TOKEN
# shellcheck disable=SC2016
check "the pmg wrapper passes ZSHSETUP_GH_TOKEN on" grep -q 'PMG_GH_TOKEN="${PMG_GH_TOKEN:-${ZSHSETUP_GH_TOKEN:-}}"' \
  "$ZSHSETUP_HOME/packages/pmg"

finish
