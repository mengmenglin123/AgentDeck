#!/usr/bin/env bash
# 本地一键校验：与 CI 中 Python 门禁保持一致（py_compile + 协议测试 + Host 测试）。
# 可选：传入 --flutter 同时运行 flutter analyze / flutter test（需本机安装 Flutter）。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# 测试只连回环地址；避免宿主环境的 HTTP(S)_PROXY 把 127.0.0.1 请求转发出去。
export NO_PROXY="127.0.0.1,localhost${NO_PROXY:+,$NO_PROXY}"
export no_proxy="$NO_PROXY"

echo "==> py_compile"
python3 -m py_compile server/*.py server/mock-host/mock_host.py \
  packages/huan_protocol/src/*.py packages/huan_protocol/test/*.py

echo "==> protocol tests"
PYTHONPATH=packages/huan_protocol python3 -m unittest discover -s packages/huan_protocol/test

echo "==> host tests"
PYTHONPATH=server PYTHONWARNINGS=error::ResourceWarning \
  python3 -m unittest discover -s server -p 'test_*.py'

if [[ "${1:-}" == "--flutter" ]]; then
  echo "==> flutter analyze / test"
  (cd apps/mobile && flutter pub get && flutter analyze --no-fatal-infos && flutter test)
fi

echo "OK"
