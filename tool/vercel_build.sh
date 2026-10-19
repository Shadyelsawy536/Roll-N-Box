#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${SUPABASE_URL:-}" ]]; then
  echo "Missing required environment variable: SUPABASE_URL" >&2
  exit 1
fi

if [[ -z "${SUPABASE_PUBLISHABLE_KEY:-}" ]]; then
  echo "Missing required environment variable: SUPABASE_PUBLISHABLE_KEY" >&2
  exit 1
fi

FLUTTER_DIR="/tmp/flutter"

if [[ ! -x "$FLUTTER_DIR/bin/flutter" ]]; then
  echo "Installing Flutter stable SDK..."
  git clone --depth 1 --branch stable https://github.com/flutter/flutter.git "$FLUTTER_DIR"
fi

export PATH="$FLUTTER_DIR/bin:$PATH"
export CI=true

flutter --version
flutter config --enable-web
flutter precache --web
flutter pub get
dart run flutter_launcher_icons

flutter build web --release \
  --dart-define="SUPABASE_URL=$SUPABASE_URL" \
  --dart-define="SUPABASE_PUBLISHABLE_KEY=$SUPABASE_PUBLISHABLE_KEY"

test -f build/web/index.html
echo "Roll N Box Flutter Web build completed."
