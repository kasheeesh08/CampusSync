"""Lists the reminders CampusSync has scheduled on a connected debug device.

Reads flutter_local_notifications' persisted schedule (debug builds only, via
`run-as`) so reminder behaviour can be verified on the device itself.
Usage: python -I tools/reminders_check.py [label]
"""
import html, json, os, re, subprocess, sys
from collections import Counter

ADB = os.path.join(os.environ.get("LOCALAPPDATA", ""), "Android", "Sdk", "platform-tools", "adb.exe")
xml = subprocess.run([ADB, "shell", "run-as", "com.campussync.campussync", "cat", "shared_prefs/scheduled_notifications.xml"],
                     capture_output=True, text=True, encoding="utf-8").stdout
m = re.search(r'<string name="scheduled_notifications">(.*?)</string>', xml, re.S)
items = json.loads(html.unescape(m.group(1))) if m else []
label = sys.argv[1] if len(sys.argv) > 1 else "snapshot"
rows = []
for n in items:
    when = n.get("scheduledDateTime") or n.get("scheduledDateTimeISO8601") or "?"
    rows.append((when, n.get("id"), n.get("title"), n.get("body"), n.get("timeZoneName")))
rows.sort(key=lambda r: str(r[0]))
ids = Counter(r[1] for r in rows)
dups = [i for i, c in ids.items() if c > 1]
kinds = Counter("exam" if (r[2] or "").startswith("Exam tomorrow") else "class" for r in rows)
print(f"[{label}] {len(rows)} scheduled ({dict(kinds)}), duplicate ids: {len(dups)}, timezones: {sorted({str(r[4]) for r in rows})}")
for r in rows:
    if (r[2] or "").startswith("Exam tomorrow") or "-v" in sys.argv:
        print(f"   {r[0]}  {r[2]} - {r[3]}")
