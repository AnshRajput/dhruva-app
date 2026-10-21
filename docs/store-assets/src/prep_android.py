# Android raws from the iPhone simulator captures: same Flutter UI, so paint
# out the iOS status bar / Dynamic Island and the home indicator with the
# app's own background; build.mjs then draws an Android status bar + pill.
# Usage: python3 prep_android.py <raw_ios_dir> <raw_android_dir>
import glob
import os
import sys

from PIL import Image, ImageDraw

src, dst = sys.argv[1], sys.argv[2]
os.makedirs(dst, exist_ok=True)
for f in sorted(glob.glob(os.path.join(src, "*.png"))):
    im = Image.open(f).convert("RGB")
    w, h = im.size
    top, bottom = round(h * 0.062), round(h * 0.024)  # 59pt / ~22pt @3x on 956pt
    d = ImageDraw.Draw(im)
    d.rectangle([0, 0, w, top], fill=im.getpixel((8, top + 6)))
    d.rectangle([0, h - bottom, w, h], fill=im.getpixel((8, h - bottom - 4)))
    im.save(os.path.join(dst, os.path.basename(f)))
print("ok")
