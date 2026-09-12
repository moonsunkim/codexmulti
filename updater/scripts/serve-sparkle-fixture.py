from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import pathlib
import sys
import time
import uuid

feed = pathlib.Path(sys.argv[1]).resolve()
metadata = pathlib.Path(sys.argv[2]).resolve()
metadata.mkdir(parents=True, exist_ok=True)
prefix = '/' + uuid.uuid4().hex + '/'


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        names = {prefix + name: name for name in ['appcast.xml', 'CodexMulti.zip']}
        name = names.get(self.path)
        file = feed / name if name else None
        if not file or not file.is_file() or file.is_symlink():
            self.send_error(404)
            return
        self.send_response(200)
        self.send_header('Content-Type', 'application/xml' if name.endswith('xml') else 'application/octet-stream')
        self.send_header('Content-Length', str(file.stat().st_size))
        self.send_header('Cache-Control', 'no-store')
        self.end_headers()
        with (metadata / 'requests.jsonl').open('a') as log:
            log.write(json.dumps(dict(file=name, time=time.time(), size=file.stat().st_size)) + '\n')
        with file.open('rb') as stream:
            while chunk := stream.read(262144):
                self.wfile.write(chunk)

    def log_message(self, *_):
        pass


server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
(metadata / 'server.json').write_text(json.dumps(dict(port=server.server_port, prefix=prefix, feed=str(feed))) + '\n')
server.serve_forever()
