#!/usr/bin/env bash
# Usage: ./tests/docker_smoke_test.sh [-i IMAGE]... [PACKAGE]...
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGES=()
PACKAGES=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    -i)
      IMAGES+=("$2")
      shift 2
      ;;
    -*)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
    *)
      PACKAGES+=("$1")
      shift
      ;;
  esac
done
[ ${#IMAGES[@]} -gt 0 ] || IMAGES=(alpine:3.22 debian:stable-slim ubuntu:24.04)
[ ${#PACKAGES[@]} -gt 0 ] || PACKAGES=(curl jq uv bat python3 git)

# shellcheck disable=SC2016
container_script='
set -u
if [ -e /etc/ssl/certs/ca-certificates.crt ] || [ -e /etc/ssl/cert.pem ]; then
  echo "  info  CA certificates present"
else
  echo "  info  no CA certificates"
fi
if ! ZSHSETUP_ZSH_ONLY=1 sh /zshsetup/install.sh >/tmp/install.log 2>&1; then
  echo "  FAIL  install.sh (zsh bootstrap)"
  sed "s/^/        /" /tmp/install.log | tail -n 5
  exit 1
fi
echo "  ok    install.sh (zsh $(PATH="$HOME/.local/bin:$PATH" zsh --version | cut -d" " -f2))"
export ZSHSETUP_HOME="$HOME/.config/zshsetup" XDG_BIN_HOME="$HOME/.local/bin" XDG_DATA_HOME="$HOME/.local/share"
export ZSHSETUP_CHOICE=manual PATH="$HOME/.local/bin:$PATH"
mkdir -p "$ZSHSETUP_HOME" "$XDG_BIN_HOME" "$XDG_DATA_HOME"
cp -R /zshsetup/packages /zshsetup/package_manager.py /zshsetup/simple_term_menu.py "$ZSHSETUP_HOME/"
failed=0
for p in "$@"; do
  if "$ZSHSETUP_HOME/packages/$p.sh" install >"/tmp/$p.log" 2>&1 && "$p" --version >/dev/null 2>&1; then
    echo "  ok    $p ($("$p" --version 2>&1 | head -n 1))"
  else
    echo "  FAIL  $p"
    sed "s/^/        /" "/tmp/$p.log" | tail -n 5
    failed=1
  fi
done
exit "$failed"
'

status=0
for image in "${IMAGES[@]}"; do
  echo "== $image"
  if ! docker run --rm -v "$ROOT_DIR:/zshsetup:ro" "$image" sh -c "$container_script" sh "${PACKAGES[@]}"; then
    status=1
  fi
done
exit "$status"
