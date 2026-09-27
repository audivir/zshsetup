#!/usr/bin/env bash
#
# Runs the test scenarios in tests/scenarios/ in fresh containers, or natively with a temp HOME.
#
# Usage: ./tests/run_tests.sh [-i IMAGE]... [--native] [SCENARIO]...
#
#   -i IMAGE  container image, repeatable (default: alpine:3.22 debian:stable-slim ubuntu:24.04 rockylinux:8)
#   --native  run on this machine instead (e.g. macOS), with a temporary HOME; choices, shell, and
#             musl expect a bare system, so they only fit containers
#   SCENARIO  env packages choices lifecycle shell musl all (default: all but the slow musl and all)
#
# ZSHSETUP_GH_TOKEN is passed on to avoid GitHub's API rate limit; ZSHSETUP_TEST_PACKAGES sets
# the packages of the packages scenario.
#
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGES=()
SCENARIOS=()
NATIVE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    -i)
      IMAGES+=("$2")
      shift 2
      ;;
    --native)
      NATIVE=1
      shift
      ;;
    -*)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
    *)
      SCENARIOS+=("$1")
      shift
      ;;
  esac
done
[ ${#IMAGES[@]} -gt 0 ] || IMAGES=(alpine:3.22 debian:stable-slim ubuntu:24.04 rockylinux:8)
[ ${#SCENARIOS[@]} -gt 0 ] || SCENARIOS=(env packages choices lifecycle shell)

status=0
for scenario in "${SCENARIOS[@]}"; do
  if [ ! -f "$ROOT_DIR/tests/scenarios/$scenario.sh" ]; then
    echo "Unknown scenario: $scenario" >&2
    exit 1
  fi
  if [ "$NATIVE" = 1 ]; then
    echo "== native: $scenario"
    home="$(mktemp -d)"
    if ! env HOME="$home" ZSHSETUP_TEST_REPO="$ROOT_DIR" sh "$ROOT_DIR/tests/scenarios/$scenario.sh"; then
      status=1
    fi
    rm -rf "$home"
    continue
  fi
  for image in "${IMAGES[@]}"; do
    echo "== $image: $scenario"
    if ! docker run --rm -e ZSHSETUP_GH_TOKEN -e ZSHSETUP_TEST_PACKAGES -v "$ROOT_DIR:/zshsetup:ro" \
      "$image" sh "/zshsetup/tests/scenarios/$scenario.sh"; then
      status=1
    fi
  done
done
exit "$status"
