#!/bin/sh
# every package through a shell start, with all non-default packages required (slow)
. "${ZSHSETUP_TEST_REPO:-/zshsetup}/tests/lib.sh"
setup_zshsetup
ln -s "$ZSHSETUP_HOME/.zshrc" "$HOME/.zshrc"
export ZSHSETUP_CHOICE=manual ZSHSETUP_REQUIRE_ZIG=1 ZSHSETUP_REQUIRE_MAKE=1 ZSHSETUP_REQUIRE_ZSTD=1 \
  ZSHSETUP_REQUIRE_MICROMAMBA=1 ZSHSETUP_REQUIRE_GO=1 ZSHSETUP_REQUIRE_RUSTUP=1 ZSHSETUP_REQUIRE_BUN=1
is_linux && export ZSHSETUP_REQUIRE_PATCHELF=1
is_musl && export ZSHSETUP_REQUIRE_GLIBC=1 ZSHSETUP_REQUIRE_MUSL_LIBS=1

zsh -i -c 'echo ready' >/tmp/all-install.log 2>&1 || true
check "no install failed" test ! -e "$ZSHSETUP_HOME/failed"
if [ -e "$ZSHSETUP_HOME/failed" ]; then
  echo "  info  failed: $(cd "$ZSHSETUP_HOME/failed" && echo *)"
  tail -n 60 /tmp/all-install.log | sed 's/^/        /'
fi

run() {
  echo "  info  $1: $(zsh -i -c "whence -p ${2%% *}" 2>/dev/null)"
  check "$1 runs" zsh -i -c "$2"
}
run curl "curl --version"
run git "git ls-remote https://github.com/audivir/zshsetup HEAD"
run zig "zig version"
run make "make --version"
run gawk "gawk --version"
run jq "jq --version"
run micromamba "micromamba create -q -y -p /tmp/env -c conda-forge python && micromamba run -p /tmp/env python -c 'print(1)'"
run go "go version"
run rustup "cd \$(mktemp -d) && cargo new -q hello && cd hello && cargo run -q"
run uv "uv --version"
run python "uv run --no-project python -c 'import ssl, sqlite3'"
run uvc "uvc --help"
run bun "bun -e 'console.log(1)'"
run bat "bat --version"
run micro "micro --version"
run kv "kv --version"
run zstd "zstd --version"
if is_linux; then
  is_musl && run glibc "\$XDG_DATA_HOME/pmg/packages/glibc@*/loader --version"
  is_musl && run musl-libs "test -e \$XDG_DATA_HOME/pmg/packages/musl-libs@*/usr/lib/libgcc_s.so.1"
  run patchelf "patchelf --version"
fi

finish
