#!/usr/bin/env python3
"""Read-only Violet boot-log triage. No game files or generated C are needed.

Usage: python tools/violet/boot_triage.py build/violet-tests/boot/stderr.log
       python tools/violet/boot_triage.py <log> --json <report.json> [--timed-out]
A guest abort with Result 0 is not evidence that a particular IPC stub caused it.
"""
import argparse
import json
from pathlib import Path
import re

LOADED = re.compile(r"^loaded\s+(main|subsdk0|sdk)\s+at\s+([0-9a-f]+)\s+size\s+([0-9a-f]+)", re.I)
BREAK = re.compile(r"svcBreak\(reason=([0-9a-f]+), info=([0-9a-f]+), size=([0-9a-f]+)\) at ([0-9a-f]+)", re.I)
FRAME = re.compile(r"^\s+guest #(\d+) ([0-9a-f]+)", re.I)
RESULT = re.compile(r"\[kernel\] abort on result 0x([0-9a-f]+)", re.I)
FRAME_STAT = re.compile(r"^\[(?:vk|metal)\] t=[\d.]+ frame (\d+) [\d.]+ fps", re.I)
STUB = re.compile(r"\[ipc\] (?:STUB |no HLE implementation for service )", re.I)


def location(addr, modules):
    """Return a module and an offset only when that address is inside its *loaded* image."""
    for name, base, size in modules:
        if base <= addr < base + size:
            return {"address": f"0x{addr:x}", "module": name, "offset": f"0x{addr-base:x}"}
    return {"address": f"0x{addr:x}", "module": None, "offset": None}


def analyze(log_text, timed_out=False):
    lines = log_text.splitlines()
    modules = []
    break_info = None
    payload_result = None
    stack = []
    recent_service_warnings = []
    frame_stats = 0
    for line in lines:
        m = LOADED.search(line)
        if m:
            modules = [x for x in modules if x[0] != m[1]]
            modules.append((m[1], int(m[2], 16), int(m[3], 16)))
        m = RESULT.search(line)
        if m:
            payload_result = int(m[1], 16)
        elif "abort payload Result is zero" in line:
            payload_result = 0
        m = BREAK.search(line)
        if m:
            break_info = {"reason": int(m[1], 16), "info": f"0x{int(m[2],16):x}",
                          "size": int(m[3], 16), "pc": int(m[4], 16)}
        m = FRAME.match(line)
        if m:
            stack.append((int(m[1]), int(m[2], 16)))
        if STUB.search(line) or "(unhandled, ok)" in line:
            recent_service_warnings.append(line.strip()[:240])
            recent_service_warnings = recent_service_warnings[-12:]
        if m := FRAME_STAT.match(line):
            if int(m[1]) > 0:
                frame_stats += 1

    if break_info:
        outcome = "guest-abort-before-frame-stats" if not frame_stats else "guest-abort-after-frame-stats"
    elif any("FATAL:" in line for line in lines):
        outcome = "other-fatal"
    elif timed_out:
        outcome = "time-limit"
    else:
        outcome = "unclassified"

    notes = []
    if break_info and payload_result == 0:
        notes.append("Abort payload Result is zero. Do not infer an IPC failure from this value.")
    if not frame_stats:
        notes.append("No positive-frame FPS line was observed; this alone does not prove no frame was presented.")
    if recent_service_warnings:
        notes.append("Stub/unhandled service lines are leads, not confirmed causes.")
    if not modules:
        notes.append("No loaded-module ranges in the log; addresses cannot be attributed safely.")
    return {
        "outcome": outcome,
        "timed_out": bool(timed_out),
        "loaded_modules": [{"name": name, "base": f"0x{base:x}", "size": f"0x{size:x}"}
                           for name, base, size in modules],
        "abort": ({**{k: v for k, v in break_info.items() if k != "pc"},
                   "location": location(break_info["pc"], modules),
                   "payload_result": None if payload_result is None else f"0x{payload_result:x}"}
                  if break_info else None),
        "guest_stack": [{"frame": i, **location(addr, modules)} for i, addr in stack[-16:]],
        "fps_lines_with_positive_frame_count": frame_stats,
        "recent_stub_or_unhandled_calls": recent_service_warnings,
        "notes": notes,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("log", type=Path)
    parser.add_argument("--json", type=Path, dest="report")
    parser.add_argument("--timed-out", action="store_true")
    args = parser.parse_args()
    report = analyze(args.log.read_text(encoding="utf-8", errors="replace"), args.timed_out)
    output = json.dumps(report, indent=2) + "\n"
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(output, encoding="utf-8")
    print(output, end="")


if __name__ == "__main__":
    main()
