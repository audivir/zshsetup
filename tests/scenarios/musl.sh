#!/bin/sh
# musl extras through a shell start: micromamba with a user-space glibc (create, activate, run,
# completion), Rust with zig's libgcc_s and cc, bun with musl-libs, and statically built make and gawk (slow)
. "${ZSHSETUP_TEST_REPO:-/zshsetup}/tests/lib.sh"
is_musl || skip "musl only"
setup_zshsetup
ln -s "$ZSHSETUP_HOME/.zshrc" "$HOME/.zshrc"
export ZSHSETUP_CHOICE=manual ZSHSETUP_REQUIRE_MICROMAMBA=1 ZSHSETUP_DISABLE_GO=1

check "the first shell start installs everything" zsh -i -c 'echo ready'
check "no install failed" test ! -e "$ZSHSETUP_HOME/failed"

out="$(zsh -i -c '
micromamba create -q -y -n test -c conda-forge python=3.12 numpy >/dev/null && echo "created"
micromamba activate test && python -c "import numpy, ssl; print(\"numpy\", numpy.__version__)"
micromamba install -q -y -c conda-forge requests >/dev/null && python -c "import requests; print(\"requests ok\")"
micromamba run -n test python -c "print(\"run ok\")"
micromamba run -a stdin -n test true 2>&1
echo "completion: $(__mamba_exe completer cr)"
cd "$(mktemp -d)" && cargo new -q hello && cd hello && cargo run -q
echo "make: $(make --version | head -n 1)"
echo "gawk: $(gawk --version | head -n 1)"
echo "bun: $(bun -e "console.log([1, 2].map((x) => x * 2).join())")"
' 2>&1)"
check "micromamba creates an environment" contains "$out" "^created"
check "the patched environment runs python with numpy" contains "$out" "^numpy "
check "micromamba install patches new packages" contains "$out" "^requests ok"
check "micromamba run works through the wrapper" contains "$out" "^run ok"
check "unsupported micromamba run flags stop with a message" contains "$out" "not supported on musl"
check "micromamba completion works through the wrapper" contains "$out" "completion: create"
check "cargo builds and runs with zig as cc" contains "$out" "Hello, world!"
check "make runs" contains "$out" "make: GNU Make"
check "gawk runs" contains "$out" "gawk: GNU Awk"
check "bun runs" contains "$out" "bun: 2,4"
if [ ! -e /usr/lib/libstdc++.so.6 ]; then
  check "bun's libstdc++ comes from musl-libs" sh -c "ls '$XDG_DATA_HOME'/pmg/packages/musl-libs@*/usr/lib/libstdc++.so.6"
fi
check "uninstalling bun keeps musl-libs for Rust" sh -c "pmg uninstall bun && ls -d '$XDG_DATA_HOME'/pmg/packages/musl-libs@*"

finish
