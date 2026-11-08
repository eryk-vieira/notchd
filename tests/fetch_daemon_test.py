#!/usr/bin/env python3
"""Tests of scripts/fetch-daemon.py, the pinned daemon download, of
scripts/ensure-daemon.sh, which picks the binary a host starts, and of the
version the plugin pins.

Hermetic: the destination and XDG_DATA_HOME are temp dirs, the "release" is a
tarball holding a fake `notchd` script, served by a local HTTP server on
127.0.0.1. Nothing touches ~/.local/share. Every process runs under
`timeout -k 2`.

    python3 tests/fetch_daemon_test.py
"""

import hashlib
import io
import json
import os
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FETCH = os.path.join(ROOT, "scripts", "fetch-daemon.py")
ENSURE = os.path.join(ROOT, "scripts", "ensure-daemon.sh")
TIMEOUT = shutil.which("timeout")
VERSION = "9.9.9"
TARGET = "x86_64-unknown-linux-gnu"


def fake_daemon(version):
    return ("#!/bin/sh\necho 'notchd %s'\n" % version).encode()


def fake_ensuring_daemon(version):
    """A `notchd` whose `daemon --ensure` prints a socket path naming its version."""
    return ("#!/bin/sh\ncase \"$1\" in\n  --version) echo 'notchd %s' ;;\n"
            "  daemon) echo 'starting'; echo '/run/notchd-%s.sock' ;;\n  *) exit 2 ;;\nesac\n" % (version, version)).encode()


def tarball(version=VERSION, name="notchd", data=None):
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode="w:gz") as tar:
        data = data or fake_daemon(version)
        info = tarfile.TarInfo("notchd-%s-%s/%s" % (version, TARGET, name))
        info.size = len(data)
        info.mode = 0o644
        tar.addfile(info, io.BytesIO(data))
    return buf.getvalue()


class Versions(unittest.TestCase):
    """Unit: the plugin, the daemon crate and the release pin agree."""

    def test_manifest_and_daemon_crate_share_a_version(self):
        with open(os.path.join(ROOT, "manifest.json")) as f:
            manifest = json.load(f)["version"]
        with open(os.path.join(ROOT, "native", "notchd-daemon", "Cargo.toml")) as f:
            crate = re.search(r'^version = "([^"]+)"', f.read(), re.M).group(1)
        self.assertEqual(manifest, crate, "bump both: manifest.json and native/notchd-daemon/Cargo.toml")

    def test_releases_file_is_a_map_of_versions_to_targets(self):
        with open(os.path.join(ROOT, "native", "releases.json")) as f:
            releases = json.load(f)
        for version, targets in releases.items():
            for target, entry in targets.items():
                self.assertRegex(entry["sha256"], r"^[0-9a-f]{64}$", "%s %s" % (version, target))
                self.assertTrue(entry["url"].startswith("https://"), "%s %s" % (version, target))


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def do_GET(self):
        self.server.hits.append(self.path)
        body = self.server.files.get(self.path)
        if body is None:
            self.send_response(404)
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        self.send_response(200)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


class Fetch(unittest.TestCase):
    tier = "integration"  # fetch-daemon.py as a process against a local server

    def setUp(self):
        self.dir = tempfile.mkdtemp(prefix="notchd-fetch-test.")
        self.addCleanup(shutil.rmtree, self.dir, True)
        self.dest = os.path.join(self.dir, "bin")
        self.archive = tarball()
        self.server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.server.files = {"/notchd.tar.gz": self.archive}
        self.server.hits = []
        self.server.daemon_threads = True
        threading.Thread(target=self.server.serve_forever, daemon=True).start()
        self.addCleanup(self.server.server_close)
        self.addCleanup(self.server.shutdown)
        self.url = "http://127.0.0.1:%d" % self.server.server_address[1]
        self.write_releases(sha=hashlib.sha256(self.archive).hexdigest())

    def write_releases(self, sha, url=None, version=VERSION, target=TARGET):
        self.releases = os.path.join(self.dir, "releases.json")
        with open(self.releases, "w") as f:
            json.dump({version: {target: {"url": url or self.url + "/notchd.tar.gz", "sha256": sha}}}, f)

    def fetch(self, *extra, version=VERSION):
        env = {"PATH": os.environ["PATH"], "HOME": self.dir, "XDG_DATA_HOME": os.path.join(self.dir, "data")}
        cmd = [TIMEOUT, "-k", "2", "30", sys.executable, "-I", FETCH, "--dest", self.dest,
               "--releases", self.releases, "--target", TARGET, "--version", version]
        p = subprocess.run(cmd + list(extra), capture_output=True, text=True, env=env)
        return p.returncode, p.stdout.strip(), p.stderr.strip()

    def error(self, stderr):
        return json.loads(stderr)["error"]

    def leftovers(self):
        return sorted(os.listdir(self.dest)) if os.path.isdir(self.dest) else []

    def test_good_download_installs_an_executable(self):
        code, out, err = self.fetch()
        self.assertEqual((code, err), (0, ""))
        self.assertEqual(out, os.path.join(self.dest, "notchd"))
        self.assertTrue(os.access(out, os.X_OK))
        self.assertEqual(subprocess.run([out, "--version"], capture_output=True, text=True).stdout.strip(), "notchd " + VERSION)
        self.assertEqual(self.leftovers(), ["notchd"])

    def test_checksum_mismatch_is_refused_and_leaves_nothing(self):
        self.write_releases(sha="0" * 64)
        code, out, err = self.fetch()
        self.assertEqual(code, 6)
        self.assertEqual(self.error(err), "checksum-mismatch")
        self.assertEqual(out, "")
        self.assertEqual(self.leftovers(), [])

    def test_a_mismatch_keeps_the_binary_that_was_there(self):
        os.makedirs(self.dest)
        old = os.path.join(self.dest, "notchd")
        with open(old, "wb") as f:
            f.write(fake_daemon("0.0.1"))
        os.chmod(old, 0o755)
        self.write_releases(sha="f" * 64)
        code, _, _ = self.fetch()
        self.assertEqual(code, 6)
        with open(old, "rb") as f:
            self.assertEqual(f.read(), fake_daemon("0.0.1"))
        self.assertEqual(self.leftovers(), ["notchd"])

    def test_a_stale_binary_is_replaced(self):
        os.makedirs(self.dest)
        old = os.path.join(self.dest, "notchd")
        with open(old, "wb") as f:
            f.write(fake_daemon("0.0.1"))
        os.chmod(old, 0o755)
        code, out, _ = self.fetch()
        self.assertEqual(code, 0)
        self.assertEqual(subprocess.run([out, "--version"], capture_output=True, text=True).stdout.strip(), "notchd " + VERSION)

    def test_missing_version(self):
        code, _, err = self.fetch(version="1.2.3")
        self.assertEqual((code, self.error(err)), (3, "no-release"))
        self.assertEqual(self.server.hits, [])
        self.assertEqual(self.leftovers(), [])

    def test_unsupported_arch(self):
        code, _, err = self.fetch("--target", "riscv64gc-unknown-linux-gnu")
        self.assertEqual((code, self.error(err)), (4, "unsupported-arch"))
        self.assertEqual(self.server.hits, [])
        self.assertEqual(self.leftovers(), [])

    def test_already_present_is_not_downloaded(self):
        os.makedirs(self.dest)
        have = os.path.join(self.dest, "notchd")
        with open(have, "wb") as f:
            f.write(fake_daemon(VERSION))
        os.chmod(have, 0o755)
        code, out, _ = self.fetch()
        self.assertEqual((code, out), (0, have))
        self.assertEqual(self.server.hits, [])

    def test_offline(self):
        self.write_releases(sha="0" * 64, url="http://127.0.0.1:9/notchd.tar.gz")
        code, _, err = self.fetch()
        self.assertEqual((code, self.error(err)), (5, "offline"))
        self.assertEqual(self.leftovers(), [])

    def test_http_error_and_bad_archive_fail_cleanly(self):
        self.write_releases(sha="0" * 64, url=self.url + "/nope.tar.gz")
        code, _, err = self.fetch()
        self.assertEqual((code, self.error(err)), (7, "failed"))
        junk = b"not a tarball"
        self.server.files["/junk.tar.gz"] = junk
        self.write_releases(sha=hashlib.sha256(junk).hexdigest(), url=self.url + "/junk.tar.gz")
        code, _, err = self.fetch()
        self.assertEqual((code, self.error(err)), (7, "failed"))
        self.assertEqual(self.leftovers(), [])

    def test_default_dest_is_under_xdg_data_home(self):
        env = {"PATH": os.environ["PATH"], "HOME": self.dir, "XDG_DATA_HOME": os.path.join(self.dir, "data")}
        p = subprocess.run([TIMEOUT, "-k", "2", "30", sys.executable, "-I", FETCH, "--releases", self.releases,
                            "--target", TARGET, "--version", VERSION], capture_output=True, text=True, env=env)
        self.assertEqual(p.stdout.strip(), os.path.join(self.dir, "data", "notchd", "bin", "notchd"))


class Ensure(unittest.TestCase):
    """scripts/ensure-daemon.sh, run on copies of the plugin's scripts in a temp
    tree whose manifest.json says VERSION and whose releases.json pins a
    release served on 127.0.0.1. The fake `notchd` only prints: no daemon starts."""

    tier = "integration"  # the script and fetch-daemon.py as processes, a local server

    def setUp(self):
        self.dir = tempfile.mkdtemp(prefix="notchd-ensure-test.")
        self.addCleanup(shutil.rmtree, self.dir, True)
        self.plugin = os.path.join(self.dir, "plugin")
        os.makedirs(os.path.join(self.plugin, "scripts"))
        os.makedirs(os.path.join(self.plugin, "native"))
        for f in (ENSURE, FETCH):
            shutil.copy(f, os.path.join(self.plugin, "scripts"))
        with open(os.path.join(self.plugin, "manifest.json"), "w") as f:
            json.dump({"version": VERSION}, f)
        # A PATH with what the scripts need and no `notchd`.
        self.path = os.path.join(self.dir, "path")
        os.makedirs(self.path)
        for tool in ("python3", "dirname", "tail"):
            os.symlink(shutil.which(tool), os.path.join(self.path, tool))
        self.data = os.path.join(self.dir, "data", "notchd", "bin")
        self.archive = tarball(data=fake_ensuring_daemon(VERSION))
        self.server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.server.files = {"/notchd.tar.gz": self.archive}
        self.server.hits = []
        self.server.daemon_threads = True
        threading.Thread(target=self.server.serve_forever, daemon=True).start()
        self.addCleanup(self.server.server_close)
        self.addCleanup(self.server.shutdown)
        self.pin("http://127.0.0.1:%d/notchd.tar.gz" % self.server.server_address[1])

    def pin(self, url):
        machine = subprocess.run([sys.executable, "-c", "import platform; print(platform.machine())"],
                                 capture_output=True, text=True).stdout.strip().lower()
        target = {"x86_64": TARGET, "amd64": TARGET}.get(machine, "aarch64-unknown-linux-gnu")
        sha = hashlib.sha256(self.archive).hexdigest()
        with open(os.path.join(self.plugin, "native", "releases.json"), "w") as f:
            json.dump({VERSION: {target: {"url": url, "sha256": sha}}}, f)

    def install(self, version, where=None):
        where = where or self.data
        os.makedirs(where, exist_ok=True)
        path = os.path.join(where, "notchd")
        with open(path, "wb") as f:
            f.write(fake_ensuring_daemon(version))
        os.chmod(path, 0o755)
        return path

    def ensure(self, **extra):
        env = {"PATH": self.path, "HOME": self.dir, "XDG_DATA_HOME": os.path.join(self.dir, "data")}
        env.update(extra)
        p = subprocess.run([TIMEOUT, "-k", "2", "30", "/bin/bash", os.path.join(self.plugin, "scripts", "ensure-daemon.sh")],
                           capture_output=True, text=True, env=env)
        return p.returncode, p.stdout.strip()

    def version_of(self, path):
        return subprocess.run([path, "--version"], capture_output=True, text=True).stdout.strip()

    def test_nothing_installed_fetches_the_pinned_release(self):
        self.assertEqual(self.ensure(), (0, "/run/notchd-%s.sock" % VERSION))
        self.assertEqual(self.version_of(os.path.join(self.data, "notchd")), "notchd " + VERSION)

    def test_an_older_plugin_binary_is_replaced_by_the_pinned_release(self):
        # Issue #22: after a plugin update the old daemon stayed for good.
        self.install("0.0.1")
        self.assertEqual(self.ensure(), (0, "/run/notchd-%s.sock" % VERSION))
        self.assertEqual(self.version_of(os.path.join(self.data, "notchd")), "notchd " + VERSION)
        self.assertEqual(len(self.server.hits), 1)

    def test_the_right_version_is_kept_without_a_download(self):
        self.install(VERSION)
        self.assertEqual(self.ensure(), (0, "/run/notchd-%s.sock" % VERSION))
        self.assertEqual(self.server.hits, [])

    def test_offline_keeps_the_binary_that_is_there(self):
        self.pin("http://127.0.0.1:9/notchd.tar.gz")
        self.install("0.0.1")
        self.assertEqual(self.ensure(), (0, "/run/notchd-0.0.1.sock"))

    def test_offline_with_nothing_installed_says_why(self):
        self.pin("http://127.0.0.1:9/notchd.tar.gz")
        code, out = self.ensure()
        self.assertEqual(code, 1)
        self.assertIn("cannot download", json.loads(out)["error"])

    def test_the_users_own_binary_is_used_as_it_is(self):
        mine = self.install("0.0.2", os.path.join(self.dir, "mine"))
        self.assertEqual(self.ensure(NOTCHD_BIN=mine), (0, "/run/notchd-0.0.2.sock"))
        self.install("0.0.3", self.path)
        self.assertEqual(self.ensure(), (0, "/run/notchd-0.0.3.sock"))
        self.assertEqual(self.server.hits, [])
        self.assertFalse(os.path.exists(self.data))

    def test_a_bad_notchd_bin_is_an_error_not_the_plugins_binary(self):
        self.install(VERSION)
        code, out = self.ensure(NOTCHD_BIN=os.path.join(self.dir, "nope"))
        self.assertEqual(code, 1)
        self.assertIn("NOTCHD_BIN is not executable", json.loads(out)["error"])


if __name__ == "__main__":
    unittest.main()
