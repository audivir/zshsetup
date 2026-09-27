#!/bin/sh
# installs packages manually and checks that they run (ZSHSETUP_TEST_PACKAGES overrides the list)
. "${ZSHSETUP_TEST_REPO:-/zshsetup}/tests/lib.sh"
setup_zshsetup
export ZSHSETUP_CHOICE=manual

if [ -e /etc/ssl/certs/ca-certificates.crt ] || [ -e /etc/ssl/cert.pem ]; then
  echo "  info  CA certificates present"
else
  echo "  info  no CA certificates"
fi
for p in ${ZSHSETUP_TEST_PACKAGES:-curl jq uv bat python3 git uvc bun}; do
  case "$p" in
    uvc) arg=--help ;;
    *) arg=--version ;;
  esac
  check "$p installs and runs" sh -c "'$ZSHSETUP_HOME/packages/$p.sh' install && '$p' $arg"
done

finish
