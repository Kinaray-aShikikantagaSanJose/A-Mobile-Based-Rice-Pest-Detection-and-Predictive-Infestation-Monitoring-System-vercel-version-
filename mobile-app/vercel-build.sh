#!/usr/bin/env bash
# Builds the Palay Patrol Flutter web app on Vercel (Root Directory = mobile-app).
#
#   bash vercel-build.sh install   # Vercel "Install Command": Flutter SDK + pub get
#   bash vercel-build.sh build     # Vercel "Build Command": flutter build web -> build/web
#
# Needs the environment variable API_URL (the deployed FastAPI backend, e.g.
# https://rice-pest-api.vercel.app). It is compiled into the app.
#
# web/sqlite3.wasm and web/sqflite_sw.js are committed, so
# `dart run sqflite_common_ffi_web:setup` is NOT needed here. If you upgrade
# sqflite_common_ffi_web, run that setup locally again and commit the files.
set -euo pipefail

FLUTTER_VERSION="${FLUTTER_VERSION:-3.47.1}"
FLUTTER_HOME="${FLUTTER_HOME:-$HOME/flutter-sdk}"
export PATH="$FLUTTER_HOME/bin:$PATH"
export CI=true
export PUB_CACHE="${PUB_CACHE:-$HOME/.pub-cache}"

cd "$(dirname "$0")"

install_flutter() {
  if [ ! -x "$FLUTTER_HOME/bin/flutter" ]; then
    # Flutter's first run unpacks the Dart SDK with unzip.
    if ! command -v unzip >/dev/null 2>&1; then
      (dnf install -y unzip || yum install -y unzip) >/dev/null 2>&1 || true
    fi
    echo "Cloning Flutter $FLUTTER_VERSION into $FLUTTER_HOME"
    git clone https://github.com/flutter/flutter.git --depth 1 -b "$FLUTTER_VERSION" "$FLUTTER_HOME"
  fi
  flutter --disable-analytics >/dev/null 2>&1 || true
  flutter config --no-analytics >/dev/null 2>&1 || true
  flutter config --enable-web
  flutter --version
}

case "${1:-build}" in
  install)
    install_flutter
    flutter pub get
    ;;
  build)
    if [ -z "${API_URL:-}" ]; then
      echo "ERROR: API_URL is not set." >&2
      echo "Set it in Vercel > Project > Settings > Environment Variables to the" >&2
      echo "HTTPS address of the deployed API (e.g. https://rice-pest-api.vercel.app)." >&2
      exit 1
    fi
    case "$API_URL" in
      https://*) ;;
      *) echo "ERROR: API_URL must start with https:// (got: $API_URL)." >&2; exit 1 ;;
    esac
    # The install step normally ran already; this makes `build` work alone too.
    [ -x "$FLUTTER_HOME/bin/flutter" ] || { install_flutter; flutter pub get; }
    flutter build web --release --dart-define=API_URL="$API_URL"
    ;;
  *)
    echo "usage: bash vercel-build.sh [install|build]" >&2
    exit 2
    ;;
esac
