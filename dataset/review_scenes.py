#!/usr/bin/env python3

# NOTE: Run from the iset-lfm/ directory; using the relative path to ScenePNGs.

import os
import sys
import json
import glob
import subprocess
from datetime import datetime
from shutil import which

# --- Config (relative to this script) ---
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
PNG_DIR = os.path.normpath(os.path.join("../ScenePNGs"))
OUT_TXT = os.path.join(BASE_DIR, "selected_scenes.txt")
PROGRESS_JSON = os.path.join(BASE_DIR, "selection_progress.json")

USE_VSCODE = which("code") is not None  # open images in the VS Code editor

HELP = "Keys: y = select, n = reject, b = back, r = reopen image, q = quit"

def load_selected_set(path):
    sel = set()
    if os.path.exists(path):
        with open(path, "r") as f:
            for line in f:
                s = line.strip()
                if s:
                    sel.add(s)
    return sel

def append_selected(path, scene_id):
    with open(path, "a") as f:
        f.write(scene_id + "\n")

def load_progress(path, total):
    idx = 0
    if os.path.exists(path):
        try:
            with open(path, "r") as f:
                data = json.load(f)
                idx = int(data.get("index", 0))
        except Exception:
            idx = 0
    return max(0, min(idx, total))

def save_progress(path, index, total):
    payload = {
        "index": int(index),
        "total": int(total),
        "timestamp": datetime.now().isoformat(timespec="seconds"),
    }
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        json.dump(payload, f, indent=2)
    os.replace(tmp, path)

def extract_scene_id(png_path):
    # Expect: <sceneID>_skymap.png
    base = os.path.basename(png_path)
    if "_" in base:
        return base.split("_", 1)[0]
    return os.path.splitext(base)[0]

def open_in_vscode(path):
    # -r reuse window; --goto works for text but fine to reuse here
    # Use blocking call; VS Code opens the image, we just return immediately.
    try:
        subprocess.run(["code", "-r", path], check=False)
    except FileNotFoundError:
        pass

def main():
    files = sorted(glob.glob(os.path.join(PNG_DIR, "*_skymap.png")))
    if not files:
        print(f"No *_skymap.png files found in: {PNG_DIR}")
        sys.exit(1)

    os.makedirs(os.path.dirname(OUT_TXT), exist_ok=True)
    selected = load_selected_set(OUT_TXT)

    i = load_progress(PROGRESS_JSON, len(files))
    print(f"Loaded {len(files)} thumbnails from {PNG_DIR}")
    print(f"Resuming at index {i}/{len(files)}")
    print(HELP)
    if not USE_VSCODE:
        print("Note: 'code' CLI not found. Will print file paths; open them manually in VS Code.")

    while i < len(files):
        path = files[i]
        scene_id = extract_scene_id(path)
        print(f"\n[{i+1}/{len(files)}] {os.path.basename(path)}  sceneID={scene_id}")

        if USE_VSCODE:
            open_in_vscode(path)
        else:
            print(f"Open this image: {path}")

        while True:
            choice = input("(y/n/b/r/q) > ").strip().lower()
            if choice == "y":
                if scene_id not in selected:
                    append_selected(OUT_TXT, scene_id)
                    selected.add(scene_id)
                print(f"SELECTED {scene_id}")
                i += 1
                break
            elif choice == "n":
                print(f"rejected {scene_id}")
                i += 1
                break
            elif choice == "b":
                i = max(0, i - 1)
                print(f"Back to index {i} ({os.path.basename(files[i])})")
                break
            elif choice == "r":
                if USE_VSCODE:
                    open_in_vscode(path)
                else:
                    print(f"Open this image: {path}")
                continue
            elif choice == "q":
                print("Quitting, progress saved.")
                save_progress(PROGRESS_JSON, i, len(files))
                sys.exit(0)
            else:
                print("Unrecognized key. " + HELP)

        save_progress(PROGRESS_JSON, i, len(files))

    print("\nDone! Reviewed all images.")
    save_progress(PROGRESS_JSON, len(files), len(files))
    print(f"Selected scenes written to {OUT_TXT} (unique total: {len(selected)})")

if __name__ == "__main__":
    main()
