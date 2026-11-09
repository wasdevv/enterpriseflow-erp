#!/usr/bin/env python3
"""Servico fiscal SIMULADO, so para demonstracao e testes de integracao.

POST /v1/events aplica um efeito por Idempotency-Key. /__admin permite roteirizar falhas:
responder erro depois de aplicar o efeito (resposta perdida), atrasar alem do timeout
do cliente e recusar de forma permanente.
"""
import argparse
import json
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

LOCK = threading.Lock()
EFFECTS = {}
REPLIES = {}
SCRIPT = []
RECEIVED = 0


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *_):
        pass

    def reply(self, status, body):
        data = body.encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        try:
            self.wfile.write(data)
        except (BrokenPipeError, ConnectionResetError):
            pass

    def read_body(self):
        length = int(self.headers.get("Content-Length") or 0)
        return self.rfile.read(length).decode("utf-8") if length else ""

    def do_GET(self):
        url = urlparse(self.path)
        if url.path == "/health":
            return self.reply(200, '{"status":"ok"}')
        if url.path == "/__admin/effects":
            key = parse_qs(url.query).get("key", [""])[0]
            with LOCK:
                return self.reply(200, str(EFFECTS.get(key, 0)))
        if url.path == "/__admin/received":
            with LOCK:
                return self.reply(200, str(RECEIVED))
        return self.reply(404, '{"error":"not found"}')

    def do_POST(self):
        global RECEIVED
        url = urlparse(self.path)
        body = self.read_body()
        if url.path == "/__admin/reset":
            with LOCK:
                EFFECTS.clear()
                REPLIES.clear()
                SCRIPT.clear()
                RECEIVED = 0
            return self.reply(200, "{}")
        if url.path == "/__admin/script":
            with LOCK:
                SCRIPT.extend(json.loads(body))
            return self.reply(200, "{}")
        if url.path != "/v1/events":
            return self.reply(404, '{"error":"not found"}')

        key = self.headers.get("Idempotency-Key", "")
        with LOCK:
            RECEIVED += 1
            step = SCRIPT.pop(0) if SCRIPT else {}
        time.sleep(step.get("delay_ms", 0) / 1000)

        if step.get("apply", step.get("status", 200) < 400):
            with LOCK:
                if key:
                    EFFECTS[key] = 1
                else:
                    EFFECTS["<sem-chave>"] = EFFECTS.get("<sem-chave>", 0) + 1
                REPLIES.setdefault(key, '{"receipt":"R-%d"}' % len(EFFECTS))
                reply = REPLIES[key]
        else:
            reply = '{"error":"recusado"}'

        status = step.get("status", 200)
        if step.get("echo_auth"):
            reply = json.dumps({"error": "falha", "token": self.headers.get("Authorization", "")})
        return self.reply(status, reply)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=8765)
    args = parser.parse_args()
    ThreadingHTTPServer(("127.0.0.1", args.port), Handler).serve_forever()


if __name__ == "__main__":
    main()
