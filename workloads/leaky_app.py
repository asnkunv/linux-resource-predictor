#!/usr/bin/env python3
"""Slow memory leak simulator: grows memory for 5 to 8 minutes, holds, then exits."""
import random
import time


def mem_available_mb():
    with open("/proc/meminfo") as f:
        for line in f:
            if line.startswith("MemAvailable"):
                return int(line.split()[1]) // 1024
    return 1000


duration_s = random.randint(5, 8) * 60
interval_s = 10
steps = duration_s // interval_s
target_mb = int(mem_available_mb() * random.uniform(0.20, 0.40))
step_mb = max(1, target_mb // steps)

hog = []
for _ in range(steps):
    hog.append(bytearray(b"x") * (step_mb * 1024 * 1024))  # filled, so it really uses RAM
    time.sleep(interval_s)

time.sleep(30)