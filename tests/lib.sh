# shellcheck shell=sh
# shared helpers for tests/scenarios/*.sh, which run in a fresh container (or natively with a temp HOME)

REPO="${ZSHSETUP_TEST_REPO:-/zshsetup}"
FAILURES=0

ok() { echo "  ok    $*"; }
fail() {
  echo "  FAIL  $*"
  FAILURES=$((FAILURES + 1))
}
skip() {
  echo "  skip  $*"
  exit 0
}
finish() {
  [ "$FAILURES" -eq 0 ] || exit 1
  exit 0
}

# check <description> <command>...: runs the command quietly and shows its output on failure
check() {
  description="$1"
  shift
  if "$@" >/tmp/check.log 2>&1; then
    ok "$description"
  else
    fail "$description"
    sed 's/^/        /' /tmp/check.log | tail -n 8
  fi
}

# contains/lacks <text> <pattern>: whether the text matches the grep pattern, printing it otherwise
contains() {
  printf '%s\n' "$1" | grep -q -- "$2" && return 0
  printf '%s\n' "$1"
  return 1
}
lacks() {
  printf '%s\n' "$1" | grep -q -- "$2" || return 0
  printf '%s\n' "$1"
  return 1
}

is_musl() { [ -e /lib/ld-musl-x86_64.so.1 ] || [ -e /lib/ld-musl-aarch64.so.1 ]; }
is_linux() { [ "$(uname)" = "Linux" ]; }
has_apt() { command -v apt-get >/dev/null 2>&1; }

# installs zsh with install.sh and sets the environment .zshrc would set
setup_env() {
  export USER="${USER:-$(id -un)}"
  if ! ZSHSETUP_ZSH_ONLY=1 sh "$REPO/install.sh" >/tmp/install.log 2>&1; then
    fail "zsh bootstrap with install.sh"
    tail -n 5 /tmp/install.log
    exit 1
  fi
  export ZSHSETUP_HOME="$HOME/.config/zshsetup" XDG_BIN_HOME="$HOME/.local/bin"
  export XDG_DATA_HOME="$HOME/.local/share" XDG_CACHE_HOME="$HOME/.cache"
  # only the system dirs, so the tools of the machine running the tests are not found
  export PATH="$ZSHSETUP_HOME/bin:$XDG_BIN_HOME:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
  mkdir -p "$XDG_BIN_HOME" "$XDG_DATA_HOME"
}

# copies the working tree to $1 (the files an install clones)
copy_tree() {
  mkdir -p "$1"
  (cd "$REPO" && tar -cf - .gitignore .zshrc install.sh custom_functions.sh theme_viewer.sh completions packages) \
    | tar -xf - -C "$1"
}

# sets up ZSHSETUP_HOME from the working tree, for running pmg directly
setup_zshsetup() {
  setup_env
  copy_tree "$ZSHSETUP_HOME"
  mkdir -p "$ZSHSETUP_HOME/bin"
  ln -s "$ZSHSETUP_HOME/packages/pmg" "$ZSHSETUP_HOME/bin/pmg"
}

# prints a zsh function from .zshrc, to test it on its own
zshrc_function() {
  sed -n "/^$1() {/,/^}/p" "$REPO/.zshrc"
}
