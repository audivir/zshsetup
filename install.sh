#!/bin/sh
# shellcheck shell=sh

__available() {
  cmd="$1"
  shift
  command "$cmd" "$@" >/dev/null 2>&1
}

__download() {
  url="$1"
  if command -v curl >/dev/null 2>&1; then
    curl --fail-with-body -sSL "$url"
  elif command -v wget >/dev/null 2>&1; then
    wget -q -O - "$url"
  else
    echo "curl or wget required!" >&2
    exit 1
  fi
}

if [ -z "$HOME" ]; then
  echo "HOME must be set"
  exit 1
fi

if [ "$(uname)" = "Darwin" ] && [ "$(uname -m)" != "arm64" ]; then
  echo "Only macOS arm64 is supported" >&2
  exit 1
fi

if { ! __available curl --help && ! __available wget --help; } || ! __available git --help; then
  echo "curl (or wget) and git required!"
  exit 1
fi

if ! __available zsh --help; then
  export PATH="$PATH:$HOME/.local/bin"
  if ! __available zsh --help; then
    __download https://raw.githubusercontent.com/romkatv/zsh-bin/master/install \
      | sh -s -- -d "$HOME/.local" -e "no" || exit 1
  fi
fi

__download https://github.com/audivir/zshsetup/raw/refs/heads/main/.zshrc | zsh -s -- install
