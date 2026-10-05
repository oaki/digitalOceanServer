#!/usr/bin/env bash
# Pull, build, and restart the already-provisioned private video-call service.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source lib.sh

VIDEO_CALL_REPO="${VIDEO_CALL_REPO:-$REPO_ROOT/../videocall}"
APK_PATH="${VIDEO_CALL_APK_PATH:-$VIDEO_CALL_REPO/apps/android/app/build/outputs/apk/debug/app-debug.apk}"

if [[ ! -f "$APK_PATH" ]]; then
  echo "Missing Android APK: $APK_PATH" >&2
  echo "Build it with apps/android/gradlew -p apps/android assembleDebug" >&2
  exit 1
fi

echo "==> Publishing bintonin Android APK"
scp_to_droplet "$APK_PATH" "/tmp/bintonin.apk.upload"
ssh_run "install -d -m 0755 /opt/apps/videocall/releases && install -m 0644 /tmp/bintonin.apk.upload /opt/apps/videocall/releases/bintonin.apk && rm -f /tmp/bintonin.apk.upload"

ssh_run "cd /opt/apps/videocall && git pull --ff-only origin main && ./infra/production/build-and-restart.sh"
ssh_run "curl -fsS http://127.0.0.1:3005/health && curl -fsSI http://127.0.0.1:3006/ >/dev/null && systemctl is-active videocall-livekit"

echo "==> Deployed and verified: https://call.contexthub.uk"
