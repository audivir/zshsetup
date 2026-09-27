#!/bin/sh
# environment variables and small helpers: choices, preinit settings, /scratch, GitHub token, libc
. "${ZSHSETUP_TEST_REPO:-/zshsetup}/tests/lib.sh"
setup_zshsetup
helper="$ZSHSETUP_HOME/packages/helper.sh"

# a fake package, so choices can be checked without installing anything
# shellcheck disable=SC2016
printf '#!/bin/sh\necho "fake $1"\n' >"$ZSHSETUP_HOME/packages/fake-pkg.sh"
chmod +x "$ZSHSETUP_HOME/packages/fake-pkg.sh"
choose() { # env assignments..., then the package manager arguments
  # shellcheck disable=SC2016
  env "$@" zsh -c '. "$1"; shift; package_manager "$@"' sh "$helper" fake-pkg "" fakeapt </dev/null 2>&1
}

out="$(choose ZSHSETUP_CHOICE=manual)"
check "ZSHSETUP_CHOICE=manual runs the manual install" contains "$out" "fake install"
out="$(choose ZSHSETUP_CHOICE=brew)"
check "an unavailable choice falls back to manual" contains "$out" "fake install"
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

# libc detection picks the right downloads
libc="$(zsh -c ". $helper; __libc")"
if is_musl; then
  check "__libc detects musl" test "$libc" = musl
elif is_linux; then
  check "__libc detects glibc" test "$libc" = gnu
else
  check "__libc is empty outside Linux" test -z "$libc"
fi

# ZSHSETUP_GH_TOKEN lifts the GitHub API rate limit
if [ -n "${ZSHSETUP_GH_TOKEN:-}" ]; then
  export ZSHSETUP_CHOICE=manual
  limit="$(zsh -c ". $helper; require_cmd curl jq && github_api rate_limit | jq .resources.core.limit" 2>/dev/null)"
  check "ZSHSETUP_GH_TOKEN authenticates GitHub API requests" test "${limit:-0}" -gt 60
else
  echo "  skip  ZSHSETUP_GH_TOKEN test (not set)"
fi

finish
