#!/bin/sh
# installs packages with pmg and checks that they run (ZSHSETUP_TEST_PACKAGES overrides the list)
. "${ZSHSETUP_TEST_REPO:-/zshsetup}/tests/lib.sh"
setup_zshsetup

if [ -e /etc/ssl/certs/ca-certificates.crt ] || [ -e /etc/ssl/cert.pem ]; then
  echo "  info  CA certificates present"
else
  echo "  info  no CA certificates"
fi
for p in ${ZSHSETUP_TEST_PACKAGES:-curl jq uv bat git uvc bun}; do
  case "$p" in
    uvc) arg=--help ;;
    *) arg=--version ;;
  esac
  check "$p installs and runs" sh -c "pmg install '$p' && '$p' $arg"
done

finish
