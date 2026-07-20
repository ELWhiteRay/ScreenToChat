#!/bin/zsh

project_dir="${0:A:h}"
chatgpt_app="/Applications/ChatGPT.app"
screen_to_chat="$project_dir/ScreenToChat1.app"

fail() {
    echo
    echo "Ошибка: $1"
    read -r "?Нажмите Enter, чтобы закрыть Terminal…"
    exit 1
}

[[ -x "$chatgpt_app/Contents/MacOS/ChatGPT" ]] || fail "ChatGPT не найден в папке Applications."
[[ -d "$screen_to_chat" ]] || fail "ScreenToChat1.app не найден рядом с этим файлом."

echo "1/3 — закрываю ChatGPT…"
pkill -x ScreenToChat1 >/dev/null 2>&1 || true
osascript -e 'tell application id "com.openai.codex" to quit' >/dev/null 2>&1 || true

for _ in {1..40}; do
    pgrep -x ChatGPT >/dev/null || break
    sleep 0.25
done
pgrep -x ChatGPT >/dev/null && fail "ChatGPT не завершился. Закройте его вручную и запустите этот файл ещё раз."

echo "2/3 — запускаю ChatGPT с локальной автоматизацией…"
open -na "$chatgpt_app" --args \
    --force-renderer-accessibility=complete \
    --remote-debugging-address=127.0.0.1 \
    --remote-debugging-port=9222 \
    --remote-allow-origins='*' || fail "Не удалось запустить ChatGPT."

for _ in {1..40}; do
    pgrep -x ChatGPT >/dev/null && break
    sleep 0.25
done
pgrep -x ChatGPT >/dev/null || fail "ChatGPT не запустился за 10 секунд."

for _ in {1..40}; do
    curl --silent --fail --max-time 1 http://127.0.0.1:9222/json/version >/dev/null && break
    sleep 0.25
done
curl --silent --fail --max-time 1 http://127.0.0.1:9222/json/version >/dev/null \
    || fail "ChatGPT не открыл локальный DevTools-порт 9222."

echo "3/3 — запускаю ScreenToChat1…"
open "$screen_to_chat" || fail "Не удалось запустить ScreenToChat1."

echo
echo "Готово. Откройте нужный чат и нажмите Shift + Command + 9."
echo "Для закрытия ScreenToChat1: Shift + Command + 0 (ноль)."
read -r "?Нажмите Enter, чтобы закрыть Terminal…"
