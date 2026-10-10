# UniRp — PROGRESS.md

Registro de tudo o que foi feito no projeto, para quem for continuar (Claude Code, Codex ou outra pessoa).
Última atualização: **10/out/2026**. Idioma do projeto, dos textos e da conversa com o dono: **português do Brasil**.

---

## 1. O que é o UniRp

RPG de vida com NPCs controlados por IA, passado numa cidade brasileira melancólica ("Porto Cinza" e mais 3 cenários).
Estilo: mundo aberto **isométrico 2.5D em 3D** (visão tipo Project Zomboid / The Sims), conversa com retrato animado da própria pessoa 3D (seção 14), celular com apps, economia estilo Sims, crime, empregos, vícios, clima, eventos.

- **Motor:** Godot 4.7.2 (GDScript), renderizador **`gl_compatibility`** (não trocar sem autorização do dono).
- **IA:** OpenRouter. A chave e o modelo são configurados pelo dono na tela de Configurações do jogo. **Nunca digitar, pedir ou mostrar a chave.**
- **Pasta do projeto:** `C:\Users\glznc\OneDrive\Documentos\UniRp`
- **Cenários:** `porto_cinza`, `vale_sereno`, `nova_aurora`, `colapso` (`data/cenarios.json`).
- **Modelos 3D:** personagens MakeHuman hm08 (CC0; seção 13), assets Quaternius antigos arquivados, animações "Universal Animation Library" (`assets/anim/ual.glb`), móveis Quaternius/Kenney (CC0). **NÃO usar imagens geradas por IA** (o dono rejeitou); tudo visual é desenhado/animado por código.

## 2. Como rodar

Executáveis do Godot (instalados via winget, fora do PATH):

```
C:\Users\glznc\AppData\Local\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64.exe          (janela)
C:\Users\glznc\AppData\Local\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64_console.exe  (testes, imprime no terminal)
```

- Abrir o jogo: `Godot_v4.7.2-stable_win64.exe --path C:\Users\glznc\OneDrive\Documentos\UniRp`
- Rodar um teste: `Godot_..._console.exe --path . res://tests/<nome>.tscn`
- Rodapé da tela inicial mostra a versão (`v0.8 (10/out)`), para saber qual build está aberto.
- Capturas de tela dos testes vão para `C:\Users\glznc\AppData\Roaming\Godot\app_userdata\UniRp\` e as organizadas para o dono ficam em `C:\Users\glznc\OneDrive\Documentos\UniRp_capturas\`.
- Save do jogo: `user://save1.json` (= `...\app_userdata\UniRp\save1.json`). Configurações: `user://settings.cfg`.

## 3. Regras do dono (valem para qualquer agente)

1. **Nada de commit sem aprovação.** Sempre mostrar `git diff`/lista de arquivos antes.
2. **Não trocar o renderizador** (`gl_compatibility`) sem apresentar opções e receber autorização. Sem depender de SSAO/SSR/normal map.
3. **Não alterar** conteúdo de diálogos, economia, necessidades, inventário, movimento, colisão, **formato do save** e IA dos NPCs, **exceto** onde o dono autorizou (caixa de diálogo, menus, ações animadas, e os sistemas novos de calendário/idade/social descritos abaixo).
4. **Saves antigos precisam continuar carregando** (campos novos sempre com valor padrão).
5. Preservar os mapas e o commit de referência `0076408`; **não adicionar prédios**.
6. **Medir FPS antes/depois** (baseline ~59 FPS no início; hoje 145–205 nos testes), validar com **capturas reais do Godot**, apresentar **tabela de status** (Concluído / Parcial / Não concluído / Bloqueado) separando o verificado do não verificado.
7. **Rig e animações do personagem 3D não podem quebrar** (só posições de vértices e ossos por cima da animação).
8. Estilo do retrato: desenhado por código, nunca imagem de IA. Mudanças grandes de estilo: mostrar opções antes.
9. Menores de idade: o jogador pode ser criança/adolescente, **com bloqueios** (ver seção 5.8). Nada sexualizado.
10. Nunca digitar senhas/chaves pelo dono. Comunicação em pt-BR.

## 4. Estado do git

- Commit visual de referência: **`0076408` "Direcao de arte: mundo melancolico, brasileiro e com identidade por cenario"**.
- Último commit confirmado localmente e no GitHub: **`650e6a0` "Personagens, calendario, vida social e mundo vivo"**. O dono commitou e enviou as rodadas anteriores.
- As reformulações 3D e dos retratos das seções 12–14 estão no diretório de trabalho, sem commit. Não commitar sem aprovação explícita.
- Rodapé de commit exigido pelo ambiente: `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>` (ou o modelo em uso).
- Terminações de linha: o repositório mistura CRLF e LF; o git avisa "LF will be replaced by CRLF". Ao editar por script, preservar a terminação do arquivo.

## 5. O que existe hoje (por área)

### 5.1 Arquitetura rápida

| Pasta | Conteúdo |
|---|---|
| `autoload/` | Sistemas globais (singletons): `GameState`, `TimeManager`, `World`, `NPCManager`, `PhoneSystem`, `CrimeSystem`, `HomeSystem`, `JobSystem`, `BusinessSystem`, `AddictionSystem`, `WorldEvents`, `NewsSystem`, `Population`, `Houses`, `Economy`, `SaveManager`, `Settings`, `NeedsSystem`, `AIService` e os **novos** `AgingSystem`, `Holidays`, `SocialSystem` |
| `ai/` | Prompts da IA (`prompts.gd`), respostas rápidas locais (`local_dialogue.gd`, `dialogue_lines.gd`), checagem de ações, motor de expressão |
| `data/` | JSON: locais, NPCs, itens, origens, traços, aparência, imóveis, móveis, cenários, emoções |
| `ui/` | Telas (menu, criação, configurações, jogo), tema "madeira e papel", caixa de diálogo, celular, retratos (`ui/face/`), fundos do menu (`ui/menu/`) |
| `world3d/` | Cidade 3D isométrica gerada por código (`city_layout`, `city_builder`, `house_gen`, `mesh_kit`, `chunk_kit`, `flora`, `furn_lib`), pessoas (`person.gd`), vida ambiente (`life.gd`), `world_view.gd` (câmera, NPCs, ações, clima, corte de paredes) |
| `tests/` | Testes e ferramentas de captura (ver seção 7) |
| `assets/` | Modelos CC0 |

Autoloads ficam registrados em `project.godot` (ordem importa: `Settings` antes de `TimeManager`).

### 5.2 Fases do projeto (histórico anterior, já commitado)

1. Fase 1: base (autoloads, conversa com IA, necessidades, save).
2. Fase 2: celular (mensagens, contatos, banco, jornal).
3. Fase 3: crime e serviços (polícia, hospital, arrombamento, empregos).
4. Fase 4: economia estilo Sims (contas, aluguel, móveis, negócio próprio).
5. Fase 5: mundo vivo (cenários, eventos, jornal, moradores gerados).
6. Fase 6: visual 3D (cidade isométrica, pessoas 3D, direção de arte por cenário) — commits até `0076408`.

### 5.3 Rodada 09/out (não commitada): visual, interface e interações

- **Mundo/gráficos:** chuva por superfície, poças, iluminação e materiais, fachadas, ruas, identidade por cenário, árvores variadas (`flora.gd`), sombras de contato suaves, vertex AO, `ChunkKit` (chunks de 80 m por categoria), desempenho (FPS subiu de ~59 para 145–205).
- **Corte estilo Sims:** só o prédio onde o jogador está se abre; paredes de trás ficam altas; silhueta de raio-x do jogador atrás de paredes (shader com `depth_test_inverted`, `DEPTH = FRAGCOORD.z + 0.004`).
- **Interiores:** casa do jogador (quarto, cozinha, banheiro com chuveiro, sala, jantar) e hospital (leitos com cortinas, consultório, recepção, farmácia), móveis em fila com orçamento por quadro.
- **Ações animadas:** dormir, banho, comer/usar item (aproximar → alinhar → animar → efeito real → fim; andar cancela antes do efeito). `world_view.start_action`, `_update_action`.
- **NPCs com vida:** sentar, conversar em dupla, celular, olhar, mexer, pegar, agachar, consertar, deitar em leitos; ocupação de cadeiras/camas.
- **Caixa de diálogo estilo Stardew/Sims** (`ui/game/dialogue_box.gd`): só aparece com interação; retrato à direita; máquina de escrever; fila de mensagens; log roteado (toast × caixa).
- **Menu de pausa** com "Salvar jogo", "Salvar e sair para o início", "Sair sem salvar"; tema "madeira e papel" em todos os menus; tela inicial com nuvens, fumaça, vinheta e grão; fundo `skyline_bg.gd` nas telas de criação/configurações.
- **Personagem 3D:** `person.gd` com roupas geradas da própria malha, rim, blob de sombra, animações retargetadas (`anim_bank.gd`).

### 5.4 Rodada 10/out: retrato, criação, idade, calendário

- **Retrato pintado** (`ui/face/face_paint.gd`, estende `face_rig.gd`): sem contorno preto; pele com sombreamento que segue o volume; cabelo em massas com mechas; barba, rugas, 18 expressões (as do jogo), bases de idade (criança/adolescente/adulto/idoso). Camadas estáticas gravadas em cache (`_cached`) — a conversa ficou mais rápida. Ligado em criação, HUD e conversas. (Alternativas testadas e descartadas: render 3D do modelo e o desenho antigo com contorno.)
- **Tela de criação nova** (`ui/character_creation.gd`): 13 categorias (identidade, idade e aniversário, rosto, olhos, sobrancelhas, nariz e boca, orelhas, pele e marcas, cabelo, barba, corpo, roupa e acessórios, história), prévia ao vivo em retrato **ou corpo 3D girando**, linha "Editando: …", "Aleatorizar esta parte/tudo", miniaturas clicáveis (cabelo, barba, roupa, formato do rosto), 12 tons de pele, formato dos olhos, orelhas, rugas, 3 estilos de barba novos (`bigode fino`, `barba curta`, `costeletas`), cor da barba, cor secundária da roupa.
- **Calendário** (`autoload/time_manager.gd`): ano de 12 meses; **ritmo configurável (3, 7 ou 28 dias por mês; padrão 7 → ano de 84 dias de jogo)**; começa em 1º de março de 2026; `date()`, `date_str()`, `short_date_str()`; trocar o ritmo não pula a data; save guarda `calendar`; saves antigos ganham data a partir de março de 2026.
- **Aniversários e envelhecimento** (`autoload/aging_system.gd`): cada pessoa tem `nascimento {m, d}` (dia guardado em escala de 28 para sobreviver à troca de ritmo); aniversário vira evento; +1 ano (se "Envelhecer" estiver ligado em Configurações); mudança de faixa nos 13, 18 e 60 anos; NPCs envelhecem por dia, só mudando um número (idade nova vai em `state[id]["idade"]` e é restaurada no load).
- **App Calendário no celular** (`ui/phone/phone_panel.gd`): ano inteiro, aniversários (rosa), feriados (verde), contas vencendo (laranja), próximos aniversários e botão "Mandar parabéns". Data também no HUD, pausa, tela inicial.
- **Configurações:** ritmo do calendário e envelhecer ligado/desligado (`Settings.days_per_month`, `Settings.aging`).

### 5.5 Rodada 10/out: mundo vivo e vida social

- **`autoload/holidays.gd`:** 17 datas brasileiras (Ano-Novo, Carnaval, Sexta Santa, Tiradentes, Trabalho, Mães, Namorados, São João, Pais, Independência, Aparecida/Crianças, Finados, República, Consciência Negra, Véspera de Natal, Natal, Réveillon), **proporcionais ao mês curto**. `World.is_open()` respeita feriados: Ano-Novo/Natal fecham quase tudo; feriados nacionais deixam mercado só de manhã; vésperas e festas fecham às 14–16h; hospital, delegacia, praça e casas nunca fecham. Emprego: feriado não conta falta. Festas (Carnaval, São João, Réveillon, Consciência) abrem "Festa na praça". Feriado aparece no HUD, jornal e calendário.
- **`autoload/social_system.gd`:**
  - **Repetição irrita:** 2ª vez "já falou isso", 3ª irritado, 4ª xinga, 5ª vai embora e evita o jogador; relação piora; criança reclama sem palavrão.
  - **Aviso de patamar** da relação (amigo, melhor amigo, não gosta, inimigo, desconfia, ex).
  - **Flerte namorando → fofoca:** quem viu sabe; a fofoca anda de pessoa em pessoa a cada hora de jogo; chegando no parceiro ele desconfia, perde afeto, manda mensagem e pode terminar (`ex`); parceiro presente vê na hora.
  - **Aniversário:** "Dar parabéns" no menu da pessoa, presente no dia vale mais, quem faz anos comemora no bar à noite (ou praça), convites e parabéns por mensagem.
  - **Dia dos Namorados:** esquecer magoa o parceiro; qualquer contato/presente no dia conta.
- **Pessoas de todas as idades:** `Population.generate_young()` (crianças 6–12 e adolescentes 13–17, estudam de manhã, brincam à tarde); pais jovens saem com **bebê no carrinho** (`npc["bebe"]`); início de jogo garante 1 jovem e 1 pai/mãe com bebê. Violência/flerte/roubo contra menor bloqueados.
- **Clima:** na chuva quem está na rua abre **guarda-chuva** (cores variadas; jogador também) ou anda encolhido; ninguém senta em banco molhado; amigos acenam ao jogador; festa e comemoração têm gente dançando (`Dance`).
- **Imobiliária:** `HomeSystem.list_city_houses()` anuncia até 9 casas vazias das ruas do mapa (aluguel/compra; casas abandonadas baratas para reformar); casa alugada fica destrancada e dá para dormir nela. Nenhum prédio novo.
- **Crianças e bebês no 3D:** corpo próprio de criança/adolescente, cabeça proporcionalmente maior, passada proporcional à altura.

### 5.6 Corpo e rosto 3D (`world3d/person.gd`)

- **Corpo remodelado** (o modelo "Superhero" original foi aplainado): `SHAPE` (por gênero e faixa de idade) × `BODY_TYPES` (**7 tipos físicos** = campo "corpo" da criação: magro, médio, atlético, forte, acima do peso, obeso, esquelético). `_shape_for()`, `_reshape()` (braços/pernas/pescoço/mãos por eixo do osso, tronco, barriga, ombros) e `_smooth_torso()` (tira músculos esculpidos e recalcula normais). Cada combinação gênero × idade × tipo gera uma malha (~150 ms na 1ª vez, depois em cache `_shaped`); `world_view._prewarm_bodies()` gera todas as dos NPCs no carregamento.
- **Mulher** com proporção própria (ombros estreitos, cintura, quadril, pescoço fino, busto menor); **homem** sem aparência de super-herói.
- **Roupas:** geradas da malha do corpo (folga + caimento), barras/golas retas (`_straighten_hems`), costura soldada, cores por vértice.
- **Rosto 3D com expressão** (o modelo não tem blendshapes): sorriso, boca triste, piscar, queixo ao falar (blendshapes **por delta** gerados por código) e sobrancelhas (erguer, bravas, tristes); postura por emoção e por idade (idoso curvado, cabeça baixa quando triste). Cabeça usa largura/comprimento do rosto desenhado (`_head_vec`).
- **Mãos/objetos:** guarda-chuva (malha única por cor, no máx. 3 abertos por quadro), carrinho de bebê, aceno (`wave()`), tudo posto por cima da animação (`_apply_hands`).
- Chave `Person.face_fx` desliga rosto/postura (para medir FPS).

### 5.7 Interface e conversa

- `ui/game_screen.gd` (HUD, pausa, atualização no aniversário, chip de feriado), `ui/main_menu.gd` (data e idade no save), `ui/settings_screen.gd`, `ui/phone/phone_panel.gd` (apps: Mensagens, Contatos, Banco, Contas, Imóveis, Compras, Jornal, **Calendário**, Emergência).
- A conversa usa o retrato pintado (`FaceRig = face_paint.gd`).

### 5.8 Bloqueios para menores (`GameState.minor_block`, `refuse_minor`, `refuse_item_for_minor`)

Menor (<18) não: compra/usa bebida, cigarro, droga, arma, ferramenta de crime; comete crime (opção some da lista e é recusada); é contratado (bico a partir de 14); aluga/compra imóvel, abre negócio; dirige; namora/flerta. Origem "Saiu da prisão" bloqueada; carro inicial removido. A IA recebe regras fixas (`Prompts.minor_rules`) e as respostas locais ao flerte recusam. Ninguém ataca/flerta/rouba criança.

## 6. Decisões já tomadas pelo dono (não reabrir sem motivo)

- Retrato: **opção B, pintado** (descartadas: render 3D do modelo e retrato antigo).
- Calendário: **meses de 7 dias** (ano = 84 dias de jogo, ~34 h jogadas por ano); ritmo configurável.
- Jogador **pode** ser criança/adolescente, com bloqueios.
- Rosto 3D: **deformar por código** (em vez de só linguagem corporal).
- O corpo 3D não deve ser "super-herói": corpos comuns, variados, homem/mulher realmente diferentes.
- Os NPCs têm vida social completa (relações, fofoca, aniversário, feriados, clima, crianças e bebês, mais imóveis) — feito na rodada 10/out.

## 7. Testes e ferramentas (`tests/`)

Executar com `...console.exe --path . res://tests/<nome>.tscn`. Os que terminam com `RESULTADO ...: OK` são de regressão.

| Teste | O que cobre | Estado em 10/out |
|---|---|---|
| `smoke_test` | Sistemas gerais, criação, conversa, crime, economia, mundo | OK |
| `ui_flow` | Fluxo de menus, pausa, salvar/carregar | OK |
| `calendar_test` | Datas, ritmos, aniversário (jogador e contato), faixas de idade, save/load, save antigo, app Calendário | OK |
| `age_rules_test` | Bloqueios de menor, prompt da IA, flerte | OK |
| `social_test` | Repetição, patamares, fofoca, parabéns, feriados, Namorados, crianças, imobiliária | OK |
| `creation_shots` | Tela de criação (categorias, 3D, 12 aleatórios únicos, começar como adolescente) | OK |
| `life_actions` | Dormir/banho/comer animados, cancelar, hospital | OK |
| `cut_shots` | Corte de paredes | OK |
| `perf_walk` | FPS andando (`PERF_HOUR`, `PERF_RAIN`, `PERF_SCEN`, `PERF_SEM_ROSTO=1`) | dia ~188 / noite ~205 / chuva ~157 FPS |
| `talk_perf` | Desempenho da conversa | ~105–115 FPS durante a conversa |
| `stress_real` | Jogo com relógio acelerado, andando em loop, chegada de moradores (`STRESS_SEG`, `STRESS_VEL`, `STRESS_CHUVA`, `STRESS_SAVE`, `STRESS_TRACE`) | sem vazamento |
| `stress_flow` | Menu → continuar → jogo → sair → criação, 4 voltas (`STRESS_SAVE`) | sem vazamento |
| `stress_creation` | Tempo de cada categoria e da prévia 3D | engasgos de ~140 ms só na 1ª vez |
| Capturas | `portrait_shots`, `char3d_shots` (`CHAR3D_MODO=rosto/idade/corpos`, `CHAR3D_GENERO`), `ages_ingame`, `life_rain_shots`, `social_shots`, `char_closeup`, `char_ingame`, `menu_shots`, `life_shots`, `scenario_shots` | geram PNGs em `app_userdata\UniRp\` |

Dica: para testes que conversam com a IA, usar `AIService.mock = Callable` (ver `smoke_test._mock`) para **não gastar a chave do dono**.

## 8. Investigação de travadas (10/out) — o que se sabe

O dono relatou que o jogo "travou muito" e que precisou reiniciar o PC. **Não consegui reproduzir** a trava. Evidências:

- Log do Godot sem erros; Windows sem evento de queda de vídeo/memória (o reinício foi iniciado pelo usuário).
- Estresse com relógio acelerado (200 s) e com o save real do dono (150 s): memória estável (~130 MB do Godot, ~700 MB RAM / ~1,2 GB privados do processo), nós e objetos estáveis, threads/handles constantes, FPS 130–170.
- Troca repetida de telas (menu ↔ jogo ↔ criação, 4 voltas): sem vazamento.
- Conhecido e **ainda por resolver**:
  - engasgos curtos de ~130–150 ms quando personagens novos aparecem (provavelmente a placa compilando o desenho na 1ª vez; não aparecem nas etapas medidas do código do mundo);
  - **carregar o jogo leva 2,7–6 s** com a janela parada (sem tela de "Carregando…");
  - gerar o corpo de um tipo novo custa ~150 ms na primeira vez (já mitigado: o carregamento pré-gera os corpos dos NPCs).
- **Ideia a testar (não aplicada):** durante o carregamento, desenhar de verdade cada tipo de personagem (minúsculo, junto ao jogador, por ~0,5 s) para a placa compilar tudo antes; medir com `stress_real` (linha de base: 8–12 quadros >60 ms em 170 s numa partida nova; 1–3 em 150 s com o save real).
- **Sugestão:** adicionar um monitor de diagnóstico que grave em `user://diagnostico.log` quadros >250 ms com contexto (tela, hora do jogo, lugar, nº de NPCs, memória), para capturar a trava se acontecer de novo; e uma tela "Carregando…".
- Atenção ao medir FPS: **não rodar testes pesados enquanto o dono joga** (eles usam a GPU sem limite de FPS e travam o jogo dele).

## 9. Pendências e ideias (nada disso foi começado)

**Personagens**
- Rosto 3D igual para todo mundo do mesmo gênero (falta variar nariz, mandíbula, olhos conforme o rosto desenhado); só 6 malhas de cabelo para 14 estilos; bigodes/costeletas sem malha no 3D.
- Pernas ainda têm a silhueta musculosa do modelo original; diferença entre "atlético" e "forte" sutil de longe.
- Criança no 3D ainda com pernas de proporção adulta; bebê é simples (cabeça + manta), não é NPC próprio.
- Modelo base substituído por MakeHuman CC0 a pedido do dono (seção 13). Melhorar acabamento de cabelo/pele e fidelidade dos estilos de roupa continua pendente.
- Verificar tranças, dreads, moicano e rabo de cavalo no retrato; miniaturas da criação não atualizam ao mexer em outra categoria.
- Confirmar no jogo (câmera isométrica, 4 cenários) os corpos novos.

**Mundo**
- Identidade arquitetônica por cenário; expandir interiores para outros prédios; persistência de objetos (exige campos de save e autorização); picos isolados à noite; roupa preta escura demais à noite (Colapso); frestinha clara na cintura entre camisa e calça em alguns corpos; casa alugada na imobiliária ainda sem móveis dentro; cidade só gera moradores crianças via `Population`.
- Com a IA ligada: **não verificado** o comportamento do parceiro traído e dos NPCs reagindo a repetição em conversa real (só testado com respostas simuladas e locais).

**Qualidade**
- FPS na chuva depois de otimizar os guarda-chuvas (malha única, sem sombra): ~157 FPS medido; antes da otimização 145.
- Rodar uma revisão (`/code-review`) antes do commit, dado o tamanho do diff.

## 10. Armadilhas técnicas aprendidas (leia antes de mexer)

**Renderizador `gl_compatibility`**
- `GeometryInstance3D.transparency` **não funciona**; `render_mode depth_test_inverted` funciona (usado na silhueta).
- Máximo de 8 luzes por objeto; sem SSAO/SSR. MSAA 2D não existe (serrilhado do `draw_*` é inevitável: por isso retrato com malhas e bordas suaves em vez de contorno grosso).
- Malhas com blendshape: o blendshape precisa ser **delta** em relação à base e trazer as normais/tangentes da base (senão a luz fica errada).
- Mesh com blendshape não pode manter `FLAG_COMPRESS_ATTRIBUTES` ao recriar a superfície.

**Corpo/roupa**
- **Não deslocar o braço inteiro para dentro**: o pivô dos dedos desalinha e a mão abre como garra. Deslocar só ombro/clavícula com queda antes do cotovelo.
- Recorte de roupa por triângulo gera zigue-zague; por isso `_straighten_hems` e a regra "2 vértices dentro + 3º colado". Vértices de costura duplicados precisam andar juntos (`weld`).
- Posturas/gestos por cima da animação só mexem em rotação de osso depois de `ap.advance`.

**Godot/GDScript**
- Variáveis `var x := valor_variante` dão erro de inferência ("Warning treated as error"): tipar explicitamente.
- Funções com nome igual à da classe pai quebram (`_lock` já existia em `face_rig.gd` → usei `_mecha`).
- `--check-only` não enxerga autoloads (erro "Identifier not found: GameState/TimeManager" é falso positivo): valide rodando o `smoke_test`.
- `Population`, `NPCManager` etc. só existem com o jogo carregado; ao testar, chamar `NPCManager.reset_state(origin)`.
- Em testes, `world_view.realtime = false` para o relógio não correr sozinho; **no jogo real ele corre 1 min de jogo por segundo**.
- Em testes de ações dos NPCs, esperar `NPCManager.busy == false` (um evento da noite pode deixá-lo ocupado).

**Ambiente Windows**
- Python do Windows não abre caminhos > 260 caracteres: usei `C:/Users/glznc/AppData/Local/Temp/cmp` para scripts de patch.
- Ao matar testes com `timeout`, conferir se sobrou processo `Godot*` (`Get-Process Godot*`).
- Pasta do projeto está no OneDrive: se aparecer comportamento antigo no outro PC, o OneDrive ainda não sincronizou.

## 11. Para quem continuar

1. Ler as **seções 3 (regras)** e **10 (armadilhas)**.
2. Rodar `smoke_test`, `social_test`, `calendar_test`, `age_rules_test`, `creation_shots` e `life_actions` antes e depois de qualquer mudança em sistemas.
3. Mudou algo visual? Gerar captura real (não basta compilar) e mostrar ao dono antes/depois.
4. Mudou desempenho? Medir com `perf_walk` (dia/noite/chuva) alternando ligado/desligado; **não** com o dono jogando.
5. Só commitar com aprovação explícita do dono.


## 12. Rodada Codex — 10/out: personagens mais sóbrios e humanos

Pedido do dono: reformular totalmente a direção do boneco 3D, com referências
The Sims / Project Zomboid nas características físicas e tom melancólico e
sombrio de I'm Not Human. Autorizada a reformulação de corpo, materiais,
rosto, cabelo e expressão. O retrato pintado 2D continua com seu estilo aprovado.

**Implementação**
- `world3d/person.gd`: adulto com braços, pernas, mãos, pescoço e peito menos
  volumosos; cintura menos heroica, suavização do relevo muscular dos membros;
  cabeça adulta ligeiramente menor e postura de repouso mais contida.
- Roupas mais soltas, materiais foscos, normais reconstruídas pela roupa;
  detalhes de abertura/gola/costura na malha. Cabelo com menos brilho;
  recortes de bigode/costeleta/cavanhaque e barba por fazer pintada na pele;
  coque convertido de dois volumes laterais para um volume atrás da cabeça.
- `world3d/human_style.gd`: cabeça separada do corpo compartilhado, subdivisão
  curva e anatomia individual. Nariz, mandíbula, queixo, maçãs, lábios,
  olhos e orelhas usam os controles físicos existentes. Pele com olheiras,
  pigmento dos lábios e sulcos de idade; textura de detalhe obtida por código
  do próprio asset CC0. Cor dos olhos desenhada por código.
- Expressões: 8 deformações na pele + 3 nas sobrancelhas + fechamento do olho;
  tensão da boca/testa, olhos semicerrados, sorriso assimétrico, piscar e fala.
  São combinadas nas 18 emoções existentes; continuam obedecendo ao LOD.
- `world3d/world_view.gd`: prepara também as anatomias individuais dos moradores
  durante o carregamento. Caches de rosto e olhos limitados a 96 entradas.
- `tests/human_style_review.gd/.tscn`: galeria real de rostos, corpos, expressões
  e sete tipos físicos; confere deformação, índices/rig e pesos dos vértices.
  `HUMAN_REVIEW_OUT` escolhe a pasta de capturas; padrão em `user://`.

**Limites do visual**
O rig e os assets CC0 existentes foram remodelados por código, sem baixar um
modelo externo. O resultado continua sendo realismo estilizado, com algumas
características do cabelo e da topologia originais. A aprovação estética do dono
ainda depende de ele ver as capturas e o jogo atualizado.

**Verificado nesta rodada**
- `smoke_test`, `social_test`, `calendar_test`, `age_rules_test`,
  `creation_shots` e `life_actions`: todos terminaram em `OK`.
- A galeria `human_style_review`: `OK`, com capturas reais do Godot.
- Saves do dono não foram utilizados nos testes (cada teste usa seu arquivo).
- Sem mudanças em renderizador, economia, colisão, mapas, diálogos ou formato
  do save. Nenhum commit feito pelo Codex.

**Desempenho nesta máquina (RTX 2060)**
- Antes: dia 165,2 FPS / noite 196,6 FPS (rota `perf_walk`).
- Primeira versão, antes do cache de anatomias: dia 169,1 FPS, mas 3 quadros
  de 131–145 ms entrando no bairro. Por isso foi acrescentado o cache/preparo.
- Revisão com caches: dia **151,9 FPS** (pior quadro 21 ms; zero >33 ms);
  noite **171,1 FPS** (pior 142,1 ms; 5 >50 ms); chuva **135,2 FPS**
  (pior 95,1 ms; 3 >50 ms). Medido antes do acabamento final de preenchimento
  de luz dos materiais e retirada dos símbolos de emoção padrão.
- Os testes sorteiam moradores, então esses números não isolam perfeitamente
  o custo do visual. Houve queda nas médias versus as medidas anteriores;
  a investigação de engasgos continua parcial, não foi resolvida nesta rodada.
- Capturas reais geradas nos quatro cenários (`char_ingame`), incluindo
  dia/noite/chuva e zoom distante. Conferidos frente/isométrico e galeria.
- Ajuste final: preenchimento muito discreto nos materiais de pele/roupa para
  preservar a silhueta à noite; símbolos de emoção acima da cabeça passam a
  ser opcionais (`set_emotion(..., true)`), com expressões físicas como padrão.
- A galeria foi executada novamente após os acabamentos e terminou em `OK`.

| Área | Status | Evidência / limite |
|---|---|---|
| Proporções, materiais e rosto 3D | Concluído | Capturas reais e controles físicos testados |
| Expressões e compatibilidade das animações | Concluído | Galeria + `life_actions` e criação em `OK` |
| Compatibilidade dos sistemas e saves | Concluído | Seis testes existentes em `OK` |
| Redução de engasgos | Parcial | Sem engasgo no teste diurno; persistem à noite/chuva |
| Aprovação estética do dono | Não concluído | Aguardando avaliação das capturas e jogo |

Arquivos desta rodada: `PROGRESS.md`, `world3d/person.gd`,
`world3d/human_style.gd`, `world3d/world_view.gd`,
`tests/human_style_review.gd`, `tests/human_style_review.tscn`.
Nenhuma aprovação para commit foi solicitada ou presumida.


## 13. Rodada Codex — 10/out: substituição da base 3D, referência inZOI

O dono rejeitou o acabamento da seção 12 e autorizou permanecer no Godot,
substituir totalmente corpo e rosto e usar as fotos do inZOI como referência
anatômica e de realismo. A rodada anterior ficou aquém da referência.

**Troca aplicada**
- O jogo usa `assets/humans/Human_male.gltf`, `Human_female.gltf` e versões
  `_child`. São novas malhas anatômicas MakeHuman hm08, não deformações da
  topologia Superhero. 13.380 vértices anatômicos por base, UVs de pele e rig
  de 53 ossos, com aliases para o sistema de animações existente.
- Bases infantis geradas com macros de criança. Escala por idade e altura
  individual continua no renderer. Adolescentes usam a transição adulta.
- Roupas próprias do pacote: gola, botões, dobras, mangas, bolsos e jeans.
  Três famílias por gênero, com cores independentes em cima/baixo.
- Nove bases de cabelo com textura e recorte alfa; sobrancelhas e cílios
  texturizados; olhos com íris/esclera originais e cor de íris configurável.
- Pele de 2048 px, versões jovem/meia idade/idosa. Texturas reais CC0 do
  MakeHuman, sem geração de imagens por IA e sem copiar assets do inZOI.
- Controles existentes de tipo físico, nariz, mandíbula, queixo, lábios,
  olhos, orelhas e idade continuam alimentando o renderer; oito expressões
  faciais combináveis, sobrancelhas, cílios e barba acompanham a expressão.
- Pose de repouso mais natural: mãos abertas, braços soltos e pernas menos
  afastadas. Caminhada/conversa/sentar continuam usando UAL retargetada.
- O preparador alinha a pose A do MakeHuman à pose T da UAL. Consulta somente
  posições dos ossos do rig antigo, sem usar seu corpo, rosto ou cabelo.
- Pesos dos helpers de roupa transferidos do corpo; pele coberta ocultada
  pelas máscaras das peças. IDs anatômicos em COLOR_0 evitam erros quando o
  importador reordena vértices; substituídos por branco antes de desenhar.
- `world3d/person.gd` e `human_style.gd` removem os antigos geradores de roupa,
  remodelagem de herói e auxiliares de suavização sem uso.

**Origem/reprodução**
- Base/rig/macros/pesos: repositório oficial makehumancommunity/makehuman.
- Cabelo, roupa, pele e detalhes: pacote oficial `makehuman_system_assets_cc0.zip`.
  Um espelho antigo foi consultado durante a pesquisa, mas os arquivos usados
  foram substituídos pelos arquivos do pacote oficial, com declaração CC0.
- `assets/humans/README.md`, `LICENSE-CC0.txt` e `manifest.json` documentam
  origem, licença e hashes. `tools/build_humans.py` prepara os assets com
  Python/NumPy/Pillow; nenhum desses programas é exigido pelo jogo.
- Os assets Quaternius antigos permanecem arquivados no repositório.

**Conferido nesta rodada**
- Importação/compilação do Godot e capturas reais de corpo/rosto, expressões,
  sete tipos físicos, variações de pele/cabelo, idosos e jovens.
- Poses de caminhada, sentado e conversa conferidas visualmente. As capturas
  mostraram problemas de roupa/pose/olhos na primeira versão; eles foram
  corrigidos e as capturas geradas novamente.
- Capturas reais na cidade nos quatro cenários, dia/noite/chuva. A iluminação
  noturna do mundo continua escura e ainda limita a leitura da roupa preta.
- Ferramentas: `tools/human_preview.tscn` e `human_world_preview.tscn`.
  Capturas em `C:/Users/glznc/Documents/Codex/2026-10-10/humans`.
- Não foram executadas suítes funcionais nesta rodada. Compatibilidade de
  saves, ações como banho/dormir e fluxo completo de criação não foram
  revalidados por testes; o formato de save e os sistemas não foram alterados.

**Desempenho — amostras curtas, personagem parado, 1280×800, RTX 2060**

| Cenário | Dia | Noite | Chuva |
|---|---:|---:|---:|
| Porto Cinza | 164,4 FPS | 154,8 FPS | 154,1 FPS |
| Vale Sereno | 157,7 FPS | 147,3 FPS | 138,4 FPS |
| Nova Aurora | 150,0 FPS | 152,1 FPS | 141,7 FPS |
| Colapso | 162,3 FPS | 152,8 FPS | 154,4 FPS |

600 quadros por amostra, após 120 quadros de aquecimento, sem limite de FPS.
Os piores quadros diurnos foram 90,9–98 ms. A medição não percorreu a rota
`perf_walk` usada anteriormente (151,9/171,1/135,2 FPS na seção 12), portanto
**não demonstra ganho ou perda comparável**. NPCs/clima são variáveis entre
execuções. A investigação das travadas continua parcial.

**Limites do resultado**
A base foi substituída, mas o acabamento completo de inZOI ainda não foi
atingido. Cabelo continua usando cartões de malha, pele não tem espalhamento
de luz e rostos não são escaneados. Alguns estilos de roupa/cabelo compartilham
peças (coque/rabo, tranças/dreads). A aprovação estética depende do dono.
Renderizador continua `gl_compatibility`; mapas, retratos 2D, sistemas e
campos de save mantidos. Nenhum commit feito.

| Área | Status | Evidência / limite |
|---|---|---|
| Substituir corpo e rosto Superhero | Concluído | Quatro bases hm08, capturas reais |
| Anatomia, materiais e controles físicos | Concluído | Galerias de corpo/rosto/idade/tipo físico |
| Animações principais | Concluído | Caminhada, conversa e sentado nas capturas |
| Demais ações, saves e fluxos | Não concluído | Sem revalidação funcional nesta rodada |
| Acabamento completo inspirado no inZOI | Parcial | Cabelo, pele e variedade de roupa ainda limitados |
| Investigação das travadas | Parcial | Amostras curtas; picos diurnos de até 98 ms |
| Aprovação estética | Não concluído | Aguardando avaliação das capturas pelo dono |

Arquivos desta rodada: `world3d/person.gd`, `world3d/human_style.gd`,
`assets/humans/*`, `tools/build_humans.py`, `tools/human_preview.gd/.tscn`,
`tools/human_world_preview.gd/.tscn`, `PROGRESS.md`. Alterações anteriores de
`world3d/world_view.gd` e `tests/human_style_review.gd/.tscn` foram preservadas.


## 14. Retratos com a mesma identidade do personagem 3D (10/out/2026)

**Pedido do dono:** substituir o rosto 2D pelo mesmo rosto do personagem 3D,
com cabelo/nariz/boca iguais, mais realismo, apresentação melancólica e todas
as expressões. Direção autorizada pelo pedido e pelas referências do inZOI.

**Aplicado**
- `ui/face/face_portrait.gd` substitui o retrato pintado na criação, HUD e
  conversa. Apresenta a mesma anatomia MakeHuman e o mesmo `LookBuilder` em
  um SubViewport transparente; nenhuma feição é redesenhada em polígonos 2D.
- Mesmos cabelos, cores, roupa, idade, proporções do rosto, nariz, lábios,
  olhos e orelhas da pessoa 3D. Pose frontal e enquadramento de rosto/ombros.
- Luz quente lateral, preenchimento frio, sombra, fundo desfocado procedural,
  vinheta discreta e tratamento suave dos tons claros. Renderizador mantido.
- As 18 emoções existentes continuam com a mesma API (`set_emotion`, `talk`).
  Piscadas, maxilar durante a fala, inclinação da cabeça, lágrimas, suor,
  rubor, palidez, olheiras e hematomas. Sem os balões desenhados de emote do
  retrato antigo: a apresentação passa a enfatizar o rosto.
- `portrait_person.gd` mantém a anatomia neutra do mundo e amplia a abertura
  do maxilar para a câmera próxima, com interior bucal/dentes discretos.
  Cache com assinatura própria evita modificar a expressão do modelo do mundo.
- A criação mantém oito atalhos e ganha o seletor “Todas as expressões…”.
- Miniaturas capturadas uma vez: o SubViewport/mundo 3D é liberado depois.
  Retratos vivos são atualizados a 24 Hz; escondidos deixam de renderizar.
  Reconstrução limitada a uma pessoa por quadro e atrasada 120 ms nos controles.
- `world3d/human_features.gd`/`human_marks.gdshader` passam a representar marcas
  e acessórios em ambas as apresentações: óculos, piercings, brincos, boné,
  corrente, sardas, cicatriz, tatuagens, pintas, queimadura e maquiagem.
  Nariz quebrado é uma deformação compartilhada; dente de ouro no retrato.
  São representações procedurais, sem assets do inZOI ou imagens de IA.
- Arquivos do retrato pintado antigo preservados como histórico/ferramentas.
  Sem mudança em mapas, lógica da IA, formato do save ou conteúdo do jogo.

**Capturas e desempenho**
- Ferramenta de captura `tools/portrait_preview.gd/.tscn`: não lê/salva a
  partida do dono e não chama a IA. Galeria de idade/pele, 18 emoções de
  homem/mulher, 14 opções de cabelo, acessórios, criação e caixa de conversa.
- Capturas: `C:/Users/glznc/Documents/Codex/2026-10-10/portraits`.
- Amostra isolada com seis retratos visíveis, 1280×800, RTX 2060, sem VSync,
  quatro segundos: anterior 39,9 FPS; novo 1515,0 FPS da janela de captura.
  O novo desenha a cena dos retratos a 24 Hz e reapresenta a textura entre
  atualizações; esse número alto **não é FPS da cidade, nem taxa da animação**.
  Não foi medido antes/depois numa partida ou rota comparável.
- Capturas reais renderizadas sem erro de script/shader na versão final.
  Fala, ida/volta entre retrato e corpo 3D conferidas visualmente. Após as
  miniaturas, restam dois SubViewports na criação (retrato e prévia de corpo),
  em vez de um mundo 3D ativo por miniatura.
  Suítes funcionais e carregamento de saves não executados nesta rodada.

| Área | Status | Evidência / limite |
|---|---|---|
| Mesma base de rosto/cabelo do 3D | Concluído | Mesma malha, aparência e texturas |
| As 18 expressões e fala | Concluído | Galerias reais de homem/mulher; código de fala preservado |
| Criação, miniaturas, HUD e conversa | Concluído | Capturas reais das telas |
| Marcas e acessórios | Parcial | Representações procedurais; exemplos capturados, nem todas as combinações revistas |
| Acabamento equivalente ao inZOI | Parcial | Limites de cabelo, pele e modelo permanecem |
| Desempenho no jogo completo e saves | Não concluído | Só amostra isolada; sem suíte funcional |
| Aprovação estética | Não concluído | Aguardando avaliação do dono |

Arquivos desta rodada: `ui/face/face_portrait.gd`, `portrait_person.gd`,
`portrait_skin.gdshader`, `portrait_finish.gdshader`, `ui/character_creation.gd`,
`ui/game_screen.gd`, `world3d/human_features.gd`, `human_marks.gdshader`, pequenos
ajustes em `world3d/person.gd`/`human_style.gd`, `tools/portrait_preview.gd/.tscn`,
`PROGRESS.md`. Nenhum commit feito.
