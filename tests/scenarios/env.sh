#!/bin/sh
# environment variables and small helpers: choices, preinit settings, /scratch, GitHub token
. "${ZSHSETUP_TEST_REPO:-/zshsetup}/tests/lib.sh"
setup_zshsetup

# a fake pmg, so choices can be checked without installing anything
fake="$(mktemp -d)"
cat >"$fake/pmg" <<'EOF'
#!/bin/sh
case "$1" in
  external) echo "${FAKE_EXTERNAL-apt fakeapt}" ;;
  install)
    shift
    echo "fake install $*"
    [ -z "${FAKE_INSTALL_FAILS:-}" ]
    ;;
esac
EOF
chmod +x "$fake/pmg"
choose() { # env assignments, then runs __package_manager of .zshrc for fake-pkg
  env PATH="$fake:$PATH" "$@" zsh -c "$(zshrc_function __eprint)
$(install_functions)
$(zshrc_function __choose_manager)
$(zshrc_function __package_manager)
__package_manager fake-pkg" </dev/null 2>&1
}

out="$(choose ZSHSETUP_CHOICE=manual)"
check "ZSHSETUP_CHOICE=manual installs with pmg" contains "$out" "fake install fake-pkg"
out="$(choose ZSHSETUP_CHOICE=brew)"
check "an unavailable choice falls back to manual" contains "$out" "fake install fake-pkg"
out="$(choose ZSHSETUP_CHOICE=apt ZSHSETUP_CHOICE_FAKE_PKG=manual)"
check "ZSHSETUP_CHOICE_<PACKAGE> overrides ZSHSETUP_CHOICE (dashes become underscores)" contains "$out" "fake install"
out="$(choose ZSHSETUP_CHOICE= FAKE_EXTERNAL=)"
check "a package only pmg has installs without asking" contains "$out" "fake install fake-pkg"
if has_apt; then
  out="$(choose ZSHSETUP_CHOICE= ZSHSETUP_CHOICE_FAKE_PKG=)"
  check "no choice and no terminal stops with a hint" contains "$out" "set ZSHSETUP_CHOICE or ZSHSETUP_CHOICE_FAKE_PKG"
fi

# missing packages install together, a package that is there or listed twice only once
require_all() { # env assignments, then runs __require_all of .zshrc for fake-a, fake-b, and sh
  env PATH="$fake:$PATH" ZSHSETUP_CHOICE=manual "$@" zsh -c "$(zshrc_function __eprint)
$(install_functions)
$(zshrc_function __last_match)
$(zshrc_function __pmg_installed)
$(zshrc_function __choose_manager)
$(zshrc_function __wants_install)
$(zshrc_function __record_install)
$(zshrc_function __require_all)
__require_all fake-a sh fake-b fake-a" </dev/null 2>&1
}
out="$(require_all)"
check "__require_all installs the missing packages with one pmg run" contains "$out" "^fake install fake-a fake-b$"
rm -rf "$ZSHSETUP_HOME/failed"
out="$(require_all FAKE_INSTALL_FAILS=1)"
check "__require_all installs one by one after pmg failed for all" contains "$out" "^fake install fake-b$"
check "__require_all asks for each missing package once" test "$(printf '%s\n' "$out" | grep -c 'Install fake-a via')" -eq 1
check "__require_all skips packages in PATH" lacks "$out" "Install sh via"
check "__require_all records the packages that are still missing" contains "$out" "installing fake-b failed"
out="$(require_all)"
check "__require_all skips packages that failed within a day" lacks "$out" "fake install"
rm -rf "$ZSHSETUP_HOME/failed"
out="$(require_all ZSHSETUP_DISABLE_FAKE_A=1)"
check "__require_all skips disabled packages" contains "$out" "^fake install fake-b$"
rm -rf "$ZSHSETUP_HOME/failed"

# settings given at installation are saved to preinit.zsh
preinit_home="$(mktemp -d)"
env -i HOME="$HOME" PATH="$PATH" ZSHSETUP_HOME="$preinit_home" ZSHSETUP_CHOICE=manual ZSHSETUP_CHOICE_CURL=apt \
  ZSHSETUP_REQUIRE_ZIG=1 ZSHSETUP_DISABLE_BUN=1 PMG_RUST_TOOLCHAIN="1.80 beta" PMG_GH_TOKEN=secret \
  zsh -c "$(zshrc_function __save_settings)
__save_settings"
for setting in "ZSHSETUP_CHOICE=manual" "ZSHSETUP_CHOICE_CURL=apt" "ZSHSETUP_REQUIRE_ZIG=1" "ZSHSETUP_DISABLE_BUN=1"; do
  check "preinit.zsh saves $setting" grep -qx "export $setting" "$preinit_home/preinit.zsh"
done
check "preinit.zsh quotes values" zsh -c ". $preinit_home/preinit.zsh; [ \"\$PMG_RUST_TOOLCHAIN\" = '1.80 beta' ]"
check "preinit.zsh does not save PMG_GH_TOKEN" sh -c "! grep -q GH_TOKEN $preinit_home/preinit.zsh"
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

# the version checks with which packages/pmg keeps an installed pmg
# shellcheck disable=SC2329
at_least() { env ZSHSETUP_INSTALL_LIB=1 sh -c ". '$REPO/install.sh' && __version_at_least '$1' '$2'"; }
# shellcheck disable=SC2329
not_at_least() { ! at_least "$@"; }
check "v1.10.0 is at least v1.9.2" at_least v1.10.0 v1.9.2
check "v1.4.0 is at least v1.4.0" at_least v1.4.0 v1.4.0
check "v1.4 is at least v1.4.0" at_least v1.4 v1.4.0
check "v1.3.9 is not at least v1.4.0" not_at_least v1.3.9 v1.4.0
check "the URL of an older install is not at least a tag" not_at_least https://example.com/v9.tar.gz v1.4.0
check "no install is not at least a tag" not_at_least "" v1.4.0

# install.sh installs git and uv with the chosen system package manager
# shellcheck disable=SC2329
chosen() { # package, names, then env assignments
  package="$1" names="$2"
  shift 2
  env ZSHSETUP_INSTALL_LIB=1 "$@" sh -c ". '$REPO/install.sh' && __install_chosen '$package' '$names'"
}
# shellcheck disable=SC2329
not_chosen() { ! chosen "$@"; }
check "install.sh leaves ZSHSETUP_CHOICE=manual to pmg" not_chosen git 'apk git' ZSHSETUP_CHOICE=manual
check "install.sh leaves a package without a name for the choice to pmg" not_chosen uv 'apk uv' ZSHSETUP_CHOICE=apt
check "install.sh leaves ZSHSETUP_CHOICE=os without an available manager to pmg" not_chosen git 'fakeos git' ZSHSETUP_CHOICE=os
if command -v apk >/dev/null 2>&1; then
  check "ZSHSETUP_CHOICE_TREE=apk installs tree with apk" chosen tree 'apk tree' ZSHSETUP_CHOICE_TREE=apk
  check "ZSHSETUP_CHOICE_TREE=os installs tree with apk" chosen tree 'apk tree' ZSHSETUP_CHOICE_TREE=os
  check "apk keeps no index" test -z "$(ls -A /var/cache/apk 2>/dev/null)"
fi
if command -v dnf >/dev/null 2>&1; then
  # shellcheck disable=SC2329
  has_metadata() { env ZSHSETUP_INSTALL_LIB=1 sh -c ". '$REPO/install.sh' && __has_metadata dnf"; }
  # shellcheck disable=SC2329
  no_metadata() { ! has_metadata; }
  check "the image has no dnf metadata" no_metadata
  check "ZSHSETUP_CHOICE_JQ=dnf installs jq with dnf" env ZSHSETUP_INSTALL_LIB=1 ZSHSETUP_CHOICE_JQ=dnf \
    sh -c ". '$REPO/install.sh' && __install_chosen jq 'dnf jq' && __clean_metadata"
  check "jq comes from dnf" rpm -q jq
  check "the dnf metadata downloaded for jq is removed" no_metadata
fi

# an unknown terminal type and plain xterm fall back to xterm-256color, a known or empty one stays
term_after() { env TERM="$1" zsh -c "$(zshrc_function __has_terminfo)
$(zshrc_function __fallback_term)
__fallback_term; print -r -- \"\$TERM\""; }
check "an unknown TERM falls back to xterm-256color" test "$(term_after zshsetup-unknown)" = xterm-256color
check "an empty TERM stays empty" test -z "$(term_after "")"
# shellcheck disable=SC2016 # the inner zsh expands it
if [ -n "$(env TERM=dumb zsh -c 'zmodload zsh/terminfo && print -r -- "${terminfo[cols]}"' 2>/dev/null)" ]; then
  check "a known TERM stays" test "$(term_after dumb)" = dumb
else
  echo "  skip  a known TERM stays (no terminfo entry for dumb)"
fi
# an entry only in TERMINFO_DIRS, as pmg exports it for ghostty-terminfo, is kept
entry_dir="$(mktemp -d)"
for dir in /usr/share/terminfo /lib/terminfo /etc/terminfo; do
  [ -e "$dir/v/vt100" ] && mkdir -p "$entry_dir/z" && cp "$dir/v/vt100" "$entry_dir/z/zshsetup-term" && break
done
if [ -s "$entry_dir/z/zshsetup-term" ]; then
  check "an entry in TERMINFO_DIRS is kept" test "$(TERMINFO_DIRS="$entry_dir:" term_after zshsetup-term)" = zshsetup-term
else
  echo "  skip  an entry in TERMINFO_DIRS is kept (no vt100 entry to copy)"
fi
has_xterm_256color="$(zsh -c "$(zshrc_function __has_terminfo)
__has_terminfo xterm-256color && echo yes")"
if [ -n "$has_xterm_256color" ]; then
  check "plain xterm, as docker run -t sets it, becomes xterm-256color" test "$(term_after xterm)" = xterm-256color
else
  check "plain xterm stays without an xterm-256color entry" test "$(term_after xterm)" = xterm
fi

# __assure_link backs up existing files/dirs to .pre-zshsetup and creates the link
test_link_dir="$(mktemp -d)"
target_file="$test_link_dir/target"
link_file="$test_link_dir/link"
echo "new content" >"$target_file"
echo "original content" >"$link_file"
env ZSHSETUP_HOME="$test_link_dir" zsh -c "$(zshrc_function __eprint)
$(zshrc_function __assure_link)
__assure_link '$link_file' '$target_file'" >/dev/null 2>&1
check "__assure_link backs up an existing file to .pre-zshsetup" test -f "$link_file.pre-zshsetup"
check "__assure_link backup preserves original content" grep -q "original content" "$link_file.pre-zshsetup"
check "__assure_link creates the symlink" test -L "$link_file"
check "__assure_link symlink points to expected target" test "$(readlink "$link_file")" = "$target_file"

rm -f "$link_file"
echo "existing again" >"$link_file"
fail_out="$(env ZSHSETUP_HOME="$test_link_dir" zsh -c "$(zshrc_function __eprint)
$(zshrc_function __assure_link)
__assure_link '$link_file' '$target_file'" 2>&1 || true)"
check "__assure_link fails if backup already exists" contains "$fail_out" "already exists"

# __link_plugin_configs links config/ entries of plugins to XDG_CONFIG_HOME
plugin_config_dir="$test_link_dir/plugins/test-plugin/config"
mkdir -p "$plugin_config_dir/app1" "$plugin_config_dir/app2"
xdg_config="$test_link_dir/xdg_config"
mkdir -p "$xdg_config"
env ZSHSETUP_HOME="$test_link_dir" XDG_CONFIG_HOME="$xdg_config" zsh -c "$(zshrc_function __eprint)
$(zshrc_function __assure_link)
$(zshrc_function __plugin_paths)
$(zshrc_function __link_plugin_configs)
__link_plugin_configs" >/dev/null 2>&1
check "__link_plugin_configs links plugin config directories" test -L "$xdg_config/app1"
check "__link_plugin_configs links point to plugin config" test "$(readlink "$xdg_config/app1")" = "$plugin_config_dir/app1"
rm -rf "$test_link_dir"

# __extra_packages loads packages from plugins/*/packages and ZSHSETUP_REQUIRE_*
test_pkg_dir="$(mktemp -d)"
mkdir -p "$test_pkg_dir/plugins/my-plugin"
cat >"$test_pkg_dir/plugins/my-plugin/packages" <<'EOF'
# comment line
pkg-from-plugin
  another-pkg  # inline comment
  shared-pkg
EOF
# shellcheck disable=SC1083
pkgs="$(env ZSHSETUP_HOME="$test_pkg_dir" ZSHSETUP_REQUIRE_SHARED_PKG=1 ZSHSETUP_REQUIRE_EXTRA_TOOL=1 zsh -c "$(zshrc_function __plugin_paths)
$(zshrc_function __extra_packages)
__extra_packages
print -r -- "\${reply[@]}"")"
check "__extra_packages loads packages from plugins" contains "$pkgs" "pkg-from-plugin"
check "__extra_packages loads inline-commented package" contains "$pkgs" "another-pkg"
check "__extra_packages includes ZSHSETUP_REQUIRE_* packages" contains "$pkgs" "extra-tool"
check "__extra_packages deduplicates shared packages" test "$(printf '%s\n' "$pkgs" | tr ' ' '\n' | grep -c '^shared-pkg$')" -eq 1
rm -rf "$test_pkg_dir"

out="$(choose ZSHSETUP_CHOICE=os FAKE_EXTERNAL=)"
check "ZSHSETUP_CHOICE=os falls back to manual when no OS package exists" contains "$out" "fake install fake-pkg"

finish
