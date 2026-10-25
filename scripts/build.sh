#!/bin/zsh
# Compila e empacota o Dose.app em build/ (sem precisar do Xcode).
# Uso: scripts/build.sh [release|debug] [--run] [--dist]
#   --dist  build universal (Apple Silicon + Intel) e zip em dist/ pra publicar no GitHub
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG=release
RUN=0
DIST=0
for arg in "$@"; do
  case $arg in
    debug|release) CONFIG=$arg ;;
    --run) RUN=1 ;;
    --dist) DIST=1 ;;
  esac
done

# A permissão de notificações e o item de login ficam presos à assinatura; o NeyHub (plugin) e as atualizações
# conferem este certificado fixo (scripts/setup-signing.sh, o mesmo do Aero). Sem ele não há fallback ad-hoc.
IDENTITY="Aero Local Signing"
# here-string, não pipe: com pipefail o grep -q saindo cedo pode dar SIGPIPE no security.
IDENTS=$(security find-identity -p codesigning)
if ! grep -q "$IDENTITY" <<<"$IDENTS"; then
  echo "✗ sem a identidade \"$IDENTITY\": rode scripts/setup-signing.sh" >&2
  exit 1
fi

ARCHS=()
(( DIST )) && ARCHS=(--arch arm64 --arch x86_64)
swift build -c "$CONFIG" "${ARCHS[@]}"
BIN="$(swift build -c "$CONFIG" "${ARCHS[@]}" --show-bin-path)/Dose"

APP=build/Dose.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Dose"
cp Resources/Info.plist "$APP/Contents/Info.plist"
[[ -f Resources/AppIcon.icns ]] && cp Resources/AppIcon.icns "$APP/Contents/Resources/"

codesign --force --sign "$IDENTITY" --timestamp=none "$APP"
echo "✓ $APP"

if (( DIST )); then
  VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
  mkdir -p dist
  rm -f "dist/Dose-$VERSION.zip"
  ditto -c -k --norsrc --keepParent "$APP" "dist/Dose-$VERSION.zip"
  echo "✓ dist/Dose-$VERSION.zip"
fi

if (( RUN )); then
  pkill -x Dose 2>/dev/null || true
  while pgrep -x Dose >/dev/null; do sleep 0.2; done
  open -n "$APP"
fi
