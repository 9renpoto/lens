"""Black-box resource and outcome checks for the local PDF process runner."""
import json
import pathlib
import subprocess
import sys
import shutil
import time
import tempfile
import unittest


RUNNER = pathlib.Path(__file__).resolve().parents[1] / "priv" / "pdf_runner.py"


class PDFRunnerTest(unittest.TestCase):
    def test_descendants_cannot_continue_after_timeout_or_normal_exit(self):
        for timeout, parent_delay in [(0.1, 60), (2, 0)]:
            with tempfile.TemporaryDirectory() as directory:
                marker = pathlib.Path(directory) / "escaped"
                result = self.run_fixture(
                    "import os, sys, time\n"
                    "if '-v' in sys.argv: print('fixture 1'); sys.exit(0)\n"
                    "if os.fork() == 0:\n"
                    "    time.sleep(0.5)\n"
                    f"    open({str(marker)!r}, 'w').write('escaped')\n"
                    "    os._exit(0)\n"
                    "open(sys.argv[-1], 'w').write('Text')\n"
                    f"time.sleep({parent_delay})\n", timeout=timeout,
                )
                if parent_delay:
                    self.assertEqual(result["failure"], "timeout")
                else:
                    self.assertEqual(result["text"], "Text")
                time.sleep(0.75)
                self.assertFalse(marker.exists(), "extractor descendant survived")

    def test_real_japanese_pdf_preserves_text_and_paragraphs(self):
        self.assertIsNotNone(shutil.which("pdftotext"), "install poppler-utils")
        source = RUNNER.parent.parent / "test/fixtures/earnings-text.pdf"
        result = subprocess.run(
            [sys.executable, str(RUNNER), shutil.which("pdftotext"), str(source), "20", "8388608"],
            capture_output=True, text=True, check=True, timeout=25,
        )
        output = json.loads(result.stdout)
        self.assertIn("決算短信", output["text"])
        self.assertIn("売上高は１２３億円です。", output["text"])
        self.assertIn("営業利益", output["text"])
        self.assertIn("\n\n", output["text"])
        self.assertIn("pdftotext version", output["version"])

    def test_real_image_only_pdf_reports_empty_output(self):
        self.assertIsNotNone(shutil.which("pdftotext"), "install poppler-utils")
        source = RUNNER.parent.parent / "test/fixtures/earnings-image.pdf"
        result = subprocess.run(
            [sys.executable, str(RUNNER), shutil.which("pdftotext"), str(source), "20", "8388608"],
            capture_output=True, text=True, check=True, timeout=25,
        )
        self.assertEqual(json.loads(result.stdout)["failure"], "empty_output")

    def run_fixture(self, body, timeout=2, output_limit=1024):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            executable = root / "extractor"
            executable.write_text("#!/usr/bin/env python3\n" + body)
            executable.chmod(0o700)
            source = root / "input.pdf"
            source.write_bytes(b"%PDF-fixture")
            result = subprocess.run(
                [sys.executable, str(RUNNER), str(executable), str(source),
                 str(timeout), str(output_limit)],
                capture_output=True, text=True, timeout=10,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            return json.loads(result.stdout)

    def test_preserves_paragraphs_and_reports_extractor_version(self):
        result = self.run_fixture(
            "import sys\n"
            "if '-v' in sys.argv: print('fixture 1'); sys.exit(0)\n"
            "open(sys.argv[-1], 'w').write('Revenue\\n\\nProfit')\n"
        )
        self.assertEqual(result["text"], "Revenue\n\nProfit")
        self.assertEqual(result["version"], "fixture 1")

    def test_empty_output_is_failure(self):
        result = self.run_fixture(
            "import sys\n"
            "if '-v' in sys.argv: print('fixture 1'); sys.exit(0)\n"
            "open(sys.argv[-1], 'w').write(' \\n\\f')\n"
        )
        self.assertEqual(result["failure"], "empty_output")

    def test_timeout_is_failure(self):
        result = self.run_fixture(
            "import sys, time\n"
            "if '-v' in sys.argv: print('fixture 1'); sys.exit(0)\n"
            "time.sleep(60)\n", timeout=0.1
        )
        self.assertEqual(result["failure"], "timeout")

    def test_output_limit_is_failure(self):
        result = self.run_fixture(
            "import sys\n"
            "if '-v' in sys.argv: print('fixture 1'); sys.exit(0)\n"
            "open(sys.argv[-1], 'w').write('x' * 100000)\n"
        )
        self.assertEqual(result["failure"], "output_limit")

    def test_unreadable_and_invalid_text_are_failures(self):
        result = self.run_fixture(
            "import sys\n"
            "if '-v' in sys.argv: print('fixture 1'); sys.exit(0)\n"
            "sys.exit(1)\n"
        )
        self.assertEqual(result["failure"], "unreadable")
        result = self.run_fixture(
            "import sys\n"
            "if '-v' in sys.argv: print('fixture 1'); sys.exit(0)\n"
            "open(sys.argv[-1], 'wb').write(b'text\\x00')\n"
        )
        self.assertEqual(result["failure"], "invalid_text")


if __name__ == "__main__":
    unittest.main()
