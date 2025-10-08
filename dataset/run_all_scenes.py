#!/usr/bin/env python3
# Run from iset-lfm root: ../iset-lfm/

import argparse
import json
import os
import signal
import subprocess
import sys
import time
from pathlib import Path
from typing import List, Optional

CHECKPOINT_PATH = Path("./dataset/.render_progress.json")
DEFAULT_IDS_PATH = Path("./dataset/valid_sceneIDs.txt")
DEFAULT_SCRIPT = Path("./dataset/render_save_delete.sh")

# Optional tqdm progress bar
try:
    from tqdm import trange
    HAVE_TQDM = True
except Exception:
    HAVE_TQDM = False


def read_scene_ids(path: Path) -> List[str]:
    if not path.exists():
        sys.exit(f"ERROR: scene ID list not found at {path}")
    ids = []
    with path.open("r") as f:
        for line in f:
            s = line.strip()
            if not s or s.startswith("#"):
                continue
            ids.append(s)
    if not ids:
        sys.exit(f"ERROR: no scene IDs found in {path}")
    return ids


def load_checkpoint() -> Optional[int]:
    if not CHECKPOINT_PATH.exists():
        return None
    try:
        with CHECKPOINT_PATH.open("r") as f:
            data = json.load(f)
        return int(data.get("last_completed_index", -1))
    except Exception:
        # Corrupt checkpoint; ignore
        print(f"WARNING: could not read checkpoint file {CHECKPOINT_PATH}, ignoring.")
        return None


def save_checkpoint(last_completed_index: int) -> None:
    tmp = CHECKPOINT_PATH.with_suffix(".tmp")
    payload = {"last_completed_index": int(last_completed_index), "timestamp": time.time()}
    with tmp.open("w") as f:
        json.dump(payload, f)
    tmp.replace(CHECKPOINT_PATH)


def run_scene(script: Path, scene_id: str, frames: int, cwd: Optional[Path]) -> int:
    cmd = [str(script), scene_id, str(frames)]
    # Suppress all output into devnull (black hole); the rendering .sh handles logging
    with open(os.devnull, "wb") as devnull:
        res = subprocess.run(
            cmd, stdout=devnull, stderr=subprocess.STDOUT, cwd=str(cwd) if cwd else None
        )
    return res.returncode


def make_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        description="Iterate render_save_delete.sh over all sceneIDs with resume + progress."
    )
    p.add_argument(
        "--ids-file",
        type=Path,
        default=DEFAULT_IDS_PATH,
        help=f"Path to scene IDs file (default: {DEFAULT_IDS_PATH})",
    )
    p.add_argument(
        "--script",
        type=Path,
        default=DEFAULT_SCRIPT,
        help=f"Path to render script (default: {DEFAULT_SCRIPT})",
    )
    p.add_argument(
        "--frames",
        type=int,
        default=3,
        help="Number of frames to render per scene (passed to the bash script).",
    )
    p.add_argument(
        "--start-id",
        type=str,
        default=None,
        help="Start from this sceneID (overrides checkpoint).",
    )
    p.add_argument(
        "--reset",
        action="store_true",
        help="Ignore any existing checkpoint and start from the beginning (or --start-id).",
    )
    p.add_argument(
        "--stop-on-error",
        action="store_true",
        help="Stop immediately if any scene fails (non-zero exit code).",
    )
    p.add_argument(
        "--workdir",
        type=Path,
        default=None,
        help="Working directory to run the bash script in (default: current dir).",
    )
    p.add_argument(
        "--fail-log",
        type=Path,
        default=Path("./dataset/failed_scenes.txt"),
        help="File to append sceneIDs that failed (default: failed_scenes.txt).",
    )
    p.add_argument(
        "--count",
        type=int,
        default=None,
        help="Number of scenes to process this run (default: all remaining scenes).",
    )
    return p


def main():
    args = make_parser().parse_args()

    if not args.script.exists():
        sys.exit(f"ERROR: script not found at {args.script}")
    if not os.access(args.script, os.X_OK):
        sys.exit(f"ERROR: script is not executable: {args.script}")

    scene_ids = read_scene_ids(args.ids_file)

    # Determine starting index
    start_index = 0
    if args.start_id:
        try:
            start_index = scene_ids.index(args.start_id)
        except ValueError:
            sys.exit(f"ERROR: start-id '{args.start_id}' not found in {args.ids_file}")
    elif not args.reset:
        cp = load_checkpoint()
        if cp is not None:
            # cp is last completed index; resume at next
            start_index = max(0, cp + 1)

    total = len(scene_ids)

    # Apply batching limit
    if args.count is not None:
        # end_index is exclusive
        end_index = min(start_index + args.count, total)
    else:
        end_index = total

    if start_index >= total:
        print(f"Nothing to do. start_index={start_index} >= total={total}")
        return

    failures = []

    # Graceful handling: on SIGINT/SIGTERM, save checkpoint before exit
    stopping = {"flag": False}

    def handle_signal(signum, frame):
        stopping["flag"] = True
        print("\nReceived interrupt, saving checkpoint...")

    signal.signal(signal.SIGINT, handle_signal)
    signal.signal(signal.SIGTERM, handle_signal)

    # Progress loop
    if HAVE_TQDM:
        rng = trange(start_index, end_index, desc="Rendering scenes", unit="scene")
    else:
        rng = range(start_index, end_index)
        # Simple header
        print(f"Rendering {end_index - start_index} / {total} scenes (no tqdm installed).")

    last_completed = start_index - 1
    try:
        for i in rng:
            sid = scene_ids[i]
            if HAVE_TQDM:
                rng.set_postfix_str(sid)
            else:
                done = i - start_index
                print(f"[{done+1}/{end_index-start_index}] {sid}", end="\r", flush=True)

            rc = run_scene(args.script, sid, args.frames, args.workdir)
            if rc != 0:
                failures.append((sid, rc))
                if args.stop_on_error:
                    print(f"\nERROR: scene {sid} exited with code {rc}. Stopping.")
                    break

            last_completed = i
            # Save checkpoint after each scene to allow precise resume
            save_checkpoint(last_completed)

            if stopping["flag"]:
                break

    finally:
        # Ensure a newline after carriage return progress
        if not HAVE_TQDM:
            print()

    # Write failures log
    if failures:
        with args.fail_log.open("a") as f:
            for sid, rc in failures:
                f.write(f"{sid}\t{rc}\n")

    # Summary
    done_count = max(0, last_completed - start_index + 1)
    remaining = total - (last_completed + 1)
    print(f"Completed: {done_count} scene(s). Remaining: {remaining}.")
    if failures:
        print(f"Failures this run: {len(failures)} (appended to {args.fail_log}).")
    print(f"Checkpoint saved at index {last_completed} ({CHECKPOINT_PATH}).")

    if stopping["flag"]:
        print("Stopped by user; you can resume later with the same command.")


if __name__ == "__main__":
    main()
