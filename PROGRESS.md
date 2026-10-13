# UniRp — PROGRESS.md

Registro de tudo o que foi feito no projeto, para quem for continuar (Claude Code, Codex ou outra pessoa).
Última atualização: **12/out/2026**. Idioma do projeto, dos textos e da conversa com o dono: **português do Brasil**.

---

## 1. O que é o UniRp

RPG de vida com NPCs controlados por IA, passado numa cidade brasileira melancólica ("Porto Cinza" e mais 3 cenários).
Estilo: mundo aberto **isométrico 2.5D em 3D** (visão tipo Project Zomboid / The Sims), conversa com retrato animado da própria pessoa 3D (seção 14), celular com apps, economia estilo Sims, crime, empregos, vícios, clima, eventos.

- **Motor:** Godot 4.7.2 (GDScript). Estado auditado em 12/out/2026: **`forward_plus`** no desktop; `gl_compatibility` no alvo mobile. Forward+ já estava configurado antes da seção 29. Não trocar o renderizador sem autorização do dono.
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
- Rodapé da tela inicial mostra a versão (`v0.9 (11/out)`), para saber qual build está aberto.
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
- Último commit local observado em 11/out: **`b2ceac9` "Personagens MakeHuman, retrato da pessoa 3D e predios que abaixam"**, na branch `main`. Inclui as reformulações 3D/retratos e a primeira parte da seção 15. O estado remoto desta revisão não foi consultado; a última confirmação anterior no GitHub era `650e6a0`.
- Correções e revisões finais da seção 15 estão no diretório de trabalho. Nenhum commit feito pelo Codex nesta rodada. Não commitar sem aprovação explícita.
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


## 15. Movimento humano, individualidade e revisão do início (10–11/out/2026)

**Pedido do dono:** gestos cotidianos mais humanos, caminhada/corrida conforme a
idade, remover a postura corcunda, diferenciar rostos, ampliar a personalização,
dar vida aos ambientes e corrigir travadas/erros e cores de olhos/sobrancelhas.
O dono confirmou que salvou e fechou o jogo; depois pediu para continuar.

**Aplicado**
- `human_motion.gd`: repouso com respiração e pequenas mudanças de apoio,
  movimentos discretos de cabeça, braços durante caminhada/corrida e conversa.
  Perfis de velocidade, aceleração, passada e gestos para criança, adolescente,
  adulto e envelhecimento gradual. Pedestres e jogador seguem esses perfis.
- Removida a curvatura automática da coluna de idosos/adultos. Rotações da
  animação são restauradas antes das camadas de postura/gestos: não acumulam
  inclinação quadro após quadro. Tristeza continua com cabeça discretamente baixa.
- Gestos próprios para comer, beber, lavar rosto/braços, mexer uma panela,
  digitar, descansar no sofá e usar celular. Mãos aproximadas de alvos por
  articulação dos braços; boca acompanha a cabeça também quando sentado.
- Cozinhar, TV, sofá e computador passam pelo fluxo aproximar → alinhar → gesto
  → efeito → encerrar. Reservam cadeira e liberam objetos/pose no fim ou ao
  cancelar. Clique repetido não antecipa efeitos nem gastos. NPCs também podem
  comer/beber sentados em locais públicos; alinhamento ao assento corrigido.
- Amizade/casal: cumprimentar, abraço e beijo com resposta conforme vínculo,
  medo/suspeita e namoro; respeito à recusa, espaço pessoal e limite para afeto
  por repetição. Gestos sociais são aproximados. Bloqueios de menores mantidos.
- Rostos de NPCs sem ajustes personalizados recebem 21 variações determinadas
  pela identidade. A mesma aparência chega ao corpo e ao retrato, sem sortear
  outro rosto ao abrir a conversa. Aparências personalizadas são preservadas.
- Onze controles novos: distância entre olhos, ponte nasal, comprimento do
  queixo, testa, assimetria, peito, cintura, quadril, membros, abdome e estatura.
  Corpo e roupa acompanham os ajustes. Aleatorização inclui esses controles.
- `human_eyes.gdshader` colore somente as íris, preservando pupila/esclera e
  detalhes da textura; heterocromia funcional. `human_brows.gdshader` colore
  pelos independentemente da textura escura. Formato/espessura/altura alteram
  também a geometria das sobrancelhas.
- Três expressões novas: **pensativo, concentrado e aliviado**. Total de 21,
  disponíveis na criação, retrato, personagem e vocabulário da IA. As 18 antigas
  continuam disponíveis. São nuances faciais discretas, não novas malhas de face.
- Cozinha com panela/utensílios/vapor; mesa/computador/cadeira e pontos de uso
  na casa existente. Jardins/entradas com plantas, sapatos e capachos. Folhas
  caindo perto das árvores, com vento e cores sazonais, escondidas em interiores.
  São 32 instâncias numa malha compartilhada; nenhum novo lote/prédio.
- Animações dos quatro corpos preparadas em `.res`, evitando refazer a tradução
  da UAL ao iniciar. Montagem da cidade/pessoas distribuída entre quadros, com
  aviso de progresso visível; entrada e clique repetido bloqueados até ficar pronta.
- Corrigido acesso a rua/layout antes da montagem terminar. Dois avisos GLES3
  de textura ao sair foram reproduzidos isolando um menu cancelado antes do
  primeiro quadro. O céu agora é criado só após a espera inicial da tela;
  reprodução e fluxo completo ficaram sem esses avisos.
- Rodapé atualizado para v0.9 (11/out), com crédito também aos modelos MakeHuman.

**Verificações reais no Godot**
- `human_life_review`: OK — postura após 600 quadros, perfis de idade, corpo,
  geometria/material de sobrancelha, íris/heterocromia, 24 identidades distintas
  e estáveis, aparência personalizada e três novas expressões.
- `life_actions`: OK — dormir/banho/comer/beber/cozinhar/TV/sofá/PC, cancelamento,
  ordem dos efeitos, ocupação/liberação e duplo clique; vínculo/recusa/repetição,
  beijo de casal adulto e bloqueio de menor. Hospital com quatro leitos;
  a ocupação de leitos por pacientes **não foi validada** (amostra tinha zero).
- `age_rules_test`, `social_test`, `calendar_test`: OK — inclui envelhecimento,
  save/load e save antigo sem calendário. `smoke_test`: OK — revisão geral dos
  sistemas/telas/inventário/conversa/economia/criação/save com IA simulada.
- `human_start_review`: OK — início real, uma única navegação mesmo com dois
  cliques, cidade pronta e retorno ao menu; **13.421 ms até ficar pronta**,
  pior quadro **150 ms**. Sem erros de script/shader/textura na execução final.
  Portanto, carregamento e picos ainda precisam melhorar.
- Revisão automática inicialmente bloqueou `smoke_test` por suspeita de apagar
  o save principal. Confirmado caminho separado e adicionada trava explícita
  para limpar somente `user://test_save.json`; nova execução autorizada e aprovada.
- Ferramentas usam partidas em memória/arquivos de teste separados; não alteram
  `save1.json` nem salvam configurações do dono. `git diff --check` sem erros.

**Desempenho**

Porto Cinza, RTX 2060, sem VSync/limite, câmera parada na praça, 600 quadros
após 120 de aquecimento. A versão final fixa a janela em 1280×800 e imprime a
resolução; a amostra anterior não imprimia a resolução. Não é a rota de caminhada.

| Condição | Antes: FPS / pior quadro | Final: FPS / pior quadro |
|---|---|---|
| Dia | 231,2 / 108,8 ms | 249,8 / 90,2 ms |
| Noite | 214,0 / 6,1 ms | 222,8 / 5,5 ms |
| Chuva | 222,8 / 23,6 ms | 182,1 / 35,7 ms |

Resultados variam com moradores/clima e entre execuções; **não demonstram ganho
geral**, e a última amostra de chuva foi pior. A montagem da cidade medida em
2.363 ms inclui esperas entre quadros; os 1.487 ms anteriores eram montagem
síncrona e não representam o tempo total de início. Não comparar esses números
como se fossem o mesmo procedimento.

Rota diurna `perf_walk` (bairro → praça → rodoviária → beco → lanchonete),
1280×800, 28.859 quadros: **222,6 FPS**, percentil 99 do tempo de quadro
**6,9 ms**, pior **106,9 ms**; **três quadros acima de 33 ms**, dois acima de
50 ms. Engasgos no bairro (88,5/35,7 ms) e lanchonete (106,9 ms), sem erros
de script. Cada trecho tem limite de 28 segundos; não é garantia de percurso
completo até cada destino. Essa rota não teve baseline anterior equivalente
nesta rodada, então não demonstra ganho contra a versão anterior.

**Capturas e registros**
- Pasta: `C:/Users/glznc/Documents/Codex/2026-10-10` (inclui revisão de 11/out).
- `motion/cores_e_sobrancelhas.png`, `identidades.png`, `novas_expressoes.png`,
  `carregamento.png`, `inicio.png`; `humans/andar_correr_por_idade.png`, corpos,
  rostos e cidade dia/noite/chuva. Capturas das ações em `app_userdata/UniRp/acao_*.png`.
- Logs finais: `human_life_review_verified.log`, `human_start_review_verified.log`,
  `human_motion_1280_verified.log`, `motion_actions_final.log`,
  `motion_calendar.log`, `motion_smoke_final.log`, `motion_age_rules.log`,
  `motion_social.log`, `motion_walk_verified.log`; reprodução do menu em
  `menu_abort_probe.log`/`menu_abort_fixed.log`.

| Área | Status | Evidência / limite |
|---|---|---|
| Postura ereta e movimento conforme idade | Concluído | Revisão de 600 quadros e galeria real; aprovação estética pendente |
| Mais controles, identidade, olhos e sobrancelhas | Concluído | Materiais/geometria e capturas reais; save personalizado preservado |
| Novas expressões + 18 anteriores | Concluído | Três novas registradas e capturadas em homem/mulher |
| Ações cotidianas e seus efeitos | Concluído | Nove ações/cancelamento/ocupação/duplo clique testados |
| Interações sociais com contato corporal preciso | Parcial | Regras verificadas; abraço/beijo/mãos ainda são aproximações procedurais |
| Ambientes e folhas | Parcial | Implementados nas casas/cidade; todas as estações/cenários ainda não conferidos visualmente |
| Erros ao iniciar/sair e saves | Concluído | Fluxo completo e suites sem erros na revisão final |
| Eliminar travadas e reduzir carregamento | Parcial | Cerca de 13,4 s para iniciar; rota com três picos >33 ms, pior 106,9 ms; chuva variável |
| Acabamento humano equivalente ao inZOI | Parcial | Rig/gestos procedurais, cabelo e pele mantêm limitações; não há captura de movimento |

**Continuidade:** preservar `gl_compatibility`, mapas, lore e saves. Não há
simulação completa de todas as tarefas da vida humana nem acabamento AAA nesta
rodada. Próximo acabamento exige revisar contato de dedos/objetos e duplas,
reduzir custo de gerar rostos/interiores e conferir ambientes nos quatro cenários.
O pedido de mais casas foi atendido com enriquecimento das existentes; construir
novas áreas/prédios não foi executado. Nenhum commit feito pelo Codex.

## 16. Quarteirão urbano de avaliação (11/out/2026)

Novo escopo autorizado: investigar o mundo e preparar **um quarteirão** antes
de expandir a cidade. Continua Godot 4 / `gl_compatibility`, com identidade
estilizada e melancólica. Referências de cidade servem para implantação e detalhe;
não houve cópia de assets, imagens de IA ou mudança do renderizador.

### Diagnóstico real

Detalhes e contagens em `URBAN_DIAGNOSIS.md`. A cidade usa grade 8×8 com blocos
30×30 m e ruas de 10 m. Marcos ocupam um bloco inteiro, mas usam pequena parte
dele; recuos e grama aplicada por padrão explicam o vazio. Há 17 marcos nos quatro
cenários e 148/148/59/145 casas genéricas (Porto/Vale/Nova/Colapso) antes do protótipo.
Já existem 30 pedestres ambientes, 18 veículos dinâmicos, 5 cães, 21 pássaros,
15 pessoas da lore e até 14 moradores extras persistentes. Não são a mesma
população: pedestres ambientes são visuais, e os moradores usam NPCManager.

Há quatro empregos funcionais no JobSystem; as várias fachadas comerciais
decorativas não têm carreira própria. A expansão deve usar as tabelas e sistemas
existentes; não foi criada economia ou população paralela.

### Código e escopo do protótipo

- Mercado Bom Preço, célula (2,2), coordenadas x/z 90–120 m. Só este bloco foi
  densificado. A mesma implantação usa as paletas/desgaste dos quatro cenários.
- Três novas casas `casa_2_2_0..2`, registradas no Houses, com portas, fechaduras
  e interiores existentes. Os pavimentos superiores são fachada nesta rodada.
  Dois anexos fechados pertencem à cenografia do mercado. Marcos, portas e IDs
  antigos permanecem nas mesmas coordenadas; o lote do mercado foi subdividido.
- Alturas variadas, telhados/platibandas, janelas, peitoris, grades, calhas,
  ar-condicionado, passeio com variação, guia de 14 cm com acessos livres,
  grelhas, bancos/abrigo, lixeiras, correio, orelhão, bicicletas e canteiros.
- Tinta de faixa fina e desgastada nos cruzamentos do protótipo; roupa no varal
  com movimento e vento maior na chuva, presa à fachada e acompanhando sua altura.
- Quatro dos mesmos 30 pedestres e um dos mesmos cinco cães redistribuídos
  para o quarteirão, seguindo rotas livres. Carros usam o tráfego existente.
  Irene alterna balcão e prateleiras durante sua rotina original no mercado.
- Corrigidas conexões entre fios e isoladores, placas sem suporte e uma condição
  `or true` que anulava o limite de objetos laterais nos lotes residenciais.
- Chão/chunks/casas montados por etapas, com alvo medido de 6 ms por quadro.
  Uma operação indivisível ainda pode exceder esse alvo. Peças repetidas usam
  as malhas agrupadas existentes, sem um nó separado por peça.
- O aquecimento de NPCs antes montava e destruía cada modelo, e a rotina apagava
  quem saía de cena. Agora os modelos ficam guardados/reutilizados; processamento
  do personagem **e AnimationPlayer** param quando ele está fora de cena.

### Verificação e evidência

Pasta de entrega: `C:/Users/glznc/Documents/Codex/2026-10-11/urban`.
Capturas reais antes/depois dos quatro cenários × dia/tarde/noite/chuva,
galeria, comparações, sequência de movimento, medições e diff estão nessa pasta.
Os testes usam memória e arquivos temporários, sem carregar/gravar a partida real.

- Entradas/saídas das três casas e mercado testadas fisicamente nos quatro cenários.
  Paredes/mobiliário e toda a extensão das rotas de calçada conferidos com física;
  interiores abrem e fachadas voltam ao sair. Todos os imóveis antigos mantêm
  portas e implantação; os lotes novos repetem a mesma geometria por semente.
- NPCs, trânsito, chuva, rotina de Irene e reutilização do mesmo modelo testados.
  O emprego existente de repositor paga R$42 por três horas e consome energia.
- Save/load v1 e fixture antiga sem calendário/residentes carregam preservando
  estados de casas. **Partida real não verificada:** nenhum `save1.json` estava
  na pasta padrão. Nenhum formato de save ou sistema de salários foi alterado.
- Suite geral de sistemas (`smoke_test`) passou. Rota longa chegou fisicamente
  a bairro, praça, rodoviária, beco e lanchonete; média 277,2 FPS, pior quadro
  17,4 ms, nenhum >33 ms. Resolução 1280×800, FPS livre, RTX 2060.
- Comparação curta, limitada a 28 s por trecho: sem densificação 250,4 FPS,
  pior 35,6 ms; com protótipo 242,3 FPS, pior 26,9 ms. Essa comparação mede
  deslocamentos parciais; a rota longa acima confirma chegada aos destinos.
- Capturas panorâmicas custam mais com a densificação. Valores por condição
  ficam em `fps.csv`/`after_verified.log`; não são a taxa limitada por VSync (~59).
  A preparação inicial de modelos ainda produz quadros de cerca de 150 ms.

| Entrega | Status | Verificado × pendente |
|---|---|---|
| Fase A — diagnóstico | Concluído | Código, contagens e rastreamento de custos reais |
| Fases B/C — densidade e rua | Parcial | Um bloco implementado/capturado; expansão aguarda avaliação |
| Fase D — vida e movimento | Parcial | Pedestres, cão, trânsito, gerente e varal; sem novas rotinas completas de todos os moradores |
| Fase E — empregos | Parcial | Vaga/salário/necessidades existentes testados; novas carreiras só propostas |
| Navegação, colisão e fachadas | Concluído no protótipo | Quatro cenários e rota longa; não equivale a validar toda futura cidade |
| Save antigo | Parcial | Fixture v1 verificada; partida real não encontrada |
| Desempenho | Parcial | FPS/picos medidos; primeira geração de modelos/interiores ainda exige trabalho |
| Expansão para a cidade inteira | Não concluído | Depende da validação deste quarteirão pelo usuário |

**Continuidade:** avaliar o quarteirão antes de expandir. Andares superiores
visitáveis, gatos, navmesh geral, novos serviços e salários de NPCs não foram
criados. Preservar os sistemas e os IDs existentes. Nenhum commit realizado.

**Fechamento da avaliação:** nas 16 amostras finais sem limite, mínimo de
147,4 FPS e queda de FPS de 14,1–39,9% frente à referência.
Com limite de 60 FPS em Porto Cinza:
dia/tarde/chuva 60,0; noite 59,6 com um quadro isolado de 96,7 ms sem causa
confirmada. Repetição noturna de 1.800 quadros: 60,0 FPS, p99/pior 16,7 ms.
O pico anterior permanece registrado; não declarar todas as travadas resolvidas.
Galeria, 32 capturas, logs, tabela e diffs disponíveis em
`C:/Users/glznc/Documents/Codex/2026-10-11/urban/` (`VALIDATION.md`,
`galeria.html`, `fps.csv`, `urban.diff`, `working-tree.diff`).

## 17. Revisão do mundo e móveis interativos — 11/out/2026

Pedido: mais detalhe e vida no mundo/interiores, com objetos clicáveis, sentar,
deitar e pegar itens. Continua a regra de revisar **um quarteirão** antes de
regenerar/expandir a cidade. A referência é inspiração; o resultado mantém
geometria estilizada, não pretende reproduzir a qualidade de assets de inZOI.

### Causas encontradas e mudanças

- As gôndolas tinham blocos opacos preenchendo o volume das mercadorias. Foram
  substituídos por estrutura aberta, níveis, embalagens, garrafas e etiquetas.
  O caixa recebeu terminal, área de leitura e mercadorias.
- Faltava um alvo de clique para os móveis. `CityBuilder.objects` registra
  geometria/ponto de uso temporários, com validação de imóvel aberto e acesso.
  Esse registro não persiste itens nem substitui os sistemas de jogo.
- Móveis importados não tinham colisão. Agora têm volume físico; isso expôs
  portas bloqueadas por estantes/cadeiras e bancada no acesso ao banheiro.
  Casas pequenas foram reorganizadas, liberando portas e corredor.
- A fila de movimento existente recebe caminhos locais por AStar2D, consultando
  colisões dos móveis/divisórias. Os caminhos estáticos ficam em cache para até
  oito interiores, com invalidação por geometria/instância/altura/fechadura.
  Ruas e população continuam usando os sistemas originais.
- Cancelamento interrompe o caminho. Voltar à posição de pé só ocorre depois de
  a pose começar; cancelar durante a aproximação não teletransporta para a cama.
  Reservas de NPCs não são removidas por ações de exame do jogador.
- Mais alvenaria, esquadrias/persianas, grelhas, calhas, claraboias, ventiladores,
  reparos e copas irregulares no protótipo. Texturas pequenas e compartilhadas
  de reboco, asfalto, pedra, telhas e madeira são geradas por código; AO/cor de
  vértice continuam ativos. Utensílios/telefone/higiene detalham os interiores.

### Uso e verificação

Clique nos móveis acessíveis para abrir as opções. Cama e assento permitem
permanecer deitado/sentado até interromper; dormir, descansar/TV, cozinhar e
banho só aplicam as ações existentes quando disponíveis. Prateleiras usam
catálogo/preço/inventário reais. Armários/estantes usam a busca já existente do
imóvel. Mesas, cabeceiras, geladeiras e pias têm exame. Nenhum save/economia/IA
paralelo; o formato continua v1.

Evidências: `C:/Users/glznc/Documents/Codex/2026-10-11/urban_v2/`.
Galeria com 16 pares reais dos quatro cenários × dia/tarde/noite/chuva, fachadas,
mercado aberto, interiores/poses e sequência de movimento. O lado anterior é
o **protótipo da seção 16**, capturado antes desta revisão; não a cidade sem
densificação nem a imagem da referência.

- 33 conferências de interação passaram em Porto Cinza: clique visível em cama
  e prateleira; aproximar/deitar/sentar/cozinhar/banho/examinar/compra; banco;
  cancelamento sem teletransporte/entrega, reservas de NPC e save/load v1.
- 1.545 conferências urbanas passaram nos quatro cenários: casas/mercado,
  entrada/saída, colisão, retorno de fachadas, calçadas, marcos/portas/IDs,
  trânsito/cão/gerente e pagamento do emprego existente. Suite smoke: OK.
- FPS livre (RTX 2060, 1280×800): referência 143,9–234,5; revisão 148,9–248,3.
  Pior quadro quente das 16 amostras: 8,6 → 13,2 ms. Porto na chuva teve queda
  de 157,5 → 148,9 FPS. Outros resultados subiram nominalmente, mas os NPCs e
  veículos se movem entre amostras; não atribuir isso a uma otimização comprovada.
- Com limite de 60 FPS: Porto Cinza dia/tarde/noite/chuva 60,0; p99/pior 16,7 ms.
  Preparação inicial de personagens continua produzindo quadros de ~150 ms.
  Caminho de mercado no teste: primeira consulta 14,4 ms, reaproveitado ~1 ms;
  casa reaproveitada ~0,3–0,5 ms. Tempos de consulta não são FPS de sessão real.
- Rota longa e limites finais ficam em `VALIDATION.md`/logs. A primeira rodada
  teve um quadro de 36,6 ms e o trecho bairro terminou a 39,5 m; isso exige
  investigação, não deve ser omitido nem virar afirmação de navegação completa.
- Fixture v1 antiga e round-trip testados; a partida antiga real continua não
  encontrada na pasta padrão. Não afirmar que ela foi carregada.

|Item|Status|Verificado × pendente|
|---|---|---|
|Detalhes do mundo/interiores|Parcial|Protótipo revisado/capturado; avaliação visual e restante da cidade pendentes|
|Interações|Concluído nos casos testados|33 conferências em Porto; não cobre todo móvel de todos os imóveis|
|Portas/fachadas/colisões|Concluído no protótipo|Quatro cenários; navegação geral externa ainda em revisão|
|Save/load|Parcial|Fixtures v1; partida real não verificada|
|Desempenho|Parcial|Comparações e 60 FPS medidos; custos iniciais/rota longa registrados|
|Pegar/reposicionar toda decoração|Não concluído|Falta persistência individual por objeto; proposta abaixo|
|Expansão urbana inteira|Não concluído|Aguarda avaliação do protótipo conforme a regra do dono|

**Sistema que falta:** retirar/rearranjar todo copo, prato ou móvel decorativo
e restaurar sua posição após save/load. Proposta: estado por imóvel no Houses
ligado ao inventário existente, com migração/defaults para v1. Definir essa
persistência antes de implementá-la; não inventar contêiner/save paralelo nem
alterar o formato sem autorização. A busca dos armários atual é por imóvel,
não por cada gaveta/objeto. Pisos superiores e anexos continuam sendo fachadas.

`revision.diff` compara com a entrega anterior reconstituída em memória a partir
do diff/HEAD, verificando o contexto; `working-tree.diff` inclui também alterações
anteriores de personagens. Nenhum commit, stage ou mudança do renderizador.

**Fechamento da rota:** o trace mostrou que o prazo fixo de 120 s era menor que
o necessário para os 336–337 m do percurso, a 2,2 m/s. Não houve bloqueio: o
personagem seguia avançando, `_stuck = 0`, somente contato com o chão. O prazo
do teste agora considera distância/perfil/energia, sem acelerar a simulação.
Repetição chegou em 152,1 s; rodada final em 152,6 s, erro de 0,4 m. Os outros
quatro destinos foram alcançados na rota anterior; juntos confirmam os cinco
destinos, em execuções separadas. Não afirmar que a primeira rodada chegou a todos.

O trace da primeira cama mostrou 1,3 ms de leitura, 1,0 ms de limites e 31,5 ms
em instanciação/material. A textura de madeira agora é preparada no carregamento
e o custo de ~31 ms não apareceu novamente na fila. Ainda houve um quadro de
33,1 ms na rodada final, sem causa integral confirmada; os antigos 35,7/36,6 ms
continuam nos logs. Rota final do bairro: 320,9 FPS médios, p99 4,5 ms, pior
33,1 ms, um >33 ms e nenhum >50 ms. Isso não resolve os ~150 ms da montagem
inicial de personagens. FPS permanece **Parcial**.


## 18. Fase 1 — protótipo de locomoção do jogador (11/out/2026)

**Status: Parcial.** Autorizado após a auditoria da Fase 0 e o pedido para mexer
no jogo com base no documento de movimentação humana. A regra do documento
mantém uma fase por entrega; a Fase 2 não foi iniciada. Evidências e relatório:
`C:/Users/glznc/Documents/Codex/2026-10-11/fase1/RELATORIO.md` e `galeria.html`.

### Causa e alteração

- Antes: adulto andava com Jog_Fwd; criança usava Sprint ao andar. Metadados
  incompletos, redução dupla da passada infantil e limite de reprodução
  prejudicavam a seleção/cadência. A camada procedural apagava 90% dos braços.
- PlayerLocomotion é um helper visual somente do jogador: AnimationTree com
  fase comum, Walk/Sprint (Walk_Formal/Jog_Fwd para idosos), TimeScale por
  velocidade física realmente realizada. Transições de 0,12–0,16 s.
- Calibração offline em quatro bases hm08: 241 poses por clipe, ponto de sola
  estimado por vértices inferiores. A distância efetiva de apoio não equivale
  à distância anatômica entre pegadas. Sprint tem poucos apoios amostrados.
- Mantidos clipes/rig originais; braços coordenados da biblioteca, pequeno
  adicional no tronco. Aterramento visual limitado; corrida mantém fase aérea.
- Ações suspendem/retomam a árvore existente. Velocidades físicas, cápsula,
  navegação, IA/população, necessidades, inventário, economia e save v1 mantidos.
- Testes creation_shots e stress_real agora esperam prontidão assíncrona;
  a primeira execução de stress_real tinha Nil.position e foi descartada
  como validação. Logs anteriores permanecem disponíveis.

### Verificado × pendente

- Suítes obrigatórias: smoke/social/calendar/age_rules/creation/life_actions/
  human_life/human_start passaram nos casos previstos. Revisão de locomoção:
  14 casos de gênero/idade/ação; reconstrução e processo independente repetiram
  fase inicial, clipe e calibração. NPC mantém a ramificação anterior.
- Vídeos reais antes/depois: adulto, criança, idosa, oito direções, paradas,
  diagonal e dia/tarde/noite/chuva em Porto. Rotação final: erro máximo 0,052°.
  O vídeo anterior desativa o novo helper em memória; medidas/capturas também
  foram tomadas antes de editar. Mesmos comandos, poses instantâneas diferentes.
- O ponto de sola estimado teve menor deslizamento e mínimo vertical zero nos
  seis casos finais; **deslizamento ainda não é zero**. Não valida sola completa,
  calçados/desníveis ou contato físico. A cadência visual de Sprint precisa
  avaliação. IK/fixação de apoio ainda não implementados nem com custo medido.
- Comparação pareada, jogador parado, 1280×800/60 FPS: 60,0 nos quatro climas,
  máximo intervalo real 20,02 ms; não equivale a sessão completa em movimento.
- perf_walk antes→depois: dia 269,1→237,3 FPS / pior 32,2→38,2 ms;
  noite 344,1→273,9 / 80,4→121,3 ms; chuva 237,2→205,9 / 30,5→39,5 ms.
  São execuções separadas, com população/caches diferentes; queda nominal,
  sem causa relativa isolada. Não afirmar ausência de custo ou otimização.
  Prazo de 28 s/trecho não confirma chegada a todos os destinos.
- Estresse corrigido de 90 s: sem erro/órfão, um pico de 137,7 ms em sessão;
  quatro voltas do stress_flow completadas. Esse teste de fluxo não mede
  prontidão nos tempos de ~200 ms que imprime.
- Carregamento pareado: 15,291 s; pior delta 150 ms / intervalo real 796,7 ms.
  Picos de montagem e de rota **continuam abertos**, sem causa integral nos
  picos de rota. Não chamar a fase concluída diante do teto de 33 ms.
- Urban review: quatro cenários, IDs/marcos/fachadas/interiores/emprego e
  save/load de fixture v1 OK. Partida antiga real não carregada nesta rodada.
- Nenhum novo modelo, móvel, interação, ambiente mobiliado, prédio ou asset.
  Expansão para NPCs, fachadas, interiores e veículos aguarda avaliação.

Diff incremental desta rodada: `fase1/incremental.diff`, comparado ao snapshot
de 870 fontes anteriores à Fase 1. `working-tree.diff` inclui trabalho anterior.
Nenhum stage/commit/push, alteração do renderizador ou imagem gerada por IA.
Processos de teste encerrados; chave vazia apenas em memória/mocks usados.

## 19 — Marcha estreita e repouso natural compartilhado (11/10/2026)

Pedido do usuário: corrigir pernas abertas e rigidez, com mais posturas naturais
para jogador e NPCs. Expansão visual para NPCs autorizada neste pedido.

- Causa medida: posição exportada do esqueleto com tornozelos masculinos a
  40,9 cm; retargetização mantinha abertura. Correção por rotação de coxa e
  panturrilha sobre os clipes preserva avanço/flexão, sem mudar cápsula/malha.
- Homem adulto caminhando: separação lateral máxima dos ossos dos tornozelos
  42,3 → 14,0 cm; mulher adulta 35,5 → 11,9; criança 30,4 → 9,6;
  idosa 34,7 → 11,7. Medida não equivale à borda dos sapatos.
- Biblioteca visual compartilhada por jogador/NPCs; velocidade de NPC obtida
  do deslocamento horizontal. IA, velocidades físicas e save v1 preservados.
- Cinco repousos determinísticos: relaxado, peso à esquerda/direita, olhar
  ao redor, ajustar manga. Respiração/cabeça suaves; entrada/saída gradual.
  Ações, gestos, guarda-chuva e conversa têm prioridade.
- Revisão final de movimento passou em 10 combinações de idade/gênero/corpo,
  com cinco formas de pose distintas medidas; player_locomotion_review,
  human_life_review, human_start_review e life_actions passaram sem erros.
- Erro intermediário de inferência de tipos corrigido em duas variáveis;
  chuva/estresse dessa execução são inválidos, não usar para conclusão.
- Contato de sola/fixação de apoio ainda parcial: não afirmar deslizamento zero,
  nem validação de todos os sapatos/desníveis. Picos de montagem/rota continuam
  pendentes. Avaliação estética das novas posturas aguarda o usuário.
- Validação final: dia 226,1 FPS / pior 33,3 ms; noite 257,5 / 38,8;
  chuva 185,5 / 38,9, sem limite, 1280×800. Rotas com 28 s por trecho:
  não comprova chegada a todos os destinos. Pareado antes/depois: ~60 FPS
  nos quatro climas com limite 60; pior intervalo final 23,10 ms em chuva.
- Estresse final 90 s: janelas de 183,5–223,7 FPS, zero órfãos, saída 0,
  sem erros; pico de 145 ms na sessão permanece aberto. Quatro ciclos de
  carregar/salvar/menu/criação passaram com fixture v1; save pessoal não usado.
- Vídeo final de 81,5 s, capturas frontais e cinco repousos atualizados;
  dia/tarde/noite/chuva e oito direções. Tempo de encoding não mede FPS de jogo.

Entrega: `C:/Users/glznc/Documents/Codex/2026-10-11/natural_motion`.
Snapshot de 874 fontes, diff incremental separado do diff completo do Git.
Relatório/galeria contêm evidências, limites e medições finais. Sem commit.


## 20 — Protótipo PLAYER de apoio e marcha após auditoria (11/10/2026)

Planos da auditoria autorizados pelo usuário; jogador primeiro, avaliação visual
antes de generalizar para NPCs. Nenhum stage/commit/push.

- Calibração de clipes por corpo; biblioteca privada alinhada e cadência ligada
  ao deslocamento físico. Apoio no mundo, IK de duas articulações, sola curva.
- Pesos inferiores do sapato corrigidos em malha privada do jogador; assets,
  rig53ossos e clipes originais preservados. Primeiro passo/retomada infantil,
  orientação de virada/parada e competição entre mãos/gestos corrigidos.
- Sprint tem menor inclinação frontal; reaproveita cinco repousos existentes.
- Piso físicoY≈0,17 difere de asfaltoY≈0,12 e interiores observadosY≈0,235.
  Consulta visual lê malhas existentes; sombra acompanha piso. Base ampla e
  revestimentos finos são heurística, sem validar rampas/pisos pequenos/shaders.
- Cache agrupava telhados/paredes/móveis altos: filtrar pela faixa do piso reduziu
  pico observado230,4→28,2ms no percurso; não equivale a teto global atendido.
- Matriz154pessoas/462estados/3.176checks:0falhas. ≥2ciclos móveis porpessoa.
  Startup/transições/retomadas cobrem seis sujeitos médios9/30/76; skinning CPU
  esparso não comprova toda superfície GPU. NPCs anteriores preservados na amostra.
- Oito suítes passaram: smoke,life_actions,human_life,human_start,social,calendar,
  age_rules,player_locomotion. Oito direções, uma porta/interior/saída e fachada OK.
  Fixtures isoladas; save pessoal não carregado, formato inalterado.
-13sequências reais antes/depois,2.250amostras porversão, AVI30FPS; GIFs10FPS
  seminterpolação. Maior residual de apoio do vídeo0,0275mm, tolerância2mm.
- FPS antes→depois: dia235,0→228,7; noite271,7→254,2; chuva193,5→192,5.
  Piores34,9→34,1 /35,2→55,5 /51,5→52,4ms. Critério33ms NÃOatendido.
  Perfil curto noturno:37,4ms comatualização de cache;55,5ms não repetido,
  causa integral não isolada. Montagem14,7s/delta150ms continua pendente.
- Fotografias laterais/sete fases inspecionadas; estilo, peso, jerks e expansão
  para NPCs aguardam avaliação do usuário. Não declarar fase completa/perfeita.

Entrega: C:/Users/glznc/Documents/Codex/2026-10-11/sims_player.
Galeria local8770, relatório, diffincremental separado do diff completo doGit.
As tentativas interrompidas/erros de harness são diagnósticos, não evidênciafinal.

## 21 — Locomoção por captura de movimento (Mixamo) com distance matching (12/10/2026)

**Status: Concluído (aguardando avaliação do dono no jogo).** Substitui as seções 18–20
(IK de pés do protótipo e marcha UAL) para jogador **e** NPCs. Pedido do dono: nível inZOI.

- Clipes Mixamo baixados pelo dono (conta Adobe dele) em `assets/anim/mixamo/` (Walk,
  Female Walk, Jogging, Running, Start/Stop Walking, Female Start/Stop, Run To Stop,
  Left/Right Turn, Breathing Idle). Os `.fbx` crus estão no `.gitignore` (licença Mixamo
  proíbe redistribuir); o jogo usa os convertidos `assets/humans/*_mx.res`.
- `world3d/mixamo_bank.gd`: retarget Mixamo -> hm08 com correção de pose de repouso; ciclos
  cortados num passo completo alinhado no apoio do pé esquerdo (detecção circular), raiz
  retirada e guardada como metadado (distância por ciclo, curva de distância das
  arrancadas/paradas, curva de ângulo dos giros, fase por quadro). Reconverter:
  `Godot_console --headless --path . -s tools/bake_mixamo.gd` (~0,2 s por corpo).
- `world3d/mx_locomotion.gd`: estados idle/start/move/stop/turn. Fase dos ciclos avança pela
  distância física (pé não escorrega); arrancada avança pela distância percorrida; parada
  entra no quadro que casa distância restante + posição dos pés; giro parado avança pelo
  ângulo. Mistura andar->trotar->correr pela velocidade; inclinação lateral nas curvas.
  `player_locomotion.gd` fica como reserva se não houver `*_mx.res`.
- Física (`world_view.gd`): WALK_SPEED 2,2 -> 1,6 m/s (caminhada humana); direção e
  velocidade separadas (curva com raio, freia antes de inverter), frenagem ~1 passo,
  giro no lugar antes de sair andando. NPCs: giro limitado, passo menor em curva fechada.
- Testes: `tests/gait_lab.tscn` (folhas de quadros + escorregamento do pé de apoio;
  `GAIT_ALL=1` inclui crianças e idoso). Ajustados ao novo desenho: player_locomotion_review,
  natural_motion_review, human_life_review. Todos OK; perf_walk 210 FPS médio.
  Capturas: `UniRp_capturas/locomocao_mocap/`.

## 22 — Recorte estilo Project Zomboid no lugar do prédio que "abaixa" (12/10/2026)

**Status: Concluído (aguardando avaliação do dono no jogo).** Pedido do dono: o prédio que
tapa o boneco era achatado na vertical (escala Y), espremendo fachada, janelas e letreiro.

- `world_view.gd` `_hide_blockers`: o prédio/casa/loja entre a câmera e o jogador troca para a
  versão recortada já existente (`city.set_cut`): sem telhado, paredes baixas, interior à
  mostra. Raio do meio do corpo até a câmera; folga na borda e 450 ms (tempo real) contra
  piscar. Removidos `_animate_lowering`, `sy_t`, `LOWER_MIN` (nenhuma escala de prédio).
- Paredes do fundo da versão aberta separadas em `cut_back` (inteiras, jogador dentro, como
  antes) e `cut_back_low` (baixas, prédio só tapando quem está fora). Casas (`house_gen.gd`)
  e estabelecimentos (`city_builder.gd` `_location_building`). Portas em nó `doors`, escondido
  quando o prédio abre para quem está fora (a fechadura continua controlando porta aberta/fechada).
- Testes: `hide_shots` reescrito (prédio alto, casa e bar; antes/depois; `HIDE_OUT=<pasta>`),
  `urban_prototype_review` ajustado (na porta de casa virada de costas a casa fica aberta por
  tapar; longe, a fachada volta). smoke/world_detail OK; perf_walk 205 FPS.
  Capturas: `UniRp_capturas/recorte_zomboid/`.

## 23 — Salto visual: Forward+, texturas fotográficas, grama e copas reais (12/10/2026)

**Status: Concluído (aguardando avaliação do dono no jogo).** O dono AUTORIZOU nesta data:
trocar o renderizador para **Forward+** e usar SSAO/SSIL/SSR/normal map (regra 2 da seção 3
fica substituída por esta autorização), baixar texturas fotográficas CC0 e resolução mista
2K/4K. Texturas são fotos escaneadas (ambientCG, CC0), não imagens de IA.

- `project.godot`: `rendering_method="forward_plus"`; globais de shader `wetness`, `rain_time`,
  `player_pos`, `night_glow`. Forward+ rodou mais rápido que o compatibilidade (Vulkan, RTX 2060).
- `world3d/surface.gdshader` + `surfaces.gd`: um shader para todo o Kit (prédio, asfalto, chão,
  objetos, vegetação, telhado). Triplanar no espaço do mundo com arrays de textura (chão 4K,
  resto 2K, BC7 montados sem descomprimir). Material: `Kit.use_surface("nome")` (UV2) ou deduzido
  pela cor/face. A cor do vértice continua sendo a direção de arte (foto normalizada pela média).
  Camadas virtuais: `carpaint`, `lampglow` (acende à noite). Chuva: escurece, espelha, poças com
  respingos (as poças-disco antigas ficam desligadas).
- `tools/prep_textures.py <pasta dos zips>`: gera `assets/textures/surfaces/*_albedo.jpg`,
  `*_nr.jpg` (normal RG + rugosidade B), `layers.json` e `.import`. Os zips foram apagados.
- `world3d/atmosphere.gd`: SSAO, SSIL, sombra suave (PCSS), ACES, glow, SSR com chão molhado,
  névoa e curvas de cor por momento (dia, pôr do sol, noite, chuva). Postes: 20 acesos, 8 com sombra.
- `world3d/grass_field.gd` + `grass.gdshader`: lâminas instanciadas só onde o chão é grama (o Kit
  registra o chão; pisos por cima bloqueiam), vento, pisada do jogador, chuva. Casas registram em
  coordenadas do mundo (`Kit.world_xf`); interiores não registram.
- `world3d/foliage.gd` + `foliage.gdshader`: copas viram cartões de folhas recortadas (LeafSet024)
  com vento e sombra; a esfera vira miolo escuro.
- Móveis (`furn_lib.gd`): madeira/tecido/couro/metal/mármore fotográficos pelo nome do material.
- Grama/copas montadas por orçamento de tempo (2 ms/1,5 ms por quadro), células de 8 m/10 m.
- Testes: `tests/look_shots.tscn` (3 lugares × dia/pôr do sol/noite/chuva/chuva à noite, FPS sem
  vsync; `LOOK_OUT`, `LOOK_TAG`). Regressão OK: smoke, hide_shots, urban_prototype_review,
  world_detail_review, natural_motion, player_locomotion, human_life. perf_walk: 149 FPS médio,
  1 quadro >33 ms. Capturas antes/depois: `UniRp_capturas/visual_antes_depois/` (comparacao.jpg).
- Pendente/limitações: carros e prédios continuam caixas (geometria); pôr do sol ainda puxa para o
  rosa da paleta do cenário; roupas MakeHuman mantêm as texturas próprias.

## 24 — Realismo, rodada 2: GI, relevo, desgaste, nuvens, carros, pele e clima (12/10/2026)

**Status: Concluído (aguardando avaliação do dono no jogo).**

- `atmosphere.gd`: SDFGI (luz rebatida em tempo real), TAA (grama/folhas sem cintilar), neblina
  volumétrica só numa camada rente ao chão que segue o jogador (halos nos postes; névoa global
  apagava a cidade com a câmera a 150 m), respingos de chuva no chão, relâmpagos na tempestade
  (luz fria com sombra, dois pulsos). `apply_quality(n)`.
- Qualidade gráfica nas Configurações (`Settings.graphics`, `user://settings.cfg` [video] qualidade):
  0 Desempenho (sem SDFGI/névoa/relevo), 1 Alto, 2 Ultra (padrão). Vale na hora.
- `surface.gdshader`: parallax occlusion (12 passos, projeção dominante) com alturas reconstruídas
  dos normal maps (`tools/height_from_normal.py`, Frankot-Chellappa; `*_h.jpg` 1K); rejunte escuro e
  musgo entre pedras; paredes com sujeira subindo do chão, escorridos e limo; telhado com líquen;
  asfalto com óleo e remendos; sombras de nuvens passando (global `cloud_shade`); desgaste por
  cenário (global `grime` ← `Art.num("decay")`); água junta primeiro nos baixos do relevo.
- `car_mesh.gd`: sedã e hatch montados por seções (capô, para-brisa, teto, porta-malas, cabine de
  vidro, rodas com calota, faróis/lanternas que acendem à noite). Usado nos carros parados
  (`city_builder._car`) e no tráfego (`life.gd`, sedã/táxi). Corrigida a ordem escala×rotação de
  todas as rodas (`Basis(...) * Basis.from_scale`) — antes viravam "tocos".
- `person.gd`: pele com subsurface scattering (skin mode + transmitância); roupa, cabelo e pele
  molham na chuva (escurecem e brilham; guarda-chuva protege; secam devagar).
- Medidas: regressão OK (smoke, hide, urban, world_detail, natural_motion, player_locomotion,
  human_life). perf_walk Ultra 113,6 FPS (1 quadro >50 ms); Desempenho 139 FPS (0 >33 ms).
  Capturas: `UniRp_capturas/visual_rodada2/` (comparacao_rodada2.jpg: original × rodada 1 × 2).
- Limites: prédios ainda são volumes simples; roupas mantêm as texturas MakeHuman; sem áudio de
  trovão (não há assets de som).

## 25 — Personagens, animais e o que faltava no mundo (auditoria de texturas) (12/10/2026)

**Status: Concluído (aguardando avaliação do dono no jogo).**

- Auditoria automática: `tests/texture_audit.tscn` percorre tudo que é desenhado e classifica
  cada material (shader fotográfico, textura própria, cor lisa) por origem. Antes: ~170 vidros
  de janela, janelas acesas, água, cachorros e pombos em cor lisa; pele/roupa/sapato/cabelo sem
  relevo; logotipo MakeHuman nas camisetas. Depois: só sobram objetos com luz própria (neon,
  luminárias, lanternas de picape/van) e as sombras de contato (decalques).
- Pele (`human_skin.gdshader`): textura 2K + pigmento por vértice, poros (relevo celular em duas
  escalas), oleosidade, SSS skin + transmitância, penugem (rim), molha na chuva (`wet`).
- Roupas/sapatos (`human_cloth.gdshader`): textura da peça tingida + trama real pelo UV:
  algodão (malha, brilho aveludado), jeans (sarja diagonal, fio branco), couro (poros, graxa),
  lã/sarja de terno; poeira/lama na barra e na sola (`hem_top` por peça); encharca na chuva.
  `person._fabric_kind` escolhe o tecido pelo estilo. Cabelo: anisotropia + alpha to coverage.
  Olhos: córnea com clearcoat. Logotipo removido de 3 texturas (manifest.json atualizado).
- Compatibilidade: `face_portrait` lê textura/tom do shader de pele; `enable_xray` (silhueta
  atrás das paredes) funciona com ShaderMaterial e mantém o passe de sinais da pele e a chuva.
- Tela de criação: estúdio fotográfico (luz principal macia com PCSS, preenchimento quente,
  contraluz fria, SSAO, TAA, piso de concreto fotográfico, profundidade de campo).
- Animais (`animal_mesh.gd` + `fur.gdshader`): vira-latas modelados por anéis (caramelo, preto,
  malhado, cinza, bege) com pelagem (fios, dorso/barriga, manchas, brilho de pelo); pombos com
  asas em duas partes e pescoço iridescente. Hierarquia antiga mantida (animação de life.gd).
  `tests/animal_shots.tscn` mostra todos.
- Janelas (`window.gdshader`): interior mapping (sala falsa com piso, teto, paredes, móveis,
  quadro, cortina com pregas), reflexo do céu, cômodo aceso quente à noite (`window_mat`,
  `window_lit_mat` em city_builder; `lit_mat`/`glass_mat` seguem nos outros usos).
- Água (`water.gdshader`): ondas em duas escalas, Fresnel, respingos de chuva. Palmeiras com
  folhas arqueadas e árvores cônicas em camadas (viram copas de folhas reais). Faróis antigos
  duplicados do tráfego escondidos nos sedãs/táxis.
- Medidas: regressão OK (smoke, hide, urban, world_detail, natural_motion, player_locomotion,
  human_life, creation_shots). perf_walk Ultra 103 FPS (1 quadro >33 ms).
  Capturas: `UniRp_capturas/visual_rodada3/` (resumo_rodada3.jpg).
- Limites: corpo/rosto continuam a malha MakeHuman (sem modelagem nova); bichos são modelados
  por código (não escaneados); roupas limitadas às 3 peças MakeHuman por roupa.

## 26 — Correções: travadas, árvores, garagens, cortinas, silhueta (12/10/2026)

**Status: Concluído (aguardando avaliação do dono no jogo).** Pedido: "verifique os erros".

- Travadas medidas com `PERF_HOUSES=1 perf_walk` (entra em 6 casas):
  - Primeira casa aberta travava ~290 ms (FBX + materiais do primeiro móvel): `FurnLib.prewarm`
    carrega os ~46 modelos no carregamento ("Arrumando as casas…").
  - `_update_environment` reescrevia ~200 colisões de porta/luzes a cada 0,5 s: `set_door`,
    `set_interior_light`, `set_house_lit` só mexem quando o estado muda.
  - SDFGI custava ~50 FPS e causava picos: qualidade padrão agora **Alto** (sem SDFGI);
    Ultra continua opcional. Alto: 136–141 FPS entrando em casas (antes 90).
- Árvores do quintal (`house_gen._tree`): cones e "tábuas verdes" trocados pelas espécies do
  Flora (copa frondosa, pinheiro em camadas, palmeira). Palmeira: folhas em segmentos finos
  arqueados (antes bolas/tábuas). Copas mais fechadas (13 cartões/m², cartão 0,52 m) e miolo
  escuro só em copas grandes (tufos pequenos mostravam uma bola lisa).
- Copa entre a câmera e o jogador fica rendada (dither no `foliage.gdshader`, como o Zomboid).
- Carro da garagem ficava atravessando a parede: agora só estaciona na entrada se couber
  (≥ 5,2 m entre casa e calçada), centralizado.
- Cortinas das janelas da frente ficavam em pé no nada com a casa recortada: só nas paredes
  do fundo e só visíveis com o jogador dentro (`s["curtains"]`).
- Silhueta através das paredes virava um "fantasma" branco nas pernas: agora só contorno.
- Ferramentas: `tests/closeup_shots.tscn` (garagens, praça, rua e pessoas de perto).

## 27 — Árvores bugadas, faróis invertidos, braço atravessando o corpo (12/10/2026)

- Ipê branco (e outras flores de pouca saturação) não virava copa de pétalas: ficava a esfera
  lisa com a foto de folhas por cima ("bolinhas"). `Foliage.is_foliage`: toda esfera "veg" vira
  copa. Detalhe da foto por luminosidade (folha verde não pinta flor de verde). Sem miolo sólido
  (aparecia como bola e não sumia na copa rendada); volume pelas camadas internas mais escuras.
  Folhas do tamanho real (janela maior do atlas). Palmeira: folhas com fibra (grama), não pintas.
  `tests/tree_shots.tscn` mostra todas as espécies.
- Faróis do trânsito iluminavam para trás (o SpotLight aponta para -Z; o carro anda para +Z):
  vira 180° e inclina para o chão. `closeup_shots` mede: alinhamento 0,99.
- Criação: a pose de repouso "ajeitar a manga" puxava a mão por IK através do tronco; com a
  captura (mocap) ela não roda mais. Braços: `MxLocomotion._arm_clearance` abre o ombro só o
  necessário para cotovelo/mão ficarem fora do peito/quadril de cada tipo físico.
  Joelhos dobrados ~35° parado (retarget): `_stand_tall` sobe a pelve e refaz a perna por IK
  (170°), pé fixo. `tests/body_arms_shots.tscn` (médio, forte, obeso).

## 28 — Postura, boca, coleta e rodoviária; análise do quadro (12/10/2026)

- Pedido: corrigir peito estufado/corpo torto, boca deformada nas expressões,
  ônibus/rodoviária e coleta no vazio. O dono confirmou que salvou e fechou o jogo.
- Retarget Mixamo v6: ossos axiais transferem rotação relativa ao repouso; não usam
  clavícula/coxa como direção da coluna/pelve. Quatro bibliotecas `_mx.res` reconvertidas.
  Repouso mantém discreta flexão dos joelhos (166°); apoio usa a sola real dos sapatos.
  Girar a prévia do criador não dispara mais a animação de virar andando.
- Boca: centros labiais medidos por malha, mandíbula com dobradiça posterior,
  blend shapes em modo NORMALIZED com vértices/normais absolutos. Retrato usa a
  anatomia oral da pessoa do mundo; retirados o fator 3 da mandíbula e boca/dentes
  pintados no shader. Capturas reais de seis expressões em homem e mulher.
- Coleta: produto exposto registrado na prateleira, aproximação física, alcance da
  palma com IK, dedos fechando, transferência da malha real para a mão e efeito
  aplicado uma vez no contato. Usa Economy/HomeSystem/inventário existentes.
  Cancelar antes do contato não compra. Coleta/exame não teletransportam o jogador
  para onde começou. NPCs compartilham postura/rosto; coleta autônoma não foi integrada.
- Rodoviária: ônibus com carroceria, quatro pneus, janelas, porta, espelhos, faróis,
  bagageiros e ar-condicionado; táxis separados das baias. Cobertura/guichês/sinalização.
  Plataforma, bancos, colunas e malas assentados no mesmo nível da praça.
  Colisão de ônibus/táxis/colunas/guichês/malas. Rotas do jogador usam o AStar físico
  existente no lote e a malha de ruas fora dele, com cache; não há transporte novo.
- Cobertura da rodoviária passou ao recorte existente: personagens/bancos ficam
  visíveis sob ela e o teto/placas reaparecem ao sair, sem achatar a escala.
  Área coberta conta como abrigo no comportamento de chuva; clima completo pendente.
- Revisão final: três percursos reais (entrada, plataforma/bancos e saída) chegaram
  com erro final de 7,6–8,0 cm. Banco e restauração da cobertura passaram. Na última
  execução isolada: cálculo inicial 25,2 ms; cache 0,65–1,01 ms.
  Coleta em prateleira, três alturas e idades 9/76 anos terminou sem retorno por
  teletransporte: palma a 0,22–1,43 mm do alvo na revisão completa. Compra/callback
  únicos, cancelamento, save v1 e fixture antiga sem calendário passaram.
- FPS parado na rodoviária: 156,09 antes; amostras posteriores entre 131,26 e
  156,62 FPS. Última execução isolada: 138,32 FPS, p99 13,076 ms, pior 14,889 ms
  (360 quadros, Alto, 1440×900, RTX 2060, VSync desligado). Há variação entre
  execuções e posições/rotinas de NPCs não foram congeladas: comparação controlada
  e eventual regressão ficam pendentes. Não generalizar para todo o mapa.
  Uma repetição interrompeu rotas antes de chegar; não foi reproduzida no teste
  isolado final. A fixture ganhou foco de texto para evitar teclado externo e
  registro de estado; entrada do jogo permanece igual. Percurso completo não foi concluído com log
  válido; picos de beco/rodoviária em travessia longa continuam pendentes.
- Também passaram nesta rodada: smoke, criação, locomoção por sete perfis,
  human_life, world_detail e restauração do recorte de edifícios. O teste de postura
  compara desvio do repouso nativo (o eixo pelve–cabeça já tem 9,63° no repouso),
  além da inclinação real do tórax; não exige um eixo nativo vertical impossível.
- Limites: todas as combinações extremas de morfologia/expressões, todos os cenários
  e climas, interação autônoma dos NPCs, transporte e save antigo real do jogador
  não foram validados. Ônibus continuam estacionados. Nenhum commit/staging/push.
  O projeto já usava Forward+ no início desta rodada; renderizador não foi alterado.
- Nova solicitação: analisados os 16 cartões da captura do Trello. Há bases reais de
  idade/calendário/social/celular/clima; adoção, rede social/fama, minijogos, crescimento
  diário de cabelo/barba e cinematics completos não foram encontrados. Proposta:
  contato e navegação → rotina reconhecível de três moradores → reações persistentes
  → bairro por horário/clima → eventos locais. Não implementados todos os cartões.
- Evidências externas desta rodada:
  [galeria](C:/Users/glznc/Documents/Codex/2026-10-12/reparo/galeria.html),
  [relatório](C:/Users/glznc/Documents/Codex/2026-10-12/reparo/relatorio.md),
  [análise dos cartões](C:/Users/glznc/Documents/Codex/2026-10-12/reparo/analise_trello.md),
  [diff da rodada](C:/Users/glznc/Documents/Codex/2026-10-12/reparo/alteracoes_desta_rodada.diff).
  `tests/repair_review.tscn` reproduz os casos usando save de teste separado.

## 29 — Câmera dupla integrada e correção da iluminação dos materiais (12/10/2026)

- Pedido: câmera isométrica + terceira pessoa no mesmo mundo, conforme o documento
  `2f58cad9-b523-46e5-a589-95aa02778a00/Texto colado.txt`. O arquivo fornecido termina
  no título da seção 7. O dono confirmou que fechou o jogo e depois dispensou a
  etapa de protótipo/aprovação. Alterações aplicadas diretamente nos arquivos do jogo.
  Não gerar novas galerias HTML, prévias web ou servidores: o dono rejeitou esse fluxo.
- Auditoria: `world_view.gd` cria um CharacterBody3D com cápsula e Person/MxLocomotion;
  movimento usa move_and_slide, AStar/rotas existentes e perfis de idade. Câmera antiga
  ortográfica a 150 m, near 70/far 250; WASD nos eixos isométricos. Interações usam
  objetos registrados em CityBuilder e menus de GameScreen. Settings usa settings.cfg;
  SaveManager permanece VERSION 1. Configurações antes navegavam para outra tela,
  destruindo o mundo e reconstruindo-o ao voltar. Não foi encontrado gamepad existente.
  O desktop já usava Forward+ no início; project.godot não foi alterado nesta rodada.
  Corrigida a informação desatualizada sobre renderizador no início deste documento.
- `world3d/camera_rig.gd`: duas Camera3D, uma ativa, mesmo SubViewport e jogador.
  Isométrica mantém recorte/zoom originais. Terceira pessoa: órbita horizontal,
  inclinação limitada, zoom 1,8–8 m, suavização exponencial, esfera de colisão de 22 cm,
  retração imediata e extensão suave. Teste de sobreposição antes da varredura evita
  usar um pivô suavizado dentro de uma parede. Limite adicional impede recuar por uma
  porta para outro imóvel. Campo de visão abre moderadamente junto a paredes.
- V alterna; botão direito arrastado gira, toque curto mantém menu contextual;
  roda aproxima/afasta; WASD/setas relativos à câmera em terceira pessoa; Shift usa
  a corrida existente; E abre interação próxima usando os mesmos objetos/NPCs.
  Diagonais normalizadas. Trocar segurando uma direção mantém o rumo até soltar a tecla.
  Clique para andar e eixos clássicos continuam na isométrica. Sem salto/controle novo.
  E já avança mensagens narrativas: essa prioridade foi preservada e testada; Enter
  também continua a leitura. Dica de leitura e ajuda atualizadas.
- Cursor recuperado ao soltar o arraste, abrir menus, digitar, perder foco ou sair da
  tela. Configurações agora são sobrepostas à partida; voltar mantém os IDs do mundo
  e do jogador. Modo/atalho V–F6–F7/sensibilidade/inversão persistem no settings.cfg,
  fora do save. Fixtures redirecionam configurações e saves para a pasta externa.
- Qualidade: o shader triplanar perdia o sinal perpendicular das faces -X/-Y/-Z e
  transformava normais pela matriz do modelo sem compensar escala não uniforme.
  Fachadas, objetos e carros recebiam iluminação/reflexos do lado errado. Corrigidos
  sinais, MODEL_NORMAL_MATRIX e rotação do relevo na segunda amostra de textura.
  `surface_review` usa o shader real na GPU, com saída diagnóstica de normal: anterior
  falhou em 9/12 casos; corrigido passou em 12/12, erro máximo 0,0108 (limite 0,035).
  Capturas reais confirmaram parede antes preta com textura/cor legíveis depois.
- Céu em terceira pessoa usa o Sky existente. fog_sky_affect=1 cobria-o totalmente,
  mesmo com pouca névoa; agora influência reduzida em céu aberto e maior na chuva,
  seguindo a gradação existente de horário/clima. Isométrica mantém BG_COLOR.
  Não foram adicionados efeitos pesados ou trocado o renderizador.
- Validação: matriz de câmera com 51 verificações passou; rodada de entrada real via
  Input.parse_input_event passou (arraste/soltar/V/E/W/mensagem/configurações).
  Compra real de água durante troca: contato/callback/pagamento/item únicos.
  Trocas com estados de sentado/comer/deitado preservam ação; esses três casos
  usam estados de fixture, não demonstram todas as atividades completas em terceira pessoa.
  Save v1 e fixture antiga sem calendário carregam; save real do dono não foi usado.
  Regressões: world_detail (33 checks), recorte de prédio/casa/loja, smoke e locomoção
  em sete perfis (idades 9/16/30/76, homens/mulheres) passaram. Parse final sem erros.
- Desempenho: 1280×800, Alto, RTX 2060, VSync desligado, 120 quadros de aquecimento
  e 360 de amostra junto ao mercado. Antes isométrica: 127,55 FPS, p99 16,25 ms,
  pior 17,066 ms. Última rodada com materiais corrigidos: isométrica 122,29 FPS,
  p99 16,468 ms/pior 17,898 ms; terceira pessoa 96,54 FPS, p99 14,749 ms/pior
  18,434 ms. Isométrica ~4,1% abaixo da amostra inicial; execuções variaram entre
  ~110–128 FPS e ~91–99 na terceira pessoa. Rotinas/posição dos NPCs não foram
  congeladas: não atribuir toda a diferença à câmera nem garantir ausência de regressão.
  Comparação totalmente controlada, beco/rodoviária e percursos longos pendentes.
- Limites: terceira pessoa conserva o recorte do imóvel ocupado (interiores ainda
  abertos), não foi feita uma arquitetura fechada de interiores para essa câmera.
  Colisão depende dos obstáculos físicos já existentes; pequenos enfeites sem
  collider continuam sem bloqueio. Nem todos os quatro cenários, climas e corpos
  foram revisados visualmente. Gamepad não implementado. Não concluídos todos os
  cartões do Trello nem uma reconstrução completa de modelos/construções.
- Evidências externas: `C:/Users/glznc/Documents/Codex/2026-10-12/camera_dupla/`:
  `relatorio.md`, `alteracoes_desta_rodada.diff`, `git_diff_atual.diff`, resultados JSON,
  logs e capturas reais (isométrica, terceira pessoa, interior, noite/chuva).
  Diff desta rodada compara com os arquivos copiados antes das alterações;
  git diff completo também contém trabalho anterior. Nenhum commit/staging/push.

## 30. Interiores compartilhados, tetos e andares reais (12 out 2026)

- Pedido atual: corrigir teto/câmera, grama e móveis piscando/desorganizados;
  interiores para prédios, pisos e escadas reais, coerentes nas duas câmeras.
  O dono fechou o jogo e autorizou navegação por andares e save compatível.
  Alterações diretas no jogo, sem galeria HTML/servidor e sem commit.
- Causas: terceira pessoa usava a fachada recortada da isométrica; receitas
  de móveis tinham coordenadas fixas e superfícies quase coplanares; prédios
  genéricos eram caixas com colisão maciça. Cornijas/faixas eram lajes inteiras,
  atravessando novos cômodos e escadas. Circulação local não garantia acesso
  entre cômodos; divisória cortava uma chegada e balcão isolava patamar de loja.
- `world3d/interior_builder.gd` centraliza paredes, janelas recortadas, pisos,
  tetos, cômodos, escadas, mobiliário e os pontos de uso existentes. Colocação
  usa dimensões reais e reserva entradas, corredores, patamares e aproximações.
  Peças menores substituem cama/sofá que não cabem. TV acompanha rack real ou
  recebe suporte de parede; computador acompanha mesa e cadeira reais.
  Slots repetidos em cômodos distintos têm identificadores próprios.
- Terceira pessoa conserva teto e fachada; isométrica mostra o piso ocupado,
  paredes baixas e escadas. Mesmo mundo, corpo, colisão, dinheiro e inventário.
  Janelas têm vãos reais e vidro transparente por dentro; cornijas e faixas
  ficam no perímetro. Não foi alterado o renderizador nem camera_rig.gd.
- Casas e edifícios excluem suas plantas do campo de grama. Interior usa
  material protegido de chuva/limo/escorridos externos, pisos separados dos
  tapetes/sombras e paletas de tecido sóbrias. Móveis mantêm os assets/PBR
  existentes; BRISA/AURORA são marcas fictícias. Luzes/plafons distribuídos em
  cômodos grandes; luz indireta das janelas só na terceira pessoa e em cache.
- Prédios genéricos registram entrada/interior e pisos determinísticos;
  estabelecimentos existentes conservam IDs, serviços, estoque e callbacks.
  Consulta do lote prioriza a planta real: anexos não são capturados pelo lote
  amplo de um marco. Descarregar interior preserva objetos/bancos permanentes.
- AStar2D existente recebe portais, quinas e hubs de cômodos, com varreduras
  físicas e refinamento quando necessário. Caminhos desaceleram nas quinas.
  Escadas conectam um piso por vez e validam a altura de chegada; rampas finas
  dão suporte físico aos degraus visuais. Não há teletransporte entre pisos.
- SaveManager permanece VERSION 1 e com o mesmo arquivo/serializador. Campos
  opcionais pos_height/interior_floor no jogador; saves antigos continuam no
  térreo. Posição salva livre é mantida; se a planta nova tem um móvel/parede
  naquele ponto, recupera uma passagem no mesmo piso durante o carregamento.
- Desempenho: montagem por proximidade prioriza piso ocupado e prepara um
  vizinho/piso por atualização; fachada só abre com interior pronto. Planejador
  reutiliza rotas ainda livres e busca perto antes da grade completa. Igreja
  testada passou de 336 ms para ~10 ms; prédio de ~208 ms para ~14 ms. Todas as
  alternativas continuam sujeitas a encaixe e circulação, sem ignorar colisão.
  Orçamento rígido de 2,5 ms por quadro ainda não está cumprido.
- Verificação nativa: matrizes completas dos quatro cenários, incluindo térreo,
  último piso, móveis essenciais, acessos/colisão, computadores apoiados e
  identificação correta de anexos. Capturas reais de casa/hospital em dia,
  tarde, noite e chuva, nas duas câmeras. Resultados finais e contagens estão
  no relatório externo, separado dos logs históricos de investigação.
  Última matriz: 755 pisos e 3.142 consultas de rota, zero falhas; montagem
  mediana ~8–9 ms e máxima ~20–27 ms entre os cenários (consulta geométrica,
  não caminhada física individual por cada uma dessas 3.142 rotas).
- Escadas: subida/descida física em edifício de seis pisos; save/load,
  reconstrução do mundo no último piso, save sem campos novos e recuperação
  de posição dentro de móvel passaram. Menus reais de subir/descer, entrar/sair,
  sentar/deitar, examinar, cozinha/banho, compra/cancelamento e reservas passaram.
  Revisão da câmera (incluindo entrada real), smoke e sete perfis de locomoção
  passaram. Partida real do dono não foi usada nem sobrescrita.
- Limites: revisão visual não cobre cada imóvel/animação individual; rotina
  dos NPCs permanece no térreo; apartamentos independentes/fechaduras por
  unidade e IK específico de degraus não foram adicionados. Algumas decorações
  opcionais são omitidas para conservar passagem. Malhas de móveis ainda são
  as dos pacotes existentes. Não foram concluídos os outros cartões do Trello.
- FPS e picos: amostras antes/depois usam Alto, RTX 2060, resolução interna
  1366×853 e VSync desligado. NPCs/tráfego não congelados; houve variação grande
  entre rodadas, cuja causa não foi isolada. O relatório registra os limites, incluindo
  montagem fria. Não garantir 59/60 FPS em todo o mapa; beco/rodoviária e percurso
  prolongado continuam pendentes nesta rodada.
- Evidências: `C:/Users/glznc/Documents/Codex/2026-10-12/interiores/relatorio.md`,
  `alteracoes_desta_rodada.diff`, `git_diff_atual.diff`, JSONs, logs e PNGs nativos.
  O diff da rodada compara produção com source_before e inclui fixtures novas;
  diff Git completo contém também trabalho anterior. Nenhum commit/staging/push.
