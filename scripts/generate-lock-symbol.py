"""Trace the supplied transparent logo into a monochrome SF Symbol asset.

Requires Pillow. The source PNG is unchanged; the output is vector geometry.
"""
from collections import defaultdict
from pathlib import Path
import json
from PIL import Image

root = Path(__file__).resolve().parents[1]
source = Image.open(root / "logoformatopantalladebloqueo.png").convert("RGBA")
alpha = source.getchannel("A").resize((160, 160), Image.Resampling.LANCZOS)
pixels = {(x, y) for y in range(160) for x in range(160) if alpha.getpixel((x, y)) >= 150}
edges = defaultdict(list)
for x, y in sorted(pixels):
    for neighbor, a, b in [((x, y-1), (x, y), (x+1, y)),
                            ((x+1, y), (x+1, y), (x+1, y+1)),
                            ((x, y+1), (x+1, y+1), (x, y+1)),
                            ((x-1, y), (x, y+1), (x, y))]:
        if neighbor not in pixels:
            edges[a].append(b)

paths = []
while edges:
    start = next(iter(edges))
    p = start
    ring = []
    while True:
        ring.append(p)
        q = edges[p].pop()
        if not edges[p]:
            del edges[p]
        p = q
        if p == start:
            break
    area = sum(a[0]*b[1] - b[0]*a[1] for a, b in zip(ring, ring[1:]+ring[:1])) / 2
    if abs(area) < 8:
        continue
    # Remove collinear vertices while retaining the silhouette and facial cutouts.
    ring = [b for a, b, c in zip(ring[-1:]+ring[:-1], ring, ring[1:]+ring[:1])
            if (b[0]-a[0])*(c[1]-b[1]) != (b[1]-a[1])*(c[0]-b[0])]
    paths.append("M" + " L".join(f"{x*.5:.1f},{y*.5:.1f}" for x,y in ring) + " Z")

svg = '''<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="3300" height="2200" viewBox="0 0 3300 2200">
<g id="Notes"><text x="0" y="0">Lenara — traced from logoformatopantalladebloqueo.png</text></g>
<g id="Guides">
<line id="Baseline-S" x1="0" y1="400" x2="3300" y2="400" stroke="#000"/>
<line id="Capline-S" x1="0" y1="350" x2="3300" y2="350" stroke="#000"/>
<line id="Baseline-M" x1="0" y1="750" x2="3300" y2="750" stroke="#000"/>
<line id="Capline-M" x1="0" y1="680" x2="3300" y2="680" stroke="#000"/>
<line id="Baseline-L" x1="0" y1="1100" x2="3300" y2="1100" stroke="#000"/>
<line id="Capline-L" x1="0" y1="1010" x2="3300" y2="1010" stroke="#000"/>
<line id="left-margin-Regular-M" x1="1390" y1="600" x2="1390" y2="850" stroke="#000"/>
<line id="right-margin-Regular-M" x1="1470" y1="600" x2="1470" y2="850" stroke="#000"/>
</g>
<g id="Symbols"><g id="Regular-M" transform="translate(1390 675)">
<path fill="black" fill-rule="evenodd" d="PATH"/>
</g></g></svg>
'''.replace("PATH", " ".join(paths))
asset = root / "Shared/CaptureAssets.xcassets/LenaraLockSymbol.symbolset"
asset.mkdir(parents=True, exist_ok=True)
(asset.parent / "Contents.json").write_text(json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2)+"\n")
(asset / "Contents.json").write_text(json.dumps({"info": {"author": "xcode", "version": 1},
    "symbols": [{"filename": "LenaraLockSymbol.svg", "idiom": "universal"}]}, indent=2)+"\n")
(asset / "LenaraLockSymbol.svg").write_text(svg)
print(f"Generated {asset} ({len(paths)} contours)")
