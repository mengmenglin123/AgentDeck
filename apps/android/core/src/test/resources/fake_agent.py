"""JSONL fixture agent for native end-to-end tests against the production Host."""
import json
import sys
import time


def emit(**event):
    print(json.dumps(event, ensure_ascii=False), flush=True)


for raw in sys.stdin:
    line = raw.strip()
    if not line:
        continue
    if line.startswith("{"):
        try:
            msg = json.loads(line)
        except ValueError:
            continue
        if msg.get("type") == "permission_response":
            emit(type="text_delta", text="decision=" + str(msg.get("decision")), done=True)
            emit(type="done")
        continue
    if line == "perm":
        emit(type="permission", content="允许删除 build/？", scope="fs.write")
        continue
    if line == "slow":
        emit(type="text_delta", text="first ")
        time.sleep(1.5)
        emit(type="text_delta", text="second", done=True)
        emit(type="done")
        continue
    emit(type="thinking", content="想一想")
    emit(type="tool_call", name="bash", input="ls")
    emit(type="tool_result", name="bash", output="README.md")
    emit(type="text_delta", text="你好，")
    emit(type="text_delta", text=line, done=True)
    emit(type="done")
