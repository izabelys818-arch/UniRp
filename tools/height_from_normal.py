"""Reconstrói mapas de altura a partir dos normal maps (Frankot-Chellappa, por FFT).

Uso: python tools/height_from_normal.py
Lê assets/textures/surfaces/<nome>_nr.jpg (R,G = normal OpenGL) e grava <nome>_h.jpg (1024 px,
0 = fundo do rejunte, 1 = topo da pedra) para o parallax do shader de superfícies.
"""
import json
import os

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DIR = os.path.join(ROOT, "assets", "textures", "surfaces")
SIZE = 1024

IMPORT = """[remap]

importer="texture"
type="CompressedTexture2D"

[deps]

source_file="res://assets/textures/surfaces/{name}"

[params]

compress/mode=2
compress/high_quality=true
compress/lossy_quality=0.7
compress/hdr_compression=1
compress/normal_map=2
compress/channel_pack=0
mipmaps/generate=true
mipmaps/limit=-1
roughness/mode=0
roughness/src_normal=""
process/fix_alpha_border=true
process/premult_alpha=false
process/normal_map_invert_y=false
process/hdr_as_srgb=false
process/hdr_clamp_exposure=false
process/size_limit=0
detect_3d/compress_to=0
"""


def height(nr_path):
    img = Image.open(nr_path).convert("RGB").resize((SIZE, SIZE), Image.LANCZOS)
    n = np.asarray(img).astype(np.float64) / 255.0 * 2.0 - 1.0
    nx, ny = n[..., 0], n[..., 1]
    nz = np.sqrt(np.clip(1.0 - nx * nx - ny * ny, 0.05, 1.0))
    # OpenGL: verde aponta para cima na imagem (linha cresce para baixo)
    p = -nx / nz
    q = ny / nz
    h, w = p.shape
    wx = np.fft.fftfreq(w) * 2.0 * np.pi
    wy = np.fft.fftfreq(h) * 2.0 * np.pi
    WX, WY = np.meshgrid(wx, wy)
    denom = WX ** 2 + WY ** 2
    denom[0, 0] = 1.0
    Z = (-1j * WX * np.fft.fft2(p) - 1j * WY * np.fft.fft2(q)) / denom
    Z[0, 0] = 0.0
    z = np.real(np.fft.ifft2(Z))
    lo, hi = np.percentile(z, 1.0), np.percentile(z, 99.0)
    return np.clip((z - lo) / max(hi - lo, 1e-6), 0.0, 1.0)


def main():
    layers = json.load(open(os.path.join(DIR, "layers.json"), encoding="utf-8"))
    for layer in layers:
        name = layer["name"]
        z = height(os.path.join(DIR, f"{name}_nr.jpg"))
        out = f"{name}_h.jpg"
        Image.fromarray((z * 255.0 + 0.5).astype(np.uint8), "L").save(os.path.join(DIR, out), quality=92)
        with open(os.path.join(DIR, out + ".import"), "w", encoding="utf-8", newline="\n") as fh:
            fh.write(IMPORT.format(name=out))
        print(name, "ok", flush=True)


if __name__ == "__main__":
    main()
