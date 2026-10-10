# Personagens humanos — UniRp

Base anatômica: **MakeHuman hm08**, 13.380 vértices anatômicos, com UVs de pele.
Não são as malhas Superhero remodeladas. A biblioteca de animações UAL existente
continua sendo usada sobre um esqueleto de 53 ossos com os nomes esperados pelo jogo.
Há quatro bases: homem/mulher adultos e homem/mulher crianças. Crianças usam
macros infantis próprios, além da escala por idade aplicada pelo jogo.

## Origem e licença

Assets gráficos **CC0 1.0**. Licença integral em `LICENSE-CC0.txt`.

- Base, macros, rig e pesos: https://github.com/makehumancommunity/makehuman
- Pacote oficial de pele, roupas, cabelos, olhos, sobrancelhas e cílios:
  https://static.makehumancommunity.org/assets/assetpacks/makehuman_system_assets.html
- Arquivo oficial usado:
  https://files.makehumancommunity.org/asset_packs/makehuman_system_assets/makehuman_system_assets_cc0.zip
- Política de licença: https://static.makehumancommunity.org/about/license.html

Autores originais incluem Data Collection AB, Joel Palmius e Jonas Hauquier.
O pacote oficial declara a liberação CC0 de setembro de 2020 nos próprios arquivos.
A licença do software MakeHuman é distinta da licença dos assets; seu código
de aplicativo não é distribuído aqui.

## Preparação para o jogo

`tools/build_humans.py` gera os arquivos glTF e texturas. Requer Python, NumPy e
Pillow somente na preparação dos assets. O jogo não usa Python nem MakeHuman.

- Anatomia masculina/feminina com combinação de macros do MakeHuman.
- Conversão de unidades para altura base de 1,80 m; altura individual no criador.
- Rig simplificado; pesos faciais no osso Head, expressão em malha separada.
- Ajuste da pose A do hm08 para a pose T usada pelo sistema de animações.
- Pesos transferidos do corpo aos helpers de ajuste das roupas.
- Roupas modeladas e ajustadas à anatomia, com materiais independentes em cima/baixo.
- Cabelo em cartões texturizados com recorte alfa, 9 bases de cabelo.
- Pele com textura de 2048 px, roupa/cabelo de até 1024 px.
- Texturas de pele jovem, meia idade e idosa, selecionadas pela idade do personagem.
- ID anatômico em COLOR_0 na importação, usado apenas para ocultar a pele coberta
  pela roupa. O renderer substitui essas cores por branco antes de desenhar.
- A camada de córnea azul do shader original foi excluída; os olhos mantêm a
  malha de esclera/íris e a textura original, com cor de íris ajustável.

Os assets antigos em `assets/chars` permanecem arquivados no repositório. O jogo
usa `assets/humans`. O preparador consulta apenas a pose dos ossos do rig antigo
para alinhar a biblioteca UAL, sem copiar seu corpo ou rosto.

## Limites conhecidos

Referência estética: inZOI. Estes assets e o renderizador atual não reproduzem
o acabamento completo desse jogo. Não há pele com espalhamento de luz,
cabelo por fios individuais nem escaneamento facial. Três famílias de roupa
por gênero cobrem os estilos existentes; alguns estilos compartilham peças.
Coque/rabo compartilham a base ponytail; tranças/dreads compartilham braid.

O renderer mantém os controles e dados de aparência existentes, sem novo formato
de save. Capturas reais podem ser geradas com as cenas em `tools/human_preview`
e `tools/human_world_preview`; elas não carregam nem salvam a partida do dono.
