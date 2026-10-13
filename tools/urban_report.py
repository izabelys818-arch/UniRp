"""Organiza apenas capturas reais e medições gravadas pelo Godot."""
import csv
import json
import re
import os
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(os.environ.get("URBAN_OUTPUT", "C:/Users/glznc/Documents/Codex/2026-10-11/urban"))
REFERENCE = os.environ.get("URBAN_REFERENCE_PHASE", "before")
SCENES = {"porto_cinza": "Porto Cinza", "vale_sereno": "Vale Sereno", "nova_aurora": "Nova Aurora", "colapso": "Colapso"}
MODES = {"dia": "Dia", "tarde": "Tarde", "noite": "Noite", "chuva": "Chuva"}
PATTERN = re.compile(r"URBAN SAMPLE (\w+) (\w+) (\w+) fps=([\d.]+) p99_ms=([\d.]+) worst_ms=([\d.]+) draws=([\d.]+) visible_peds=(\d+)")
records = {}
for log in [REFERENCE + ".log", "after_verified.log"]:
    for match in PATTERN.finditer((ROOT / log).read_text(encoding="utf-8-sig")):
        phase, scenario, mode, *values = match.groups()
        phase = "before" if phase == REFERENCE else phase
        records[(phase, scenario, mode)] = dict(zip(["fps", "p99_ms", "worst_ms", "draws", "visible_peds"], map(float, values)))

rows = []
for scene in SCENES:
    for mode in MODES:
        a, b = (records[(phase, scene, mode)] for phase in ["before", "after"])
        rows.append({"cenario": SCENES[scene], "condicao": MODES[mode], "fps_antes": a["fps"], "fps_depois": b["fps"], "variacao_percentual": round((b["fps"] / a["fps"] - 1) * 100, 1), "p99_antes_ms": a["p99_ms"], "p99_depois_ms": b["p99_ms"], "pior_antes_ms": a["worst_ms"], "pior_depois_ms": b["worst_ms"], "pedestres_antes": a["visible_peds"], "pedestres_depois": b["visible_peds"]})
with (ROOT / "fps.csv").open("w", encoding="utf-8-sig", newline="") as f:
    writer = csv.DictWriter(f, fieldnames=rows[0])
    writer.writeheader()
    writer.writerows(rows)

font = ImageFont.truetype("C:/Windows/Fonts/segoeui.ttf", 24)
small = ImageFont.truetype("C:/Windows/Fonts/segoeui.ttf", 18)
for scene, title in SCENES.items():
    sheet = Image.new("RGB", (1280, 4 * 440), "#17201f")
    draw = ImageDraw.Draw(sheet)
    for row, (mode, label) in enumerate(MODES.items()):
        for col, phase in enumerate(["before", "after"]):
            pic = Image.open(ROOT / (REFERENCE if phase == "before" else phase) / f"{scene}_{mode}.png").convert("RGB")
            pic.thumbnail((640, 400))
            x, y = col * 640, row * 440
            sheet.paste(pic, (x, y + 40))
            caption = ("Protótipo anterior" if REFERENCE != "before" else "Antes") if phase == "before" else "Revisão"
            draw.text((x + 12, y + 6), f"{title} · {label} · {caption}", font=small, fill="#ece8dd")
    sheet.save(ROOT / f"comparacao_{scene}.jpg", quality=93)

scene_options = "".join(f'<option value="{k}">{v}</option>' for k, v in SCENES.items())
mode_options = "".join(f'<option value="{k}">{v}</option>' for k, v in MODES.items())
data = {f"{scene}_{mode}": {phase: records[(phase, scene, mode)] for phase in ["before", "after"]} for scene in SCENES for mode in MODES}
html = '''<!doctype html><html lang="pt-BR"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>UniRp — avaliação do quarteirão</title>
<style>body{margin:0;background:#151d20;color:#e6e1d5;font:16px system-ui}main{max-width:1280px;margin:auto;padding:24px}h1{font-size:27px;margin:0 0 8px}p{color:#bdbdb5;line-height:1.5}select,input,button{background:#293638;color:#e6e1d5;padding:10px;border:1px solid #536058;border-radius:5px}nav{display:flex;gap:12px;flex-wrap:wrap;margin:20px 0}.comparison{position:relative;aspect-ratio:1.6;overflow:hidden;border:1px solid #607168}.comparison img{position:absolute;inset:0;width:100%;height:100%;object-fit:contain}.before{clip-path:inset(0 50% 0 0)}.line{position:absolute;height:100%;left:50%;border-left:2px solid white}.badge{position:absolute;top:12px;background:#172020dc;padding:8px;border-radius:4px}.left{left:12px}.right{right:12px}input[type=range]{width:100%;padding:0;margin:16px 0}.stats{background:#243033;padding:16px;border-radius:8px;line-height:1.6}a{color:#cbbf96}h2{font-size:20px}.grid{display:grid;grid-template-columns:1fr 1fr;gap:12px}.grid img{width:100%}@media(max-width:700px){.grid{grid-template-columns:1fr}}</style>
<main><h1>UniRp · quarteirão do Mercado Bom Preço</h1><p>Capturas reais do Godot. Três moradias, anexos do mercado, rua usada e presença humana. Apenas este quarteirão recebeu a densificação.</p>
<nav><label>Cenário <select id="scene">SCENES</select></label><label>Condição <select id="mode">MODES</select></label><a id="originalBefore" target="_blank">Abrir antes</a><a id="originalAfter" target="_blank">Abrir depois</a></nav>
<div class="comparison"><img id="after"><img id="before" class="before"><div id="line" class="line"></div><span class="badge left">Antes</span><span class="badge right">Protótipo</span></div><label>Comparar <input id="slider" type="range" min="0" max="100" value="50"></label><div class="stats" id="stats"></div>
<p>1280 × 800, Compatibility, RTX 2060, limite de FPS e sincronização vertical desativados. Mesma câmera, horário e clima; movimento ambiente continua durante as amostras de 600 quadros. As capturas não são imagens geradas nem montagens de cenários inventados.</p>
<h2>Fachadas, interior e movimento</h2><div class="grid"><a href="after/porto_cinza_fachadas.png"><img src="after/porto_cinza_fachadas.png" alt="Fachadas das casas"></a><a href="after/porto_cinza_mercado_interior.png"><img src="after/porto_cinza_mercado_interior.png" alt="Interior funcional do mercado"></a><img src="movimento.gif" alt="Sequência real de pedestres e veículos"></div>
<h2>Limites desta entrega</h2><p>Os andares superiores e anexos são fachadas; o térreo das casas é acessível. Novos estabelecimentos e carreiras aguardam a avaliação do protótipo. Save v1 antigo foi verificado com uma fixture; a partida real não estava na pasta padrão. A preparação inicial dos modelos ainda possui quadros longos.</p><p><a href="fps.csv">Tabela completa de FPS</a> · <a href="urban.diff">Alterações para revisão</a></p></main>
<script>const data=DATA;const scene=document.getElementById('scene'),mode=document.getElementById('mode'),slider=document.getElementById('slider');function update(){let key=scene.value+'_'+mode.value;let a=data[key].before,b=data[key].after;document.getElementById('before').src='before/'+key+'.png';document.getElementById('after').src='after/'+key+'.png';document.getElementById('originalBefore').href='before/'+key+'.png';document.getElementById('originalAfter').href='after/'+key+'.png';document.getElementById('stats').textContent=`FPS: ${a.fps} → ${b.fps} | Pior quadro: ${a.worst_ms} → ${b.worst_ms} ms | Pedestres ativos próximos: ${a.visible_peds} → ${b.visible_peds}`;}scene.onchange=mode.onchange=update;slider.oninput=()=>{document.getElementById('before').style.clipPath=`inset(0 ${100-slider.value}% 0 0)`;document.getElementById('line').style.left=slider.value+'%';};update();</script></html>'''
html = html.replace("SCENES", scene_options).replace("MODES", mode_options).replace("DATA", json.dumps(data))
if REFERENCE != "before":
    html = html.replace("'before/'", repr(REFERENCE + "/")).replace('badge left">Antes', 'badge left">Protótipo anterior').replace('badge right">Protótipo', 'badge right">Revisão')
    html = html.replace('<h2>Fachadas, interior e movimento</h2>', '<h2>Mercado: interior anterior e revisão</h2><div class="grid"><figure><img src="reference/mercado_interior.png" alt="Interior do protótipo anterior"><figcaption>Protótipo anterior</figcaption></figure><figure><img src="after/porto_cinza_mercado_interior.png" alt="Interior revisado"><figcaption>Revisão: gôndolas abertas e mercadorias visíveis</figcaption></figure></div><h2>Fachadas, interior e movimento</h2>')
    html = html.replace("Apenas este quarteirão recebeu a densificação.", "A comparação mostra o protótipo anterior e a revisão de superfícies, fachadas, vegetação e interiores. Apenas este quarteirão recebeu a densificação.")
    html = html.replace('<h2>Limites desta entrega</h2>', '<h2>Interações reais</h2><div class="grid"><img src="interactions/deitar.png" alt="Personagem deitado"><img src="interactions/sentar.png" alt="Personagem sentado"><img src="interactions/acao_cozinhar.png" alt="Cozinhando"><img src="interactions/acao_banho.png" alt="Tomando banho"><img src="interactions/mercado_interior.png" alt="Retirada de mercadoria"><img src="interactions/menu_cama.png" alt="Menu real da cama"><img src="interactions/menu_prateleira.png" alt="Menu real da prateleira"></div><p>Menus da interface real em uma partida de teste. Na captura da interface, os mesmos popups foram embutidos na janela para aparecerem na imagem.</p><h2>Limites desta entrega</h2>')
    html = html.replace("Novos estabelecimentos e carreiras aguardam a avaliação do protótipo.", "Clique em camas, assentos, fogões, banheiras, armários e prateleiras. Compras e atividades usam economia, inventário e necessidades existentes. Nem todo objeto decorativo pode ser levado ou reposicionado; essa persistência ainda precisa ser definida. Novos estabelecimentos e carreiras aguardam a avaliação do protótipo.")
    html = html.replace('<a href="fps.csv">Tabela completa de FPS</a>', '<a href="VALIDATION.md">Relatório de verificação e pendências</a> · <a href="fps.csv">Tabela completa de FPS</a>')
(ROOT / "galeria.html").write_text(html, encoding="utf-8")
frames = [Image.open(p).convert("RGB").resize((800, 500)).quantize(colors=128) for p in sorted((ROOT / "movement").glob("*.png"))]
if frames:
    frames[0].save(ROOT / "movimento.gif", save_all=True, append_images=frames[1:], duration=200, loop=0, disposal=2)
print(json.dumps({"comparacoes": len(rows), "fps_min_antes": min(r["fps_antes"] for r in rows), "fps_min_depois": min(r["fps_depois"] for r in rows), "pior_ms_antes": max(r["pior_antes_ms"] for r in rows), "pior_ms_depois": max(r["pior_depois_ms"] for r in rows)}))
