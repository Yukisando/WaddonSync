#!/usr/bin/env python3
import os
import shutil
import time
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PNG = os.path.join(ROOT, 'assets', 'icon.png')
ICO_DIR = os.path.join(ROOT, 'windows', 'runner', 'resources')
ICO_PATH = os.path.join(ICO_DIR, 'app_icon.ico')

if not os.path.exists(PNG):
    raise SystemExit(f"Source PNG not found: {PNG}")

if not os.path.exists(ICO_DIR):
    os.makedirs(ICO_DIR)

# backup existing ico if present
if os.path.exists(ICO_PATH):
    bak = ICO_PATH + '.bak.' + time.strftime('%Y%m%dT%H%M%S')
    print(f"Backing up existing ICO to: {bak}")
    shutil.copy2(ICO_PATH, bak)

print(f"Loading source PNG: {PNG}")
img = Image.open(PNG).convert('RGBA')
# Ensure large enough size by resizing from source if needed
sizes = [(256, 256), (128, 128), (64, 64), (48, 48), (32, 32), (16, 16)]
# Pillow writes an ICO with multiple sizes when provided the sizes list
print(f"Saving ICO to: {ICO_PATH} with sizes: {sizes}")
img.save(ICO_PATH, sizes=sizes)
print("Done.")
