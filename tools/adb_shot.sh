#!/usr/bin/env bash
# Usage: tools/adb_shot.sh <name> [tap X Y | text STR | key CODE | swipe X1 Y1 X2 Y2]...  (coords in device px)
ADB="$LOCALAPPDATA/Android/Sdk/platform-tools/adb.exe"
name=$1; shift
while [ $# -gt 0 ]; do
  case $1 in
    tap) "$ADB" shell input tap $2 $3; shift 3;;
    text) "$ADB" shell input text "$2"; shift 2;;
    key) "$ADB" shell input keyevent $2; shift 2;;
    swipe) "$ADB" shell input swipe $2 $3 $4 $5 400; shift 5;;
    *) echo "bad arg $1"; exit 1;;
  esac
  sleep 1.5
done
sleep 1
"$ADB" exec-out screencap -p > "$(dirname "$0")/../docs/screenshots/$name.png"
echo saved $name
