#!/usr/bin/env bash
# Проверяет APK по тем же признакам, по которым его отклоняет RuStore.
# Использование: ./check-release-apk.sh [путь-к-apk]
set -uo pipefail

APK="${1:-app/build/outputs/apk/release/app-release.apk}"
SDK="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
BT="$(ls -d "$SDK"/build-tools/* 2>/dev/null | sort -V | tail -1)"

if [ ! -f "$APK" ]; then echo "❌ Файл не найден: $APK"; exit 1; fi
if [ -z "$BT" ]; then echo "❌ Не найден build-tools в $SDK"; exit 1; fi

echo "Проверяю: $APK"
echo "Размер:   $(du -h "$APK" | cut -f1)"
echo

BADGING="$("$BT/aapt" dump badging "$APK" 2>/dev/null)"
CERTS="$("$BT/apksigner" verify --print-certs -v "$APK" 2>/dev/null)"
FAIL=0

echo "$BADGING" | grep -E "^package:" | sed 's/^/  /'
echo

# 1. Флаг отладки — главная причина отказа RuStore
if echo "$BADGING" | grep -q "^application-debuggable"; then
  echo "❌ debuggable: ВКЛЮЧЁН — это дебаг-сборка, RuStore её отклонит"
  FAIL=1
else
  echo "✅ debuggable: выключен"
fi

# 2. Сертификат подписи
if echo "$CERTS" | grep -q "CN=Android Debug"; then
  echo "❌ подпись:    отладочный ключ Android Debug — RuStore её отклонит"
  FAIL=1
elif echo "$CERTS" | grep -q "^Verifies"; then
  echo "✅ подпись:    $(echo "$CERTS" | grep 'certificate DN:' | head -1 | sed 's/.*certificate DN: //')"
  echo "$CERTS" | grep -E "^Verified using v[0-9.]+ scheme" | sed 's/^/   /'
else
  echo "❌ подпись:    APK не подписан или подпись не проходит проверку"
  FAIL=1
fi

echo
if [ "$FAIL" -eq 0 ]; then
  echo "✅ Готово к загрузке в RuStore"
else
  echo "❌ Загружать нельзя — см. пункты выше"
fi
exit "$FAIL"
