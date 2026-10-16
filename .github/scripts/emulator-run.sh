#!/usr/bin/env bash
# Runs inside android-emulator-runner. Never fails the step itself: results are judged
# from the junit xml after screenshots/logs are collected.
set -u
OUT="$RUNNER_TEMP/emu-out"; mkdir -p "$OUT"
adb logcat -c || true
adb shell settings put global window_animation_scale 0
adb shell settings put global transition_animation_scale 0
adb shell settings put global animator_duration_scale 0

# 1) Release APK smoke: the minified build must start without crashing.
adb install -r apps/android/app/build/outputs/apk/release/app-release.apk > "$OUT/release-install.txt" 2>&1
adb shell am start -W -n com.huanmeng.huanhermes/.MainActivity >> "$OUT/release-install.txt" 2>&1
sleep 10
adb exec-out screencap -p > "$OUT/release-launch.png" || true
if adb shell pidof com.huanmeng.huanhermes > /dev/null; then echo "release_alive=yes" >> "$OUT/summary.txt"; else echo "release_alive=NO" >> "$OUT/summary.txt"; fi
adb shell am force-stop com.huanmeng.huanhermes || true

# 2) Instrumented UI flow against mock-host (debug variant, .debug id).
(cd apps/android && gradle --no-daemon :app:connectedDebugAndroidTest) > "$OUT/connected.log" 2>&1
echo "connected_rc=$?" >> "$OUT/summary.txt"

adb logcat -d > "$OUT/logcat.txt" 2>&1 || true
grep -n -A30 "FATAL EXCEPTION" "$OUT/logcat.txt" > "$OUT/crashes.txt" || true
adb pull /sdcard/googletest/test_outputfiles "$OUT/shots-device" > /dev/null 2>&1 || true
exit 0
