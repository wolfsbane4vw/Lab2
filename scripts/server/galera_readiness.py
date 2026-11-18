import subprocess
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


EXPECTED = {
    "wsrep_cluster_status": "Primary",
    "wsrep_local_state_comment": "Synced",
    "wsrep_ready": "ON",
    "wsrep_connected": "ON",
}

SQL = """
SHOW GLOBAL STATUS
WHERE Variable_name IN (
    'wsrep_cluster_status',
    'wsrep_local_state_comment',
    'wsrep_ready',
    'wsrep_connected'
);
"""


def database_ready():
    try:
        result = subprocess.run(
            [
                "/usr/bin/mariadb",
                "--no-defaults",
                "--protocol=socket",
                "--socket=/var/run/mysqld/mysqld.sock",
                "--user=root",
                "--batch",
                "--skip-column-names",
                f"--execute={SQL}",
            ],
            capture_output=True,
            text=True,
            timeout=3,
            check=True,
        )

        status = dict(
            line.split("\t", 1)
            for line in result.stdout.splitlines()
        )

        return all(status.get(key) == value for key, value in EXPECTED.items())

    except (OSError, subprocess.SubprocessError, ValueError):
        return False


class ReadinessHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path != "/ready":
            code, body = 404, b"Not found\n"
        elif database_ready():
            code, body = 200, b"Ready\n"
        else:
            code, body = 503, b"Not ready\n"

        self.send_response(code)
        self.send_header("Content-Type", "text/plain")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format, *args):
        pass


if __name__ == "__main__":
    ThreadingHTTPServer(("0.0.0.0", 9200), ReadinessHandler).serve_forever()
