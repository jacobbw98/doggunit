"""Retarget genuine UniMate motion samples onto Doggunit's held-dog anchors.

Run with the isolated UniMate Python (NumPy is the only required library):
    python retarget_unimate.py --unimate-root <path-to-your-UniMate-checkout>

The bundled Unitree Head_upper joint is a leaf: its 6D feature stores its
parent's rotation, not an independently articulated head. We therefore use
the generated head-to-body vector and hip planes as pose proxies. The preview
checkpoint lifted the head for eating prompts, so pitch is deliberately
mirrored when mapped to the held weapon. Timing, asymmetry and secondary
motion remain sampled output; translation and locomotion are discarded.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import shutil

import numpy as np


SAMPLES = [
    ("eat", "doggunit_reload", "unitree_go2-an_object_lowers_its_head_to_eat_then_lifts_its-rep_0-0.npy"),
    ("nibble", "doggunit_reload_bow", "unitree_go2-an_object_bends_down_to_eat-rep_1-0.npy"),
    ("bow", "doggunit_reload_bow", "unitree_go2-an_object_crouches_down_with_its_head_lowered-rep_2-0.npy"),
]


def smooth(values: np.ndarray) -> np.ndarray:
    """Five-frame low-pass filter, preserving the endpoint pose."""
    weights = np.array([1.0, 2.0, 3.0, 2.0, 1.0]) / 9.0
    result = np.convolve(np.pad(values, (2, 2), mode="edge"), weights, mode="valid")
    return result - result[0]


def angle(vertical: np.ndarray, forward: np.ndarray) -> np.ndarray:
    return smooth(np.unwrap(np.arctan2(vertical, forward)))


def retarget(motion: np.ndarray) -> tuple[list[dict], dict]:
    if motion.shape != (60, 18, 12) or not np.isfinite(motion).all():
        raise ValueError("Expected a finite 60-frame Unitree Go2 motion.")
    pos = motion[:, :, :3].copy()
    # RIFKE removes root X/Z already, but keeps absolute joint Y heights.
    pos[:, :, 1] -= pos[:, 0:1, 1]
    head = pos[:, 5]
    front = (pos[:, 1] + pos[:, 3]) * 0.5
    rear = (pos[:, 2] + pos[:, 4]) * 0.5
    left = (pos[:, 2] + pos[:, 3]) * 0.5
    right = (pos[:, 1] + pos[:, 4]) * 0.5
    head_pitch = angle(head[:, 1], head[:, 2])
    head_yaw = angle(head[:, 0], head[:, 2])
    spine = front - rear
    across = left - right
    spine_pitch = angle(spine[:, 1], spine[:, 2])
    spine_roll = angle(across[:, 1], across[:, 0])
    amplitude = float(np.max(np.abs(head_pitch)))
    if amplitude < 0.10:
        raise ValueError("Rejecting an almost idle generated head motion.")
    # In Godot, a negative X rotation lowers a muzzle facing -Z.
    head_pitch *= -0.40 / amplitude
    spine_pitch *= -0.095 / max(float(np.max(np.abs(spine_pitch))), 0.10)
    head_rot = np.column_stack((head_pitch, -0.45 * head_yaw, 0.4 * spine_roll))
    body_rot = np.column_stack((spine_pitch, -0.10 * head_yaw, 0.12 * spine_roll))
    head_rot = np.clip(head_rot, [-0.45, -0.08, -0.06], [0.45, 0.08, 0.06])
    body_rot = np.clip(body_rot, [-0.12, -0.03, -0.035], [0.12, 0.03, 0.035])
    frames = [{"time": round(i / 59, 7),
               "head_rotation": [round(float(v), 7) for v in head_rot[i]],
               "body_rotation": [round(float(v), 7) for v in body_rot[i]]}
              for i in range(60)]
    metrics = {"source_head_pitch_amplitude_radians": round(amplitude, 7),
               "export_head_peak_radians": round(float(np.max(np.abs(head_rot))), 7),
               "export_body_peak_radians": round(float(np.max(np.abs(body_rot))), 7)}
    return frames, metrics


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--unimate-root", type=Path, required=True)
    args = parser.parse_args()
    source_dir = Path(__file__).resolve().parent
    output = source_dir.parent / "reload_motion.json"
    clips = []
    manifests = {}
    for name, run_dir, filename in SAMPLES:
        run_path = args.unimate_root / "outputs" / "samples" / run_dir
        motion_path = run_path / "motions" / filename
        manifest = json.loads((run_path / "manifest.json").read_text(encoding="utf-8"))
        sample = manifest["samples"][filename]
        run = manifest["runs"][sample["run"]]
        frames, metrics = retarget(np.load(motion_path))
        preserved = source_dir / f"{name}_unimate_motion.npy"
        shutil.copyfile(motion_path, preserved)
        clips.append({"id": name, "fps": 30, "duration_seconds": 2.0,
                      "frames": frames,
                      "source": {"prompt": sample["prompt"], "seed": run["seed"],
                                 "cfg_scale": run["cfg_scale"], "sample_file": filename,
                                 "source_file": f"source/{preserved.name}",
                                 "sha256": hashlib.sha256(preserved.read_bytes()).hexdigest(),
                                 "rig": "unitree_go2", "metrics": metrics}})
        manifests[run_dir] = manifest
    document = {
        "format": "doggunit-unimate-reload/1", "coordinate_system": "Godot Y-up, forward -Z",
        "rotation_units": "radians, local Euler XYZ delta from first frame",
        "generated_date": "2026-10-08", "clips": clips,
        "provenance": {
            "generator": "UniMate", "repository": "https://github.com/Friedrich-M/UniMate",
            "source_archive_sha256": "344ff7662f1776b8c157113447ef66fb25f4e6b89fa3ea0411125f7c9f17e64a",
            "checkpoint": "unimate_uniml3d_f60_v3/checkpoint_step_150000.pt",
            "checkpoint_sha256": "f991ddd87262c251f4681d18297a6163ab4f139daa28c86d5ef0a66771df7bc6",
            "checkpoint_url": "https://huggingface.co/Linzhan/UniMate/tree/main/unimate_uniml3d_f60_v3",
            "inference_device": "NVIDIA GeForce RTX 4090, PyTorch 2.5.1+cu124",
            "code_license": "MIT", "checkpoint_license": "CC BY-NC 4.0",
            "checkpoint_license_url": "https://huggingface.co/Linzhan/UniMate/blob/main/README.md",
            "source_rig": "Included Unitree Go2 example; Head_upper leaf and base/hip pose proxies",
            "retarget": "Head/body vectors relative to root; five-frame smoothing; first frame neutral; pitch mirrored to eating bow; head scaled to 0.40 rad, body to 0.095 rad; no translation",
            "runtime": "Normalize time to each breed's reload interval and fade both ends to the neutral pose"
        }}
    json_text = json.dumps(document, indent=2) + "\n"
    output.write_text(json_text, encoding="utf-8")
    # A preloaded GDScript resource is included by Godot's export dependency
    # scan. Plain JSON accessed by a string path can otherwise be omitted.
    native_output = output.with_name("reload_motion_data.gd")
    native_output.write_text("extends RefCounted\n"
                             "## Generated alongside reload_motion.json by source/retarget_unimate.py.\n"
                             "const JSON_TEXT := " + json.dumps(json_text, ensure_ascii=False) + "\n",
                             encoding="utf-8")
    (source_dir / "generation_manifests.json").write_text(json.dumps(manifests, indent=2) + "\n", encoding="utf-8")
    print(f"Saved {len(clips)} actual UniMate clips / {sum(len(c['frames']) for c in clips)} frames to {output}")
    print(f"Saved matching Godot export resource to {native_output}")
    for clip in clips:
        print(clip["id"], clip["source"]["metrics"])


if __name__ == "__main__":
    main()
