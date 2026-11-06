#!/bin/bash
# Подключает остров к Claude Code: добавляет хуки в ~/.claude/settings.json (с резервной копией).
# Хуки NotchBuddy и другие не трогает. Повторный запуск ничего не дублирует.
set -e
P="$HOME/.claude/settings.json"
[ -f "$P" ] && cp "$P" "$P.bak-island"
python3 - "$P" <<'PY'
import json, os, sys
p = sys.argv[1]
s = json.load(open(p)) if os.path.exists(p) else {}
b = '$HOME/Applications/Island.app/Contents/MacOS/Island'
cmd = f'[ -x "{b}" ] && "{b}" hook || true'
hooks = s.setdefault("hooks", {})
for ev in ["UserPromptSubmit", "PreToolUse", "Stop", "Notification", "SessionEnd"]:
    arr = hooks.setdefault(ev, [])
    if not any(h.get("command") == cmd for e in arr for h in e.get("hooks", [])):
        arr.append({"hooks": [{"type": "command", "command": cmd, "timeout": 5}]})
json.dump(s, open(p, "w"), indent=2, ensure_ascii=False)
print("OK хуки острова добавлены в", p)
PY
