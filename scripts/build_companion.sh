#!/usr/bin/env bash
# 可复现地打包 Host Companion：dist/companion/huanhermes-host-<version>.tar.gz
# 原生 App 构建（apps/android :app:bundleCompanion）会以 HH_COMPANION_OUT 调用本脚本并打进 assets。
#
# 用法：scripts/build_companion.sh <version> [YYYY-MM-DD]
#   - 内容：git 跟踪的 server/ 文件（不含 __pycache__ 与未跟踪文件），根目录为 huanhermes-host-<version>/server/
#   - 格式：GNU tar，按名称排序，owner/group 0/0，文件 0644、目录 0755，统一 mtime（默认当天 00:00 UTC）
#   - 压缩：gzip -n -6（不写入文件名与时间戳）
# 相同输入 + 相同日期 => 相同 sha256（已用该流程复现 0.1.203 的 bd755aa0…7528）。
set -euo pipefail

version="${1:?usage: build_companion.sh <version> [YYYY-MM-DD]}"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "bad version: $version" >&2; exit 1; }
day="${2:-$(date -u +%F)}"
mtime="$(date -u -d "$day 00:00:00" +%s)"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
out="${HH_COMPANION_OUT:-$ROOT/dist/companion}/huanhermes-host-$version.tar.gz"
mkdir -p "$(dirname "$out")"
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT

top="huanhermes-host-$version"
mkdir -p "$stage/$top"
(cd "$ROOT" && git ls-files -z server) | while IFS= read -r -d '' path; do
  case "$path" in */__pycache__/*) continue ;; esac
  mkdir -p "$stage/$top/$(dirname "$path")"
  cp "$ROOT/$path" "$stage/$top/$path"
done
find "$stage/$top" -type d -exec chmod 0755 {} +
find "$stage/$top" -type f -exec chmod 0644 {} +

tar -C "$stage" --sort=name --owner=0 --group=0 --numeric-owner \
  --mtime="@$mtime" --format=gnu -cf - "$top/server" | gzip -n -6 > "$out"

if tar -xzOf "$out" | grep -a -n -E 'BEGIN (RSA|OPENSSH|EC|PRIVATE) KEY|gh[pousr]_[A-Za-z0-9_]{20,}' >/dev/null; then
  echo "Companion archive contains a secret-like value" >&2
  rm -f "$out"
  exit 1
fi

echo "$out"
sha256sum "$out" | awk '{print $1}'
