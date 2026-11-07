#!/usr/bin/env python3
"""Read local Violet graphics evidence without ZIPs, network, or game assets.

This script only reads existing build/pass_*.png and build/violet-launch-logs/
and writes a small JSON summary to build/violet-graphics-diagnostics/.
Game files, screenshots, save files, keys, absolute paths and raw log lines
are never copied to the summary or sent anywhere.
"""
from __future__ import annotations

import argparse
from collections import Counter, defaultdict
from datetime import datetime, timezone
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]
PASS = re.compile(r"^pass_(\d+)_(\d{3})(?:_c\d+|_l\d+)?\.png$", re.I)
VERTEX = re.compile(r"^\[vtxstate\] skipped draw: vs ([0-9a-f]+) reads attribs (0x[0-9a-f]+)", re.I)
FAULT = re.compile(r"^\[vk\] device fault\s*:", re.I)
SHADER_FAILURE = re.compile(r"\b(?:shader compile failed|SPIR-V validation failed|pipeline creation failed)\b", re.I)


PROBE_LINE = re.compile(
    r"^\[probe\] build/(probe_(\d+)_(\d+)\.png): draw (\d+).*?\bvs ([0-9a-f]+) fs ([0-9a-f]+)\b", re.I
)


def scene_frame_files(build: Path) -> tuple[str | None, list[Path]]:
    """Prefer a substantial complete frame, not a newer empty two-pass capture."""
    by_frame: dict[str, list[Path]] = defaultdict(list)
    for file in build.glob("pass_*.png"):
        m = PASS.fullmatch(file.name)
        if m and not ("_c" in file.stem or "_l" in file.stem):
            by_frame[m.group(1)].append(file)
    if not by_frame:
        return None, []
    frame, paths = max(by_frame.items(), key=lambda item: (
        len(item[1]) >= 8, len(item[1]),
        max(p.stat().st_mtime_ns for p in item[1])))
    return frame, sorted(paths)


def summarize_logs(folder: Path, count: int = 25) -> dict:
    items = sorted(folder.glob("*-stderr.log"), key=lambda p: p.stat().st_mtime_ns)[-count:]
    total_vertex_skips = total_failures = 0
    faults = []
    detail_shader_mode = "not_recorded"
    detail_shader_mode_log = None
    offenders: Counter[str] = Counter()
    for file in items:
        # Avoid reading runaway multi-gigabyte debug output.
        if file.stat().st_size > 30 * 1024 * 1024:
            continue
        saw_fault = False
        for line in file.read_text(encoding="utf-8", errors="replace").splitlines():
            # This is the active runtime path, NOT just a Vulkan capability flag.
            # Keep only the known option value; no raw log text or private paths.
            if line.startswith("[vk] fragment shaders' own derivatives:"):
                detail_shader_mode_log = file.name
                if "quads kept together (quad control)" in line:
                    detail_shader_mode = "full_quad_control"
                elif "the hardware's" in line:
                    detail_shader_mode = "hardware_derivatives"
                elif "quad swaps" in line:
                    detail_shader_mode = "quad_swaps"
                else:
                    detail_shader_mode = "other"
            match = VERTEX.match(line)
            if match:
                total_vertex_skips += 1
                offenders[match.group(1)] += 1
            if FAULT.match(line):
                saw_fault = True
            if SHADER_FAILURE.search(line):
                total_failures += 1
        if saw_fault:
            # Filename is a generated timestamp, not a private or absolute path.
            faults.append(file.name)
    return {
        "logs_inspected": len(items),
        "actual_device_fault_logs": len(faults),
        "fault_log_filenames": faults[-5:],
        "skipped_vertex_draw_messages": total_vertex_skips,
        "most_skipped_vertex_shaders": [
            {"shader": shader, "messages": count} for shader, count in offenders.most_common(6)
        ],
        "shader_or_pipeline_failure_messages": total_failures,
        "detail_shader_mode": detail_shader_mode,
        "detail_shader_mode_log": detail_shader_mode_log,
    }


def _image_stats(path: Path) -> dict:
    try:
        from PIL import Image, ImageChops, ImageFilter, ImageStat
    except ImportError:
        return {"available": False, "reason": "Pillow not installed (log analysis still works)"}
    with Image.open(path) as src:
        im = src.convert("RGB")
        w, h = im.size
        # Perceptual summary only: NOT a reliable pass/fail test for visual quality.
        sample = im.resize((min(w, 640), min(h, 360)))
        mono = sample.convert("L")
        black = mono.point(lambda x: 255 if x < 16 else 0)
        frac = ImageStat.Stat(black).mean[0] / 255
        # An edge residual can track regressions on the SAME scene/frame.
        blurred = mono.filter(ImageFilter.GaussianBlur(radius=1.25))
        residual = ImageChops.difference(mono, blurred)
        edge_energy = ImageStat.Stat(residual).mean[0]
        return {
            "available": True, "width": w, "height": h,
            "dark_pixel_fraction": round(frac, 5),
            "edge_energy_heuristic": round(edge_energy, 4),
        }


def parse_probe_lines(text: str) -> list[dict]:
    """Only retain draw sequence numbers and shader IDs, not private buffers."""
    rows = []
    for line in text.splitlines():
        match = PROBE_LINE.match(line)
        if match:
            filename, frame, shot, draw, vs, fs = match.groups()
            rows.append({"filename": filename, "frame": frame, "shot": int(shot),
                         "draw": int(draw), "vertex_shader": vs, "fragment_shader": fs})
    return rows


def probe_coordinates(build: Path) -> tuple[int, int]:
    """Read only the explicitly recorded F9 target, using safe numeric bounds."""
    path = build / "violet-graphics-diagnostics" / "probe-coordinates.json"
    try:
        data = json.loads(path.read_text(encoding="utf-8-sig"))
        x, y = int(data["x"]), int(data["y"])
        if 0 <= x <= 1000 and 0 <= y <= 1000:
            return x, y
    except (OSError, ValueError, TypeError, KeyError, AttributeError):
        pass
    return 400, 780


def probe_activity(build: Path) -> dict:
    """Find the biggest changed region in a previously captured F9 draw sequence."""
    logs = sorted((build / "violet-launch-logs").glob("*-stderr.log"),
                  key=lambda p: p.stat().st_mtime_ns, reverse=True)
    rows = []
    for log in logs[:25]:
        if log.stat().st_size > 30 * 1024 * 1024:
            continue
        rows = parse_probe_lines(log.read_text(encoding="utf-8", errors="replace"))
        if rows:
            break
    if not rows:
        return {"available": False, "reason": "No F9 per-draw probe capture yet"}
    try:
        from PIL import Image, ImageChops, ImageFilter, ImageStat
    except ImportError:
        return {"available": False, "reason": "Pillow not installed"}
    frame = Counter(row["frame"] for row in rows).most_common(1)[0][0]
    chosen = sorted((row for row in rows if row["frame"] == frame), key=lambda row: row["shot"])
    x_norm, y_norm = probe_coordinates(build)
    last = None
    scores = []
    for row in chosen[:80]:
        p = build / row["filename"]
        if not p.is_file():
            continue
        try:
            with Image.open(p) as im:
                w, h = im.size
                if w < 64 or h < 64:
                    continue
                # Match the F9 target: the old hard-coded floor position
                # missed the hair completely when the head was being probed.
                x, y = round(w * x_norm / 1000), round(h * y_norm / 1000)
                left = max(0, min(w - 64, x - 32))
                top = max(0, min(h - 64, y - 32))
                crop = im.crop((left, top, left + 64, top + 64)).convert("L")
                blurred = crop.filter(ImageFilter.GaussianBlur(1.25))
                edge = ImageStat.Stat(ImageChops.difference(crop, blurred)).mean[0]
                changed = ImageStat.Stat(ImageChops.difference(crop, last)).mean[0] if last else 0
                last = crop.copy()
                scores.append({
                    "draw": row["draw"],
                    "vertex_shader": row["vertex_shader"],
                    "fragment_shader": row["fragment_shader"],
                    "pixel_change": round(changed, 3),
                    "edge_energy": round(edge, 3),
                })
        except (OSError, ValueError):
            continue
    return {
        "available": bool(scores), "frame": frame, "draws_examined": len(scores),
        "probe_coordinates": {"x": x_norm, "y": y_norm},
        "biggest_changes": sorted(scores, key=lambda row: row["pixel_change"], reverse=True)[:8],
        "note": "Heuristic only; draw order and shader IDs are leads, not proof of the defect.",
    }


def summarize(build: Path = ROOT / "build") -> dict:
    frame, files = scene_frame_files(build)
    logs = summarize_logs(build / "violet-launch-logs")
    frame_pass = None
    if files:
        candidates = [p for p in files if p.stem.endswith("_032")]
        frame_pass = (candidates or [files[len(files) // 2]])[0]
    capture_modified = (
        datetime.fromtimestamp(max(p.stat().st_mtime for p in files), tz=timezone.utc).isoformat()
        if files else None
    )
    output = {
        "format_version": 1,
        "local_only": True,
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "capture_last_modified_utc": capture_modified,
        "capture_frame": frame,
        "capture_pass_count": len(files),
        "scene_candidate_pass": frame_pass.name if frame_pass else None,
        "scene_candidate_statistics": _image_stats(frame_pass) if frame_pass else None,
        "launch_logs": logs,
        "probe_draw_activity": probe_activity(build),
        "note": "Statistics do not prove graphics are fixed. Compare the same scene after each code change.",
    }
    return output


def write_summary(build: Path = ROOT / "build") -> Path:
    result = summarize(build)
    out = build / "violet-graphics-diagnostics" / "latest-summary.json"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    return out


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build", type=Path, default=ROOT / "build",
                        help="Local project build directory containing captures and logs")
    args = parser.parse_args()
    out = write_summary(args.build)
    print(out.read_text(encoding="utf-8"))


if __name__ == "__main__":
    main()
