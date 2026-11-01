#!/usr/bin/env python3
"""Local deterministic HTTP provider for the Neovim suite. No external requests."""
import json
import sys
import time
from pathlib import Path
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

port_file, capture_file = map(Path, sys.argv[1:])
class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args): pass
    def do_POST(self):
        data = json.loads(self.rfile.read(int(self.headers['Content-Length'])))
        capture_file.write_text(json.dumps({'path': self.path, 'body': data, 'headers': dict(self.headers)}))
        source = json.dumps(data)
        if '[slow]' in source: time.sleep(2)
        code = '' if '[empty]' in source else ('return 3\n' if '[refine]' in source else 'return 2\n')
        if '[fenced]' in source: code = '```lua\nreturn 2\n```\n'
        if '[toolcall]' in source: code = json.dumps({'name': 'edit_file', 'arguments': {}})
        status = 200
        if '[fail]' in source: status, result = 503, {'error': 'fixture provider failure'}
        elif '[redirect]' in source: status, result = 302, {}
        elif '[missing]' in source: result = {}
        elif self.path.endswith('/chat/completions'):
            result = {'choices': [{'message': {'content': code}, 'finish_reason': 'length' if '[truncated]' in source else 'stop'}]}
        elif self.path.endswith('/responses'):
            result = {'status': 'completed', 'output': [{'type': 'message', 'content': [{'type': 'output_text', 'text': code}]}]}
        else:
            result = {'done': True, 'done_reason': 'length' if '[truncated]' in source else 'stop', 'message': {'content': code}}
        raw = b'not json' if '[bad-json]' in source else json.dumps(result).encode()
        self.send_response(status)
        if status == 302: self.send_header('Location', '/never-follow')
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        try: self.wfile.write(raw)
        except (BrokenPipeError, ConnectionResetError): pass

server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
port_file.write_text(str(server.server_port))
server.serve_forever()
