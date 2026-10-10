# UniRp — PROGRESS.md

Registro de tudo o que foi feito no projeto, para quem for continuar (Claude Code, Codex ou outra pessoa).
Última atualização: **10/out/2026**. Idioma do projeto, dos textos e da conversa com o dono: **português do Brasil**.

---

## 1. O que é o UniRp

RPG de vida com NPCs controlados por IA, passado numa cidade brasileira melancólica ("Porto Cinza" e mais 3 cenários).
Estilo: mundo aberto **isométrico 2.5D em 3D** (visão tipo Project Zomboid / The Sims), conversa por retrato desenhado em código (estilo "I'm Not Human", agora pintado), celular com apps, economia estilo Sims, crime, empregos, vícios, clima, eventos.

- **Motor:** Godot 4.7.2 (GDScript), renderizador **`gl_compatibility`** (não trocar sem autorização do dono).
- **IA:** OpenRouter. A chave e o modelo são configurados pelo dono na tela de Configurações do jogo. **Nunca digitar, pedir ou mostrar a chave.**
- **Pasta do projeto:** `C:\Users\glznc\OneDrive\Documentos\UniRp`
- **Cenários:** `porto_cinza`, `vale_sereno`, `nova_aurora`, `colapso` (`data/cenarios.json`).
- **Modelos 3D:** corpos e cabelos da Quaternius (CC0), animações "Universal Animation Library" (`assets/anim/ual.glb`), móveis Quaternius/Kenney (CC0). **NÃO usar imagens geradas por IA** (o dono rejeitou); tudo visual é desenhado/animado por código.

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

- Commit de referência / último commit: **`0076408` "Direcao de arte: mundo melancolico, brasileiro e com identidade por cenario"**.
- **Nada foi commitado desde então.** Há ~43 arquivos modificados (+5400 / −720 linhas) e ~50 arquivos novos (testes e módulos). O dono ainda não aprovou o commit.
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
- Trocar o modelo base por outro com corpos variados (exigiria baixar modelo CC0 compatível com o esqueleto da UAL — pedir autorização para baixar).
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
