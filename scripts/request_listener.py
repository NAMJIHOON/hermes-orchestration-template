#!/usr/bin/env python3
"""
scripts/request_listener.py
채널별 업무 요청 수신 → /triage로 라우팅

지원 채널:
  --channel slack     Slack 슬래시 커맨드 or 멘션 (webhook)
  --channel linear    Linear webhook (이슈 생성 이벤트)
  --channel jira      Jira webhook (이슈 생성/업데이트)
  --channel notion    Notion 데이터베이스 폴링
  --channel stdin     직접 입력 (로컬 테스트용)

실행 예:
  python3 scripts/request_listener.py --channel slack --port 3000
  python3 scripts/request_listener.py --channel stdin
"""

import argparse
import json
import os
import subprocess
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import parse_qs, urlparse


# ---------------------------------------------------------------------------
# 핵심: 요청 텍스트 → Claude Code /triage 호출
# ---------------------------------------------------------------------------

def dispatch(request_text: str, source: str = "unknown") -> dict:
    """요청 텍스트를 /triage 슬래시 커맨드로 Claude Code에 넘긴다."""
    print(f"[dispatch] source={source} text={request_text[:80]!r}")

    result = subprocess.run(
        [
            "claude", "-p",
            f"/triage {request_text}",
            "--allowedTools", "Read,Write,Edit,Bash",
            "--max-turns", "30",
        ],
        capture_output=True,
        text=True,
        timeout=600,
        cwd=os.getcwd(),
    )

    output = result.stdout.strip()
    error  = result.stderr.strip()

    log_event(source, request_text, output, result.returncode)

    return {
        "ok":     result.returncode == 0,
        "output": output,
        "error":  error,
    }


def log_event(source: str, request: str, output: str, code: int):
    """작업 이벤트를 Hermes 로그에 기록한다."""
    os.makedirs(".hermes-state", exist_ok=True)
    entry = json.dumps({
        "ts":      __import__("datetime").datetime.utcnow().isoformat() + "Z",
        "source":  source,
        "request": request[:200],
        "exit":    code,
        "output":  output[:500],
    })
    with open(".hermes-state/events.jsonl", "a") as f:
        f.write(entry + "\n")


# ---------------------------------------------------------------------------
# 채널 어댑터
# ---------------------------------------------------------------------------

class SlackHandler(BaseHTTPRequestHandler):
    """Slack 슬래시 커맨드 / app_mention 웹훅 수신."""

    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        body   = self.rfile.read(length).decode()

        # Slack는 application/x-www-form-urlencoded 또는 JSON
        try:
            payload = json.loads(body)
        except Exception:
            payload = {k: v[0] for k, v in parse_qs(body).items()}

        text = (
            payload.get("text")                        # 슬래시 커맨드
            or payload.get("event", {}).get("text", "") # app_mention
        ).strip()

        # 멘션(@봇 이름) 제거
        if text.startswith("<@"):
            text = text.split(">", 1)[-1].strip()

        if not text:
            self._reply(200, {"text": "요청 내용이 비어 있습니다."})
            return

        # Slack에 즉시 200 OK 반환 (3초 타임아웃 회피)
        self._reply(200, {"text": f"요청 접수: {text[:60]}... 처리 중입니다."})

        # 비동기로 처리 (간단 버전: thread)
        import threading
        def run():
            result = dispatch(text, source="slack")
            # 결과를 response_url로 보낼 수 있지만 여기선 로그만
            print(f"[slack] done ok={result['ok']}")
        threading.Thread(target=run, daemon=True).start()

    def _reply(self, code: int, data: dict):
        body = json.dumps(data).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *_):
        pass  # 기본 로그 억제


class LinearHandler(BaseHTTPRequestHandler):
    """Linear 웹훅 — 이슈 생성 이벤트를 수신한다."""

    def do_POST(self):
        length  = int(self.headers.get("Content-Length", 0))
        payload = json.loads(self.rfile.read(length))

        action = payload.get("action", "")
        issue  = payload.get("data", {})

        if action not in ("create", "update"):
            self._reply(200, {"ok": True})
            return

        title       = issue.get("title", "")
        description = issue.get("description", "")
        labels      = [l.get("name", "") for l in issue.get("labels", [])]

        # "ai-agent" 라벨이 있는 이슈만 처리
        if "ai-agent" not in labels:
            self._reply(200, {"ok": True, "skipped": "no ai-agent label"})
            return

        text = f"{title}\n{description}".strip()
        self._reply(200, {"ok": True})

        import threading
        threading.Thread(
            target=lambda: dispatch(text, source=f"linear:{issue.get('identifier','')}"),
            daemon=True,
        ).start()

    def _reply(self, code: int, data: dict):
        body = json.dumps(data).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *_):
        pass


def poll_notion(database_id: str, interval: int = 60):
    """Notion 데이터베이스를 폴링해 '대기중' 상태 항목을 처리한다."""
    import time

    notion_token = os.environ.get("NOTION_TOKEN")
    if not notion_token:
        print("NOTION_TOKEN 환경변수가 필요합니다.", file=sys.stderr)
        sys.exit(1)

    try:
        import urllib.request
    except ImportError:
        pass

    headers = {
        "Authorization": f"Bearer {notion_token}",
        "Content-Type": "application/json",
        "Notion-Version": "2022-06-28",
    }

    while True:
        try:
            # 상태가 '대기중'인 항목 조회
            body = json.dumps({
                "filter": {
                    "property": "Status",
                    "select": {"equals": "대기중"}
                }
            }).encode()

            req = urllib.request.Request(
                f"https://api.notion.com/v1/databases/{database_id}/query",
                data=body,
                headers=headers,
                method="POST",
            )
            with urllib.request.urlopen(req, timeout=10) as r:
                data = json.loads(r.read())

            for page in data.get("results", []):
                props  = page.get("properties", {})
                title  = _notion_text(props.get("Name") or props.get("Title"))
                detail = _notion_text(props.get("Description") or props.get("내용"))
                text   = f"{title}\n{detail}".strip()

                if text:
                    dispatch(text, source=f"notion:{page['id'][:8]}")
                    _notion_update_status(page["id"], "처리중", headers)

        except Exception as e:
            print(f"[notion poll] {e}", file=sys.stderr)

        time.sleep(interval)


def _notion_text(prop: dict | None) -> str:
    if not prop:
        return ""
    rich = prop.get("title") or prop.get("rich_text") or []
    return "".join(r.get("plain_text", "") for r in rich)


def _notion_update_status(page_id: str, status: str, headers: dict):
    import urllib.request
    body = json.dumps({
        "properties": {
            "Status": {"select": {"name": status}}
        }
    }).encode()
    req = urllib.request.Request(
        f"https://api.notion.com/v1/pages/{page_id}",
        data=body,
        headers=headers,
        method="PATCH",
    )
    try:
        urllib.request.urlopen(req, timeout=5)
    except Exception:
        pass


def stdin_loop():
    """로컬 테스트용: stdin에서 한 줄씩 읽어 dispatch한다."""
    print("stdin 모드 (Ctrl-C로 종료)")
    for line in sys.stdin:
        text = line.strip()
        if not text:
            continue
        result = dispatch(text, source="stdin")
        print("---")
        print(result["output"])
        print("---")


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--channel", choices=["slack", "linear", "notion", "stdin"], required=True)
    parser.add_argument("--port",    type=int, default=3000)
    parser.add_argument("--notion-db", default=os.environ.get("NOTION_DATABASE_ID", ""))
    parser.add_argument("--interval",  type=int, default=60, help="Notion 폴링 간격(초)")
    args = parser.parse_args()

    if args.channel == "stdin":
        stdin_loop()

    elif args.channel == "slack":
        server = HTTPServer(("0.0.0.0", args.port), SlackHandler)
        print(f"Slack 웹훅 수신 대기: http://0.0.0.0:{args.port}")
        server.serve_forever()

    elif args.channel == "linear":
        server = HTTPServer(("0.0.0.0", args.port), LinearHandler)
        print(f"Linear 웹훅 수신 대기: http://0.0.0.0:{args.port}")
        server.serve_forever()

    elif args.channel == "notion":
        if not args.notion_db:
            print("--notion-db 또는 NOTION_DATABASE_ID가 필요합니다.", file=sys.stderr)
            sys.exit(1)
        poll_notion(args.notion_db, args.interval)


if __name__ == "__main__":
    main()
