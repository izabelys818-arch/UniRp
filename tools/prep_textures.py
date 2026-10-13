"""Prepara as texturas fotográficas CC0 (ambientCG) para o shader de superfícies.

Uso: python tools/prep_textures.py <pasta com os zips do ambientCG>

Para cada material grava em assets/textures/surfaces/:
  <nome>_albedo.jpg  cor com a oclusão de ambiente já multiplicada
  <nome>_nr.jpg      R,G = normal (OpenGL), B = rugosidade
e assets/textures/surfaces/layers.json com a ordem das camadas, o tamanho do ladrilho em
metros, quanto a cor do vértice tinge a textura e a cor média linear (para o tingimento).
Também escreve os .import (VRAM BC7 com mipmaps; o _nr sem conversão de normal map).
"""
import io
import json
import os
import sys
import zipfile

import numpy as np
from PIL import Image, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "textures", "surfaces")

# nome, asset ambientCG, resolução, ladrilho (m), tingimento pela cor do vértice
GROUND = [
    ("grass", "Grass004", 4096, 2.2, 0.55),
    ("asphalt", "Asphalt012", 4096, 4.0, 0.55),
    ("paving", "PavingStones070", 4096, 2.4, 0.6),
    ("ground", "Ground037", 4096, 3.0, 0.5),
]
SURF = [
    ("plaster", "PaintedPlaster017", 2048, 2.6, 0.85),
    ("brick", "Bricks059", 2048, 1.6, 0.35),
    ("concrete", "Concrete034", 2048, 2.5, 0.7),
    ("roof", "RoofingTiles013A", 2048, 1.8, 0.55),
    ("woodfloor", "WoodFloor051", 2048, 2.0, 0.45),
    ("wood", "Wood049", 2048, 1.2, 0.5),
    ("paintedwood", "PaintedWood005", 2048, 1.6, 0.8),
    ("tiles", "Tiles074", 2048, 1.0, 0.6),
    ("fabric", "Fabric030", 2048, 0.6, 0.85),
    ("leather", "Leather037", 2048, 0.8, 0.8),
    ("carpet", "Carpet012", 2048, 1.2, 0.85),
    ("marble", "Marble006", 2048, 1.6, 0.4),
    ("metal", "PaintedMetal004", 2048, 1.5, 0.85),
    ("rust", "Rust004", 2048, 1.5, 0.3),
    ("gravel", "Gravel022", 2048, 1.6, 0.5),
    ("bark", "Bark007", 2048, 1.2, 0.45),
    ("leaf", "LeafSet024", 2048, 1.4, 0.6),
]

# Pintados: a foto vira só detalhe em cinza (relevo, poros, arranhões) e a cor vem do objeto.
# O mármore preto vira claro com veios escuros (tons invertidos).
DETAIL = {"asphalt", "plaster", "concrete", "paintedwood", "tiles", "fabric", "leather", "carpet", "marble", "metal", "roof"}
INVERT = {"marble"}

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


def read(zf, asset, suffix):
    for name in zf.namelist():
        if name.endswith("_" + suffix + ".jpg") and name.startswith(asset):
            return Image.open(io.BytesIO(zf.read(name)))
    return None


def srgb_to_linear(c):
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def prepare(name, asset, size, src_dir):
    res = "4K" if size >= 4096 else "2K"
    zf = zipfile.ZipFile(os.path.join(src_dir, f"{asset}_{res}-JPG.zip"))
    color = read(zf, asset, "Color").convert("RGB").resize((size, size), Image.LANCZOS)
    normal = read(zf, asset, "NormalGL").convert("RGB").resize((size, size), Image.LANCZOS)
    rough = read(zf, asset, "Roughness").convert("L").resize((size, size), Image.LANCZOS)
    ao = read(zf, asset, "AmbientOcclusion")
    opacity = read(zf, asset, "Opacity")
    col = np.asarray(color).astype(np.float32) / 255.0
    if name == "leaf" and opacity is not None:
        # folhagem opaca: o vão entre as folhas vira folhagem mais funda e escura
        a = np.asarray(opacity.convert("L").resize((size, size), Image.LANCZOS)).astype(np.float32)[..., None] / 255.0
        deep = np.asarray(color.filter(ImageFilter.GaussianBlur(24))).astype(np.float32) / 255.0 * 0.38
        col = col * a + deep * (1.0 - a)
    if ao is not None:
        aov = np.asarray(ao.convert("L").resize((size, size), Image.LANCZOS)).astype(np.float32)[..., None] / 255.0
        col = col * (1.0 - 0.7 * (1.0 - aov))
    if name in DETAIL:
        lin = srgb_to_linear(col)
        luma = lin[..., 0] * 0.2126 + lin[..., 1] * 0.7152 + lin[..., 2] * 0.0722
        if name in INVERT:
            luma = 1.0 - luma
        # detalhe com média 0,45 linear e contraste contido (sem ruído amplificado nos escuros)
        luma = np.log(np.maximum(luma, 1e-4))
        luma = (luma - luma.mean()) / max(luma.std(), 1e-4) * 0.16
        luma = 0.45 * np.exp(luma)
        enc = np.where(luma <= 0.0031308, luma * 12.92, 1.055 * np.power(np.clip(luma, 0, 1), 1 / 2.4) - 0.055)
        col = np.repeat(np.clip(enc, 0, 1)[..., None], 3, axis=2)
    albedo = Image.fromarray(np.clip(col * 255.0 + 0.5, 0, 255).astype(np.uint8))
    albedo.save(os.path.join(OUT, f"{name}_albedo.jpg"), quality=92)
    n = np.asarray(normal).astype(np.uint8)
    r = np.asarray(rough).astype(np.uint8)
    nr = np.dstack([n[..., 0], n[..., 1], r])
    Image.fromarray(nr).save(os.path.join(OUT, f"{name}_nr.jpg"), quality=95)
    for suffix in ("albedo", "nr"):
        file = f"{name}_{suffix}.jpg"
        with open(os.path.join(OUT, file + ".import"), "w", encoding="utf-8", newline="\n") as fh:
            fh.write(IMPORT.format(name=file))
    mean = srgb_to_linear(col).reshape(-1, 3).mean(axis=0)
    return [float(x) for x in mean]


def main():
    src = sys.argv[1]
    os.makedirs(OUT, exist_ok=True)
    layers = []
    for group, entries in (("ground", GROUND), ("surf", SURF)):
        for name, asset, size, tile, tint in entries:
            only = sys.argv[2].split(",") if len(sys.argv) > 2 else None
            if only and name not in only:
                prev = json.load(open(os.path.join(OUT, "layers.json"), encoding="utf-8"))
                mean = next(l["mean"] for l in prev if l["name"] == name)
            else:
                mean = prepare(name, asset, size, src)
            layers.append({"name": name, "asset": asset, "array": group, "size": size,
                           "tile_m": tile, "tint": 1.0 if name in DETAIL else tint, "mean": mean})
            print(name, asset, size, ["%.3f" % m for m in mean], flush=True)
    with open(os.path.join(OUT, "layers.json"), "w", encoding="utf-8", newline="\n") as fh:
        json.dump(layers, fh, indent=1)
    with open(os.path.join(OUT, "LICENSE.txt"), "w", encoding="utf-8", newline="\n") as fh:
        fh.write("Texturas de ambientCG.com (CC0 1.0, domínio público). Materiais:\n")
        for layer in layers:
            fh.write(f"- {layer['name']}: https://ambientcg.com/view?id={layer['asset']}\n")


if __name__ == "__main__":
    main()
