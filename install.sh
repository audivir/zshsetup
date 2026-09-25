#!/bin/sh
# shellcheck shell=sh

__available() {
  cmd="$1"
  shift
  command "$cmd" "$@" >/dev/null 2>&1
}

if [ -z "$HOME" ]; then
  echo "HOME must be set"
  exit 1
fi

if ! __available curl --help || ! __available git --help; then
  echo "curl and git required!"
  exit 1
fi

if ! __available zsh --help; then
  export PATH="$PATH:$HOME/.local/bin"
  if ! __available zsh --help; then
    curl --fail-with-body -L https://raw.githubusercontent.com/romkatv/zsh-bin/master/install \
      | sh -s -- -d "$HOME/.local" -e "no" || exit 1
  fi
fi

curl --fail-with-body -L https://github.com/audivir/zshsetup/raw/refs/heads/main/.zshrc | zsh -s -- install
