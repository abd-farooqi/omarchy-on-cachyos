#!/usr/bin/env python3
"""Emit activity only; never emit or persist key codes or text."""

import glob
import os
import struct
import sys
import threading
import time

EVENT_SIZE = struct.calcsize("llHHI")
KEY_PRESS = 1
KEY_REPEAT = 2
LEFT_SHIFT = 42
RIGHT_SHIFT = 54
shift_lock = threading.Lock()
shift_keys = set()


def keyboard_paths():
    paths = []
    for name_path in glob.glob("/sys/class/input/event*/device/name"):
        try:
            with open(name_path, encoding="utf-8", errors="replace") as handle:
                name = handle.read().strip().lower()
        except OSError:
            continue
        if any(token in name for token in ("keyboard", "hotkeys", "alp0018:00 044e:121b unknown")):
            paths.append("/dev/input/" + os.path.basename(os.path.dirname(os.path.dirname(name_path))))
    return paths


def watch(path):
    try:
        handle = open(path, "rb", buffering=0)
    except OSError:
        return
    with handle:
        try:
            while True:
                data = handle.read(EVENT_SIZE)
                if len(data) != EVENT_SIZE:
                    return
                _, _, event_type, code, value = struct.unpack("llHHI", data)
                if event_type != 1 or not (0 < code < 256):
                    continue
                if code in (LEFT_SHIFT, RIGHT_SHIFT) and value in (0, KEY_PRESS, KEY_REPEAT):
                    # Aggregate devices so one keyboard's release cannot clear
                    # Shift while another physical keyboard still holds it.
                    with shift_lock:
                        key = (path, code)
                        if value:
                            shift_keys.add(key)
                        else:
                            shift_keys.discard(key)
                        shift_held = bool(shift_keys)
                    sys.stdout.write("shift " + ("1\n" if shift_held else "0\n"))
                elif value in (KEY_PRESS, KEY_REPEAT):
                    sys.stdout.write("activity\n")
                sys.stdout.flush()
        finally:
            with shift_lock:
                stale_keys = {key for key in shift_keys if key[0] == path}
                if stale_keys:
                    shift_keys.difference_update(stale_keys)
                    sys.stdout.write("shift " + ("1\n" if shift_keys else "0\n"))
                    sys.stdout.flush()


def main():
    paths = keyboard_paths()
    if not paths:
        time.sleep(2)
        return main()
    for path in paths:
        threading.Thread(target=watch, args=(path,), daemon=True).start()
    while True:
        time.sleep(60)


if __name__ == "__main__":
    try:
        main()
    except (BrokenPipeError, KeyboardInterrupt):
        pass
