#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# seed_tasks.sh — Создаёт БД с 4 задачами на хосте и заливает в KotaTask
#
# Стратегия (не зависит от состояния приложения):
#   1. Создать SQLite-файл на хосте с точной схемой Room
#   2. Вставить 4 задачи
#   3. force-stop приложения
#   4. Залить БД через /data/local/tmp + run-as cp
#
# Запуск:
#   chmod +x seed_tasks.sh && ./seed_tasks.sh
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

# ── Инструменты ──────────────────────────────────────────────────────────────
ADB="${HOME}/Library/Android/sdk/platform-tools/adb"
SQLITE3="/usr/bin/sqlite3"
[[ -x "$ADB"     ]] || { echo "❌  adb не найден: $ADB"       >&2; exit 1; }
[[ -x "$SQLITE3" ]] || { echo "❌  sqlite3 не найден на хосте" >&2; exit 1; }

PACKAGE="com.mark.app"
DB_DEVICE="/data/data/${PACKAGE}/databases/mark_db"
TMP_ON_DEVICE="/data/local/tmp/mark_db_seed"

# ── Найти эмулятор ────────────────────────────────────────────────────────────
EMU=$("$ADB" devices | awk '/^emulator-[0-9]+[[:space:]]+device$/{print $1}' | head -1)
[[ -n "$EMU" ]] || { echo "❌  Эмулятор не найден. Запусти его через AVD Manager." >&2; exit 1; }
echo "📱  Эмулятор: ${EMU}"
A="$ADB -s $EMU"

# ── 1. Создать БД на хосте ────────────────────────────────────────────────────
TMP_LOCAL=$(mktemp /tmp/mark_db_XXXXXX.sqlite)
trap 'rm -f "$TMP_LOCAL"' EXIT

echo "🔨  Создаю БД на хосте..."

"$SQLITE3" "$TMP_LOCAL" "
-- Таблица задач (точная схема из Room AppDatabase_Impl)
CREATE TABLE IF NOT EXISTS \`tasks\` (
  \`id\`         TEXT    NOT NULL,
  \`title\`      TEXT    NOT NULL,
  \`deadline\`   TEXT    NOT NULL,
  \`parent\`     TEXT    NOT NULL,
  \`purpose\`    TEXT    NOT NULL,
  \`duration\`   INTEGER NOT NULL,
  \`importance\` TEXT    NOT NULL,
  \`status\`     TEXT    NOT NULL,
  \`assignee\`   TEXT    NOT NULL,
  \`created\`    INTEGER NOT NULL,
  \`completed\`  INTEGER NOT NULL,
  PRIMARY KEY(\`id\`)
);

-- Служебная таблица Room (identity_hash должен совпадать с AppDatabase_Impl)
CREATE TABLE IF NOT EXISTS room_master_table (
  id INTEGER PRIMARY KEY,
  identity_hash TEXT
);
INSERT OR REPLACE INTO room_master_table (id, identity_hash)
VALUES (42, 'a5e0e33629b099eb6baeace76f23be5f');
"

echo "    Схема создана."

# ── 2. Вставить задачи ────────────────────────────────────────────────────────
TODAY=$(date +%Y-%m-%d)
NOW_MS=$(( $(date +%s) * 1000 ))

declare -a TASKS=(
  "Написать отчёт за неделю|Высокая|90"
  "Прочитать главу книги|Средняя|45"
  "Подготовить презентацию|Высокая|120"
  "Разобрать входящие письма|Низкая|20"
)

echo ""
echo "✏️   Вставляю задачи..."

for entry in "${TASKS[@]}"; do
  IFS='|' read -r TITLE IMPORTANCE DURATION <<< "$entry"
  ID=$(uuidgen | tr '[:upper:]' '[:lower:]')

  "$SQLITE3" "$TMP_LOCAL" \
    "INSERT INTO tasks
       (id, title, deadline, parent, purpose, duration, importance, status, assignee, created, completed)
     VALUES
       ('${ID}', '${TITLE}', '${TODAY}', '', '', ${DURATION}, '${IMPORTANCE}', 'Сегодня', '', ${NOW_MS}, 0);"

  echo "  ✅  \"${TITLE}\" | ${IMPORTANCE} | ${DURATION} мин"
done

echo "    БД: $(wc -c < "$TMP_LOCAL") байт"

# ── 3. Force-stop приложения ──────────────────────────────────────────────────
echo ""
echo "⏹   Останавливаю приложение..."
$A shell am force-stop "$PACKAGE"
sleep 1

# ── 4. Залить БД на устройство ───────────────────────────────────────────────
echo "📤  Заливаю БД на устройство..."

# 4a. push в /data/local/tmp (доступно без root)
$A push "$TMP_LOCAL" "$TMP_ON_DEVICE" > /dev/null

# 4b. Создать папку databases если нет (первый запуск)
$A shell "run-as ${PACKAGE} mkdir -p '/data/data/${PACKAGE}/databases'"

# 4c. Скопировать в приватный каталог приложения
$A shell "run-as ${PACKAGE} cp '${TMP_ON_DEVICE}' '${DB_DEVICE}'"

# 4d. Удалить устаревшие WAL/SHM (на всякий случай)
$A shell "run-as ${PACKAGE} rm -f '${DB_DEVICE}-wal' '${DB_DEVICE}-shm'" 2>/dev/null || true

# 4e. Почистить /data/local/tmp
$A shell "rm -f '${TMP_ON_DEVICE}'" 2>/dev/null || true

echo ""
echo "🎉  Готово! Открой KotaTask → вкладка «Сегодня»."
