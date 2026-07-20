#!/bin/zsh

project_dir="${0:A:h}"
executable="$project_dir/ScreenToChat1.app/Contents/MacOS/ScreenToChat1"
log_file="$HOME/Library/Logs/ScreenToChat1.log"

if pgrep -x ScreenToChat1 >/dev/null; then
    echo "ScreenToChat1 уже работает. Показываю его лог (Ctrl+C — закрыть просмотр):"
    exec tail -n 50 -f "$log_file"
fi

echo "Запускаю ScreenToChat1. Для выхода: ⇧⌘0 или пункт в строке меню."
exec "$executable"
