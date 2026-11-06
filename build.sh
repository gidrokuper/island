#!/bin/bash
# Сборка Island.app:
#   bash build.sh            — собрать в build/
#   bash build.sh --run      — собрать и запустить отсюда
#   bash build.sh --install  — поставить в ~/Applications и запустить
set -e
cd "$(dirname "$0")"
swift build -c release
APP=build/Island.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Island "$APP/Contents/MacOS/Island"
cp Info.plist "$APP/Contents/Info.plist"
cp icon/Island.icns "$APP/Contents/Resources/Island.icns"
# Подпись постоянным локальным сертификатом «Island Local Signing» (связка «вход»):
# macOS узнаёт остров по сертификату, и «Полный доступ к диску» не слетает после пересборки.
# Если сертификата нет — подпись без него (доступ придётся включать заново после каждой сборки).
ID=$(security find-identity -p codesigning 2>/dev/null | awk '/"Island Local Signing"/{print $2; exit}')
codesign --force --sign "${ID:--}" --identifier local.gaad.island "$APP" >/dev/null
[ -n "$ID" ] && echo "SIGNED Island Local Signing" || echo "SIGNED ad-hoc"
echo "OK $(pwd)/$APP"

case "$1" in
  --run)
    pkill -x Island 2>/dev/null || true; sleep 0.3
    open "$APP" ;;
  --install)
    DEST="$HOME/Applications/Island.app"
    pkill -x Island 2>/dev/null || true; sleep 0.3
    mkdir -p "$HOME/Applications"
    rm -rf "$DEST"
    cp -R "$APP" "$DEST"
    touch "$DEST"
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DEST" >/dev/null 2>&1 || true
    open "$DEST"
    echo "INSTALLED $DEST" ;;
esac
