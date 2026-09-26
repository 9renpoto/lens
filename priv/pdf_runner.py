"""Run local pdftotext with process, time, memory and file-size bounds."""
import json
import math
import os
import pathlib
import resource
import signal
import subprocess
import sys
import tempfile


MAX_OUTPUT = 8 * 1024 * 1024
MAX_SECONDS = 30
MEMORY_BYTES = 512 * 1024 * 1024


def limits(output_limit, seconds):
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    resource.setrlimit(resource.RLIMIT_FSIZE, (output_limit + 1, output_limit + 1))
    cpu = max(1, math.ceil(seconds))
    resource.setrlimit(resource.RLIMIT_CPU, (cpu, cpu))
    resource.setrlimit(resource.RLIMIT_AS, (MEMORY_BYTES, MEMORY_BYTES))


def run(command, log, seconds, output_limit):
    with log.open("wb") as stream:
        process = subprocess.Popen(
            command, stdin=subprocess.DEVNULL, stdout=stream, stderr=stream,
            start_new_session=True,
            preexec_fn=lambda: limits(output_limit, seconds),
        )
        try:
            return process.wait(timeout=seconds)
        finally:
            # Terminate descendants too, including after an early parent exit.
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            process.wait()


def extract(executable, source, seconds, output_limit):
    if sys.platform != "linux":
        return {"version": "unavailable", "failure": "unsupported_platform"}
    with tempfile.TemporaryDirectory(prefix="lens-pdf-") as directory:
        root = pathlib.Path(directory)
        log = root / "process.log"
        output = root / "text.txt"
        version = "unavailable"
        try:
            status = run([executable, "-v"], log, min(seconds, 2), 4096)
            if status != 0:
                return {"version": version, "failure": "extractor_unavailable"}
            version = log.read_bytes()[:2048].decode("utf-8", errors="replace").strip()
            status = run(
                [executable, "-enc", "UTF-8", "-eol", "unix", "-nopgbrk",
                 str(source), str(output)], log, seconds, output_limit,
            )
            if output.exists() and output.stat().st_size > output_limit:
                return {"version": version, "failure": "output_limit"}
            if status != 0:
                return {"version": version, "failure": "unreadable"}
            text = output.read_bytes().decode("utf-8")
            if "\x00" in text:
                return {"version": version, "failure": "invalid_text"}
            if not text.strip():
                return {"version": version, "failure": "empty_output"}
            return {"version": version, "text": text}
        except subprocess.TimeoutExpired:
            return {"version": version, "failure": "timeout"}
        except UnicodeDecodeError:
            return {"version": version, "failure": "invalid_text"}
        except FileNotFoundError:
            return {"version": version, "failure": "extractor_unavailable"}
        except (OSError, subprocess.SubprocessError):
            return {"version": version, "failure": "process_error"}


def main():
    try:
        executable, source, raw_seconds, raw_output = sys.argv[1:]
        seconds, output_limit = float(raw_seconds), int(raw_output)
        if not (0 < seconds <= MAX_SECONDS and 0 < output_limit <= MAX_OUTPUT):
            raise ValueError("invalid bounds")
        result = extract(executable, pathlib.Path(source), seconds, output_limit)
    except (ValueError, OverflowError):
        result = {"version": "unavailable", "failure": "invalid_options"}
    print(json.dumps(result, ensure_ascii=True))


if __name__ == "__main__":
    main()
