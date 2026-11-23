import hashlib
import os
import struct
import subprocess
import sys
import tempfile
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TOOL = os.path.join(ROOT, "tools", "make_patch.py")


def sha(data):
    return hashlib.sha256(data).hexdigest()


class MakePatchTest(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp()
        self.original = bytearray(os.urandom(4096))
        struct.pack_into("<I", self.original, 100, 0x093C28E0)
        struct.pack_into("<I", self.original, 200, 0x00000A00)
        self.patched = bytearray(self.original)
        struct.pack_into("<I", self.patched, 100, 0x098AA1C0)
        struct.pack_into("<I", self.patched, 200, 0x00002000)
        self.write("original", self.original)
        self.write_table([(100, 0x093C28E0, 0x098AA1C0, "umost+0"), (200, 0xA00, 0x2000, "width_clamp")])
        self.write_manifest(sha(self.original), sha(self.patched))

    def write(self, name, data):
        with open(os.path.join(self.dir, name), "wb") as f:
            f.write(data)

    def write_table(self, rows):
        lines = "".join(f"{o:#010x}\t{a:#010x}\t{b:#010x}\t{label}\n" for o, a, b, label in rows)
        self.write("changes.tsv", lines.encode())

    def write_manifest(self, original, patched):
        self.write("manifest", f"ORIGINAL_SHA256={original}\nPATCHED_SHA256={patched}\nCHANGES=changes.tsv\n".encode())

    def run_tool(self):
        return subprocess.run([sys.executable, "-I", TOOL, "--patch-dir", self.dir,
                               os.path.join(self.dir, "original"), os.path.join(self.dir, "out")],
                              capture_output=True, text=True, timeout=60)

    def test_rebuilds_patched_executable(self):
        r = self.run_tool()
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        with open(os.path.join(self.dir, "out"), "rb") as f:
            self.assertEqual(f.read(), bytes(self.patched))

    def test_refuses_unknown_original(self):
        self.original[0] ^= 1
        self.write("original", self.original)
        r = self.run_tool()
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("refused: unknown original", r.stdout)
        self.assertFalse(os.path.exists(os.path.join(self.dir, "out")))

    def test_refuses_when_old_word_differs(self):
        self.write_table([(100, 0x093C28E4, 0x098AA1C0, "umost+4")])
        r = self.run_tool()
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("refused: offset 0x00000064", r.stdout)
        self.assertFalse(os.path.exists(os.path.join(self.dir, "out")))

    def test_refuses_when_result_hash_differs(self):
        self.write_manifest(sha(self.original), "0" * 64)
        r = self.run_tool()
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("refused: result", r.stdout)
        self.assertFalse(os.path.exists(os.path.join(self.dir, "out")))


if __name__ == "__main__":
    unittest.main()
