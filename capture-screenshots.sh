#!/usr/bin/env bash
# Capture Android Settings screenshots on a booted emulator.
#
# WHY THIS IS A SEPARATE FILE (do not inline it into the workflow):
#   reactivecircus/android-emulator-runner splits its `script:` input into
#   SINGLE LINES and runs each line separately with `sh -c`
#   (see its src/script-parser.ts + src/main.ts). A multi-line for-loop,
#   if-block or any other multi-line construct therefore breaks with
#   "/usr/bin/sh: Syntax error: end of file unexpected (expecting "done")".
#   So the workflow's `script:` is just one line — `bash capture-screenshots.sh`
#   — and all the logic lives here, where bash runs it as one script.
#
# INPUT: env var SCREENS (comma-separated name:intent pairs). The workflow
# passes the `screens` workflow_dispatch input through; when empty
# (scheduled runs), the default list below is used.
set -e
mkdir -p screenshots
adb wait-for-device
adb shell input keyevent 82 || true   # dismiss lock screen, if any
sleep 2

SCREENS="${SCREENS:-settings:android.settings.SETTINGS,battery:android.settings.BATTERY_SETTINGS,storage:android.settings.INTERNAL_STORAGE_SETTINGS,wifi:android.settings.WIFI_SETTINGS,apps:android.settings.APPLICATION_SETTINGS,display:android.settings.DISPLAY_SETTINGS,sound:android.settings.SOUND_SETTINGS,security:android.settings.SECURITY_SETTINGS,about:android.settings.DEVICE_INFO_SETTINGS}"
echo "Capturing: $SCREENS"
COUNT=0
# Split "name:intent,name:intent,..." on commas.
OLD_IFS="$IFS"; IFS=','
for PAIR in $SCREENS; do
  IFS="$OLD_IFS"
  NAME="${PAIR%%:*}"
  INTENT="${PAIR#*:}"
  echo "--- $NAME  ($INTENT)"
  # Open the Settings screen, wait for it to settle, shoot it.
  # Battery is special: the BATTERY_SETTINGS intent does not resolve on
  # this emulator (run 2 captured the Settings home instead), so launch
  # its activity component directly.
  if [ "$NAME" = "battery" ]; then
    adb shell am start -n 'com.android.settings/.Settings$PowerUsageSummaryActivity' || echo "::warning::am start failed for $NAME"
  else
    adb shell am start -a "$INTENT" || echo "::warning::am start failed for $NAME ($INTENT)"
  fi
  sleep 4
  adb exec-out screencap -p > "screenshots/${NAME}.png"
  SIZE=$(stat -c%s "screenshots/${NAME}.png" || echo 0)
  echo "$NAME.png = ${SIZE} bytes"
  # A real 1080x2400 PNG is hundreds of KB; <10 KB = blank/failed.
  if [ "$SIZE" -lt 10000 ]; then
    echo "::warning::$NAME.png is suspiciously small (${SIZE} bytes) — screen may not have opened"
    rm -f "screenshots/${NAME}.png"
  elif [ "$NAME" != "settings" ] && cmp -s "screenshots/${NAME}.png" screenshots/settings.png; then
    echo "::warning::$NAME.png is identical to settings.png — the screen did not open; deleting it"
    rm -f "screenshots/${NAME}.png"
  else
    COUNT=$((COUNT + 1))
  fi
  IFS=','
done
IFS="$OLD_IFS"
echo "Captured $COUNT screenshot(s):"
ls -lh screenshots/
if [ "$COUNT" -eq 0 ]; then
  echo "::error::No screenshots captured"
  exit 1
fi
