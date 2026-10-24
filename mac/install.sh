#!/usr/bin/env bash
# Собирает Release-версию KotaTask для macOS и кладёт её в ~/Applications.
# Использование: ./install.sh            — собрать и установить
#                ./install.sh --open     — то же и сразу запустить
set -euo pipefail
cd "$(dirname "$0")"

command -v xcodegen >/dev/null || { echo "Нужен XcodeGen: brew install xcodegen"; exit 1; }

xcodegen generate --quiet
xcodebuild build \
  -project KotaTaskMac.xcodeproj \
  -scheme KotaTaskMac \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath build/DerivedData \
  -quiet

APP="build/DerivedData/Build/Products/Release/KotaTask.app"
DEST="$HOME/Applications"
mkdir -p "$DEST"
# Закрываем запущенную копию, чтобы заменить бандл; данные при этом сохраняются.
osascript -e 'tell application id "ru.kotadevelopment.kotatask.mac" to quit' >/dev/null 2>&1 || true
# quit асинхронный: ждём выхода, иначе open попадёт в закрывающийся процесс (ошибка -600).
for _ in $(seq 1 50); do
  pgrep -f "$DEST/KotaTask.app/Contents/MacOS/KotaTask" >/dev/null || break
  sleep 0.1
done
rm -rf "$DEST/KotaTask.app"
cp -R "$APP" "$DEST/"
echo "✅ Установлено: $DEST/KotaTask.app"
echo "   Данные: ~/Library/Application Support/KotaTask/"

if [[ "${1:-}" == "--open" ]]; then open "$DEST/KotaTask.app"; fi
