#!/usr/bin/env bash
# shellcheck disable=SC1091
# Build git for THIS host with zig cc, with zlib/OpenSSL/curl linked in statically.
# Also collects git's static libraries (libgit.a, and libgitcore.a from Rust).
#
#   Linux  x86_64 / aarch64 : fully static musl binary (no runtime deps at all)
#   macOS  arm64 / x86_64   : deps static; only libSystem + system frameworks are
#                             dynamic (macOS does not support fully static binaries)
#
# Requirements: zig, GNU make, perl, curl, tar, xz or python3 >= 3.11.4 (Linux).
#   macOS additionally: Xcode Command Line Tools (SDK), GNU make >= 4 (brew install make).
#   Rust (cargo) is only needed with WITH_RUST=1 (installed via rustup if missing). No git needed.
#
# Usage:  ./build-static-git.sh
#         WITH_RUST=1 ./build-static-git.sh     (also build git's optional Rust parts)
#
# Output: $WORK/out/usr/local/{bin,libexec/git-core,share}   git (+ git-remote-https)
#         $WORK/out/lib/libgit.a [libgitcore.a]              static libraries
set -euo pipefail

OS="$(uname -s)"
ARCH="$(uname -m)"
[ "$ARCH" = arm64 ] && ARCH=aarch64
WORK="${WORK:-$PWD/static-git-build}"
PREFIX="$WORK/deps" # static deps (zlib, openssl, curl)
OUT="$WORK/out"     # final git install
JOBS="${JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)}"
WITH_RUST="${WITH_RUST:-0}" # 0 = NO_RUST (default), 1 = build git's Rust parts (needs cargo/rustup)

ZLIB_VER=1.3.1
OPENSSL_VER=3.5.4 # release tarball! OpenSSL master (4.x-dev) breaks curl 8.16
CURL_VER=8.16.0
GIT_VER="${GIT_VER:-2.55.0}"

case "$OS-$ARCH" in
  Linux-x86_64)
    OPENSSL_TARGET=linux-x86_64
    ZIG_TARGET=x86_64-linux-musl
    ;;
  Linux-aarch64)
    OPENSSL_TARGET=linux-aarch64
    ZIG_TARGET=aarch64-linux-musl
    ;;
  Darwin-aarch64)
    OPENSSL_TARGET=darwin64-arm64
    ZIG_TARGET=native
    ;;
  Darwin-x86_64)
    OPENSSL_TARGET=darwin64-x86_64
    ZIG_TARGET=native
    ;;
  *)
    echo "unsupported host $OS-$ARCH" >&2
    exit 1
    ;;
esac
RUST_TARGET="${ARCH}-unknown-linux-musl" # Linux: host rust is -gnu, we need -musl
[ "$OS" = Darwin ] && RUST_TARGET="${ARCH}-apple-darwin"

# GNU make: macOS ships 3.81 as `make`; prefer Homebrew's gmake if present
MAKE="${MAKE:-$(command -v gmake || command -v make)}"
"$MAKE" --version 2>/dev/null | grep -q 'GNU Make' || {
  echo "GNU make required" >&2
  exit 1
}

# zig cc: on Linux target musl explicitly (-> static); on macOS use native so the SDK is found
if [ "$ZIG_TARGET" = native ]; then export CC="zig cc"; else export CC="zig cc -target $ZIG_TARGET"; fi
export AR="zig ar"
export RANLIB="zig ranlib"
# curl/libtool configure fails with "no acceptable ld" on Linux without binutils
[ "$OS" = Linux ] && export LD="zig ld.lld"

mkdir -p "$WORK/src" "$WORK/bin" "$PREFIX/include" "$PREFIX/lib"

# ---- Rust (optional; git >= 2.52 has Rust parts) ----------------------------
if [ "$WITH_RUST" = 1 ]; then
  if ! command -v cargo >/dev/null; then
    [ -f "${CARGO_HOME:-$HOME/.cargo}/env" ] || {
      echo ">>> installing rustup (no git needed, plain https)"
      curl -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal
    }
    . "${CARGO_HOME:-$HOME/.cargo}/env"
  fi
  rustup target add "$RUST_TARGET"
  # cargo links gitcore's build.rs with the host `cc`; use zig if the host has none
  if ! command -v cc >/dev/null; then
    cat >"$WORK/bin/cc" <<'EOF'
#!/bin/sh
# host "cc" for cargo build scripts: zig cc, minus flags zig/lld reject
for a do
    shift
    case "$a" in
        -Wl,--fix-cortex-a53-843419) ;;
        *) set -- "$@" "$a" ;;
    esac
done
exec zig cc "$@"
EOF
    chmod +x "$WORK/bin/cc"
    export PATH="$WORK/bin:$PATH"
  fi
fi

cd "$WORK/src"

fetch() { # url dir   (download to file: GNU tar can't sniff xz from a pipe, bsdtar can do both)
  [ -d "$2" ] && return
  echo ">>> fetching $1"
  curl -sSL -o "${1##*/}" "$1"
  case "$1" in
    # no xz-utils: GNU tar can't decompress .xz itself, so let python do it
    *.xz) if command -v xz >/dev/null; then
      tar xf "${1##*/}"
    else python3 -m tarfile --filter data -e "${1##*/}" .; fi ;;
    *) tar xf "${1##*/}" ;;
  esac
}

fetch "https://github.com/madler/zlib/releases/download/v$ZLIB_VER/zlib-$ZLIB_VER.tar.gz" "zlib-$ZLIB_VER"
fetch "https://github.com/openssl/openssl/releases/download/openssl-$OPENSSL_VER/openssl-$OPENSSL_VER.tar.gz" "openssl-$OPENSSL_VER"
fetch "https://curl.se/download/curl-$CURL_VER.tar.xz" "curl-$CURL_VER"
fetch "https://www.kernel.org/pub/software/scm/git/git-$GIT_VER.tar.xz" "git-$GIT_VER"

# ---- zlib -------------------------------------------------------------------
echo ">>> zlib"
(
  cd "zlib-$ZLIB_VER"
  ./configure --static --prefix="$PREFIX"
  "$MAKE" -j"$JOBS"
  "$MAKE" install
)

# ---- OpenSSL ----------------------------------------------------------------
# CC must be passed as a Configure argument (env CC alone is not picked up reliably),
# no-asm avoids perlasm output that zig's assembler chokes on.
# no-module: build providers into libcrypto; otherwise legacy.dylib is linked with
# -bundle, which zig cc on macOS ignores ("undefined symbol: _main").
# --openssldir=/etc/ssl: default CA location on Linux distros (macOS: set SSL_CERT_FILE
# or git config http.sslCAInfo, e.g. /etc/ssl/cert.pem which macOS provides).
echo ">>> openssl"
(
  cd "openssl-$OPENSSL_VER"
  ./Configure "$OPENSSL_TARGET" \
    no-shared no-module no-asm no-tests no-docs \
    --prefix="$PREFIX" --libdir=lib --openssldir=/etc/ssl \
    CC="$CC" AR="$AR" RANLIB="$RANLIB"
  "$MAKE" -j"$JOBS"
  "$MAKE" install_sw
)

# ---- curl -------------------------------------------------------------------
echo ">>> curl"
(
  cd "curl-$CURL_VER"
  ./configure \
    --prefix="$PREFIX" \
    --disable-shared --enable-static \
    --with-openssl="$PREFIX" --with-zlib="$PREFIX" \
    --with-ca-fallback --without-ca-bundle --without-ca-path \
    --disable-ldap --disable-ldaps --disable-rtsp --disable-dict \
    --disable-telnet --disable-tftp --disable-pop3 --disable-imap \
    --disable-smb --disable-smtp --disable-gopher --disable-mqtt \
    --disable-manual --disable-docs \
    --without-libpsl --without-libidn2 --without-libssh2 --without-libgsasl \
    --without-nghttp2 --without-nghttp3 --without-ngtcp2 \
    --without-brotli --without-zstd
  "$MAKE" -j"$JOBS"
  "$MAKE" install
)

# ---- git --------------------------------------------------------------------
echo ">>> git"
GIT_MAKE_ARGS=(
  CC="$CC" AR="$AR" RANLIB="$RANLIB"
  CFLAGS="-Os -I$PREFIX/include"
  prefix=/usr/local
  RUNTIME_PREFIX=YesPlease # relocatable: finds libexec relative to the binary
  ZLIB_PATH="$PREFIX"
  OPENSSLDIR="$PREFIX"
  CURLDIR="$PREFIX"
  CURL_CONFIG="$PREFIX/bin/curl-config"
  CURL_LDFLAGS="$("$PREFIX/bin/curl-config" --static-libs)" # incl. ssl/crypto/z (+ frameworks on macOS)
  NO_EXPAT=YesPlease NO_GETTEXT=YesPlease NO_PERL=YesPlease
  NO_PYTHON=YesPlease NO_TCLTK=YesPlease
  NO_INSTALL_HARDLINKS=YesPlease
  INSTALL_SYMLINKS=YesPlease # libexec/git-core/* -> symlinks to git instead of 3.5 MB copies
  LINK_FUZZ_PROGRAMS=        # config.mak.uname enables it on Linux; lld rejects its flags
)
if [ "$OS" = Linux ]; then
  LDFLAGS="-static -L$PREFIX/lib"                     # (no -s needed: zig cc emits no symtab/debug info without -g)
  GIT_MAKE_ARGS+=(NO_REGEX=NeedsStartEnd)             # musl regex lacks REG_STARTEND; use git's compat regex
  [ "$WITH_RUST" = 1 ] && LDFLAGS="$LDFLAGS -lunwind" # Rust std needs _Unwind_*; zig ships libunwind
else
  LDFLAGS="-L$PREFIX/lib" # only .a files there, so deps link statically
  GIT_MAKE_ARGS+=(
    USE_HOMEBREW_LIBICONV= NEEDS_GOOD_LIBICONV= # macOS 15+ defaults to Homebrew libiconv; use system
    LD_MAJOR_VERSION=                           # skip Xcode-ld-only flags zig's linker may reject
  )
fi
GIT_MAKE_ARGS+=(LDFLAGS="$LDFLAGS")
if [ "$WITH_RUST" = 1 ]; then
  GIT_MAKE_ARGS+=(
    CARGO_ARGS="--release --target $RUST_TARGET"
    RUST_LIB="target/$RUST_TARGET/release/libgitcore.a"
  )
else
  GIT_MAKE_ARGS+=(NO_RUST=YesPlease)
fi
(
  cd "git-$GIT_VER"
  "$MAKE" -j"$JOBS" "${GIT_MAKE_ARGS[@]}" all
  rm -rf "$OUT"
  "$MAKE" "${GIT_MAKE_ARGS[@]}" DESTDIR="$OUT" install
  # client-only: git has no switches to skip these, so drop them after install
  #   imap-send (patch mailing via IMAP), http-fetch (dumb-http/packfile-uri helper),
  #   daemon + http-backend + git-shell (server side), scalar (large-repo manager)
  for p in git-imap-send git-http-fetch git-daemon git-http-backend git-shell scalar; do
    rm -f "$OUT/usr/local/libexec/git-core/$p" "$OUT/usr/local/bin/$p"
  done
  # static libraries (xdiff + reftable are part of libgit.a since 2.5x)
  mkdir -p "$OUT/lib"
  cp libgit.a "$OUT/lib/"
  if [ "$WITH_RUST" = 1 ]; then cp "target/$RUST_TARGET/release/libgitcore.a" "$OUT/lib/"; fi
)

# ---- check ------------------------------------------------------------------
GIT_BIN="$OUT/usr/local/bin/git"
echo
echo ">>> done: $GIT_BIN"
"$GIT_BIN" --version
if [ "$OS" = Linux ]; then
  if LC_ALL=C grep -a -q -E '/lib/ld-(linux|musl)' "$GIT_BIN"; then
    echo "WARNING: git references a dynamic loader, not fully static" >&2
  else
    echo "fully static"
  fi
else
  otool -L "$GIT_BIN" "$OUT/usr/local/libexec/git-core/git-remote-https" # expect only /usr/lib + /System
fi
ls -la "$OUT/lib"
