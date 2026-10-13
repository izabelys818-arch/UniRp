# UniRp — diagnóstico e distrito de avaliação (11/10/2026)

## Escopo

Somente o quarteirão do Mercado Bom Preço, célula (2,2), x/z 90–120 m.
As quatro ambientações recebem este mesmo protótipo, usando as paletas e o
desgaste existentes. A expansão para os demais quarteirões depende da avaliação
do usuário. Correções de suporte de placas, conexão dos fios e reutilização de
personagens atingem os componentes existentes da cidade.

## Fase A — descoberta no projeto

### Geração, ocupação e navegação

`world3d/city_layout.gd`: grade 8×8, quarteirões de 30×30 m, ruas de 10 m,
cidade de 330×330 m. Os IDs de `data/locations.json` são ordenados e distribuídos
pela coordenada desejada, procurando a célula livre mais próxima. Os demais
blocos usam a semente 7741 e o perfil de `art_style.gd` para escolher tipologia.
Casas genéricas são divididas em duas fileiras de 2 ou 3 lotes.

Cada marco reserva um bloco completo. O mercado ocupa 300 dos 900 m²;
uma residência importante ocupa apenas 120 m². Recuo frontal de 5 m nos marcos,
3,2 m nas casas genéricas, corredores laterais e o preenchimento padrão de
grama em todo bloco explicam o isolamento. Não há uma textura de grama sendo
repetida: são superfícies de cor por vértice e manchas geométricas.

Rotas usam A* nos cruzamentos. Personagens ambientes percorrem faixas laterais;
jogador/NPCs persistentes ainda usam o centro das ruas entre acessos. Não existe
navmesh geral que evite qualquer objeto automaticamente. Mobiliário novo deve
deixar rotas e portas livres e ter sua colisão verificada.

### Contagem anterior ao protótipo, medida em execução

| Cenário | Marcos | Blocos de casas | Casas genéricas | Torres | Comércio decorativo (blocos) | Estacionamentos | Verde | Terrenos |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| Porto Cinza | 17 | 34 | 148 | 6 | 0 | 3 | 3 | 1 |
| Vale Sereno | 17 | 34 | 148 | 1 | 2 | 0 | 7 | 3 |
| Nova Aurora | 17 | 13 | 59 | 18 | 13 | 1 | 1 | 1 |
| Colapso | 17 | 33 | 145 | 3 | 4 | 2 | 0 | 5 |

Os 17 marcos se classificam em 4 imóveis de tipo casa, 1 bar, 6 públicos,
2 serviços, 2 comida, 1 loja e 1 hospedagem. Hospital, delegacia e igreja têm
tratamentos específicos no construtor, embora sua classificação de dados seja
mais ampla. Cada bloco comercial desenha 3–4 fachadas dentre 12 nomes;
essas fachadas não têm inventário, interação ou carreira própria.

### População, tráfego e trabalho

- `NPCManager`: 15 pessoas da lore, com relações e rotinas por horário.
- `Population`: até 14 moradores extras persistidos na partida; geração local
  ou pela IA configurada. Moradores não são os mesmos personagens ambientes.
- `Life`: 30 pedestres visuais, 18 carros dinâmicos (quatro modelos), 5 cães e
  21 pássaros. Culling e simulação barata à distância já existem. Não há gatos.
- Pedestres estavam distribuídos por até 81 cruzamentos; somente dois apareciam
  perto do mercado nas capturas de referência. Quatro dos mesmos 30 foram
  redistribuídos para o protótipo, sem criar uma segunda população.
  Um dos mesmos cinco cães também circula no passeio do mercado, usando a
  mesma rota livre das pessoas, em vez de sortear destinos através dos prédios.
- Bancos, abrigos, bicicletas, hidrantes, placas, postes e fios já existiam,
  mas com distribuição espaçada. `Kit/ChunkKit` juntam as peças por material e
  região, evitando um nó por peça. Casas/interiores usam `HouseGen`.
- `JobSystem`: quatro vagas reais — Zé/bar (R$16/h), padre/igreja (R$10/h),
  Cida/pensão (R$12/h), Irene/mercado (R$14/h). Trabalhar altera dinheiro,
  horário, energia, higiene e sanidade; faltas e desligamento já existem.
- Profissões dos moradores são descrições e rotinas, não simulação de salários
  de cada NPC. Novas carreiras e estabelecimentos funcionais estão pendentes.

### Artefatos e desempenho: causas encontradas

- Os fios usavam y absoluto 7,05 m, mas os isoladores ficam em 7,22 m
  (base de 0,17 + altura local de 7,05). Corrigidas as conexões e a curva.
- Placas de rua eram `Label3D` sem suporte. Agora têm haste, chapa e base.
- Meio-fio original: 3 cm acima do asfalto; pintura: caixas brancas uniformes
  em todo cruzamento. O protótipo usa guia de 14 cm e tinta fina interrompida.
- Em `HouseGen`, um `or true` tornava inútil a verificação do objeto lateral;
  ele podia invadir o lote vizinho. Removida a condição que anulava o limite.
- Construção do piso e mobiliário de toda cidade era uma tarefa síncrona.
  A medição inicial do construtor encontrou aproximadamente 400 ms nessa
  etapa sem pausas. Chão, chunks e casas agora distribuem trabalho pelo tempo gasto, com alvo
  de 6 ms; uma operação indivisível pode ultrapassar esse alvo.
- Medição com rastreamento encontrou reconstruções de NPCs em `sync_npcs`
  acima de 200 ms ao mudar horário. O aquecimento preparava e destruía os
  modelos; a rotina também destruía quem saía de cena. Agora os modelos
  preparados são guardados e reutilizados, desativando seu AnimationPlayer
  e o processamento do personagem fora de cena.
- O limite por quadro distribui operações completas; ainda não divide a geração
  de uma malha humana em partes. O carregamento inicial e a primeira aparição
  de um morador novo continuam exigindo revisão de custo. Reutilizar modelos
  corrige o descarte indevido, mas não torna gratuita a primeira construção.
- Interiores próximos e primeira montagem/importação de móveis ainda podem
  gerar picos. A rota longa alcançou bairro, praça, rodoviária, beco e lanchonete,
  com pior quadro de 17,4 ms. A conferência separada limitada a 60 FPS registrou
  um quadro noturno de 96,7 ms; sua causa não foi confirmada. Resultados e limites
  finais ficam no relatório de validação; não declarar todas as travadas resolvidas.

## Protótipo implementado

Três casas novas usam IDs `casa_2_2_0..2`, `Houses`, portas, fechaduras e
interiores existentes. Nenhum ID antigo foi renomeado; marcos mantêm sua
implantação e portas. O lote original do mercado foi subdividido para distinguir
endereços residenciais. Dois anexos fechados são cenografia do próprio mercado.

Há mistura de alturas de 2–3 pavimentos, telhados/platibandas, janelas, peitoris,
grades, calhas, ar-condicionado, ladrilhos variados, guia com acessos baixos,
grelhas, abrigo/bancos, lixeiras, correio, orelhão, bicicletas, canteiros e roupa
no varal com movimento leve e vento maior na chuva. Piso superior das casas é
fachada; somente o térreo tem cômodos/interação nesta avaliação.

Irene usa sua rotina original para alternar balcão e prateleiras no mercado.
Sua vaga, os preços e o salário são os do sistema existente.

## Expansão proposta — aguarda avaliação do quarteirão

Para hospital, escola, oficina, farmácia e outros locais funcionais: cadastrar
locais/estoques/serviços nas mesmas tabelas, associar funcionários no NPCManager
e oferecer vagas pelo JobSystem. Antes, definir com o usuário se cada local será
entrável, quais funções existirão e como as rotinas se conectarão aos interiores.
Não foi criada economia, carreira, população, tráfego ou save paralelo.

Gatos, pavimentos superiores visitáveis e navmesh completa não foram adicionados.
Não houve troca do renderizador, SSAO/SSIL/SSR/GI/névoa volumétrica, cópia de
assets das referências, geração de imagens por IA ou commit.

## Revisão de detalhes e interação — 11/out/2026

O protótipo anterior ainda tinha superfícies lisas e mercadorias escondidas por
blocos maciços nas prateleiras. O clique da visão 3D reconhecia pessoas e chão,
mas não os móveis. Os modelos importados do HouseGen também não tinham colisão.
Adicionar colisão expôs um problema real de implantação: estantes na passagem,
cadeiras diante de portas e fogão/pia encostados justamente no acesso ao banheiro.

A revisão abre a estrutura das gôndolas, mantém caixas/garrafas/etiquetas visíveis,
acrescenta detalhes de manutenção no mercado, alvenaria, esquadrias/persianas e
copas irregulares às duas árvores do protótipo. Texturas pequenas de reboco,
asfalto, pedra, telha e madeira são compartilhadas e geradas por código, com
AO/cor de vértice preservadas. Os materiais e móveis reaproveitados também
beneficiam os componentes existentes; a implantação continua limitada a um bloco.

`CityBuilder.objects` é um registro transitório de geometria clicável e pontos
de uso. Não é um inventário, economia ou estado de mundo paralelo. Os efeitos
usam Economy, HomeSystem, Houses, GameState e o save v1 existentes. Camas e
assentos permitem permanecer na pose; fogões/banheiros usam atividades reais;
armários usam a busca existente do imóvel; prateleiras compram o catálogo real.
Mesas, cabeceiras, geladeiras e pias também podem ser examinadas.

O movimento existente recebe rotas locais por AStar2D com passagens consultadas
na física dos móveis/divisórias. A rota de rua original continua sendo usada.
Uma grade mais fina é necessária nas casas compactas; a disposição foi corrigida
para liberar acessos. Rotas estáticas são reaproveitadas, com limite de oito
interiores e invalidação por instância/quantidade de móveis/altura/fechadura.
Movimento manual respeita as colisões; não foi criada uma segunda navegação de NPCs.

Cancelamento agora interrompe a rota e somente retorna à posição de pé quando
a pose chegou a começar. Cancelar a aproximação não teletransporta à cama,
não entrega item e libera apenas a reserva do jogador, preservando a de NPCs.

### Limite que exige proposta antes de implementar

Ainda não há estado individual persistente para cada copo, prato ou móvel
decorativo, com retirada/reposicionamento e restauração após save/load. Proposta:
definir esse estado por imóvel no Houses e ligar a transferência ao inventário
existente, mantendo migração/defaults para v1. Isso exige decisão sobre como
persistir os objetos antes de prometer que toda decoração pode ser levada.
Não foi criado um contêiner de itens paralelo nem alterado o formato do save.

Andares superiores visitáveis, expansão urbana completa e uma coleção nova de
modelos com qualidade comparável à referência continuam pendentes de avaliação.
As evidências desta revisão ficam em
`C:/Users/glznc/Documents/Codex/2026-10-11/urban_v2/`.

### Diagnóstico do teste de rota e custo dos móveis

O teste antigo interrompia cada trecho após 120 s. O primeiro percurso medido
tem aproximadamente 336–337 m: a 2,2 m/s são necessários cerca de 153 s, antes
de considerar curvas. O trace mostrou avanço contínuo, `_stuck = 0`, contatos
somente com o chão e quatro pontos ainda pendentes aos 120 s. Portanto o erro
de 39,5 m não indicava bloqueio: o prazo do teste era insuficiente. O orçamento
agora é calculado pela distância e pelo perfil etário/energia, sem acelerar
a simulação. A chegada foi confirmada em 152,1 s, erro de 0,4 m.

Um trace separado dos móveis identificou `bedDouble.fbx`: leitura 1,3 ms,
medição de limites 1,0 ms, instanciação/material 31,5 ms. A textura de madeira
era gerada pela primeira cama dentro da fila de móveis, depois de entrar na
cena. Agora ela é preparada com os outros materiais durante o carregamento.
O log final registra a repetição; os picos antigos de 35,7/36,6 ms permanecem
nas evidências, sem serem apagados. A montagem inicial das malhas humanas
continua sendo uma operação indivisível de cerca de 150 ms.
