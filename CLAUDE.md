# Sete Vidas

Jogo de terror em Godot 4.7 (`godot/`), com modelos e ferramentas no Blender 5.2 (`tools/blender/`,
sempre headless). A pasta não é um repositório git: antes de sobrescrever arquivos, copie-os para
`tools/backup/`.

## Jogo (direção atual)

- **História** (`docs/HISTORIA.md`, fonte de todos os textos): a Clara passa por um ano ruim (fim do
  noivado, desemprego) e segura as pontas; cada fantasma é um pedaço disso; o Davi é o irmão mais novo
  (22). No final bom, uma montagem (`Game.MEMORY_SHOTS`) mostra que nunca houve fantasmas. Tardes com
  conversa solta (`Story.CHATTER`/`TALKS`, `Game._tick_chatter`).
- **Ritmo** (`Director`, estilo Left 4 Dead): o Director comanda e as ameaças só obedecem
  (`Threat.ready()`/`summon()`). Uma intensidade `I` (0–1) sobe com a missão (`P`, ver
  `Game.mission_progress()`: objeto no lugar 0, tirado 0,35, largado a <4 m do círculo 0,8, entregue
  1; nunca volta a 0, então empilhar não adianta), com os fantasmas fora e com o gato caçado; o teto é
  `0,45 + 0,55·P + 0,05/ciclo`. Ciclo: `build` (chama fantasmas) → `peak` (teto atingido, ou gato
  caçado/ataque; nada novo entra) → `relax` de 30–45 s (−5% por noite, ×0,7 com a Coisa) → próximo ciclo
  mais alto. Perder uma vida (`cat_down`) fecha o ciclo; vencer um fantasma (`on_repelled`) só tira
  0,25 de `I` e o Director chama outro logo. Quem entra: a ameaça nova da noite primeiro, depois um saco
  embaralhado (sem repetir até esvaziar); uma segunda ameaça só com `I ≥ 0,7`. O Cão não é inimigo
  comum: fora do saco, sem vaga, vem junto dos fantasmas no `build`. `phase()` (calm/buildup/peak/relax)
  segue igual para o som e o `Ambient` (`allows_ambient()`: só em calm). O som segue a fase
  (`Game._night_sound`, `Sfx.duck`, `docs/SOM.md`). Log: `-- --dirlog`.
- O gato tem **7 vidas para a semana** (`SaveGame.lives_at`, `nights` no save v3). Fantasmas e o Cão
  tiram vida por `Game.cat_hit()`; com 0 vidas vem o final "A sétima vida" e a noite recomeça com as
  vidas do começo dela. O menu "Escolher noite" mostra 7 gatos por noite (riscado = perdida ali).
- Os fantasmas vão atrás das pessoas, mas caçam o gato ao percebê-lo (`Threat.start_hunt`, um caçador
  por vez em `Director.may_hunt_cat`). Sombra: quem olha é o jogador. Vista no aberto (na tela, com
  linha de vista, 0,3 s) ela foge para o esconderijo escuro mais perto (`SHADOW_NOOKS` no
  `layout.json`) cuja rota não passe a menos de 1,6 m do gato; sem nenhum, recua para longe dele e
  procura de lá (encurralada, fica encolhida até o gato se afastar). Tem três corpos: andando o MPFB
  (`shadow.glb`), correndo/disparando de costas como aranha (`shadow_run.glb`, pose `spider`),
  escondida só cabeça e duas mãos (`shadow_peek.glb`, `ShadowPeek`, posta por pontos do nook;
  `tools/blender/build_shadow_forms.py`). Flagrada andando, congela 0,55 s e vira a cabeça para o
  gato antes de fugir (`CAUGHT_SECS`). Encarar o esconderijo (`_player_stares`: até 9 m, perto do
  centro da tela, sem parede nem móvel no meio; só estar no quadro não conta) faz ela espiar, virar a
  cabeça devagar para o gato (`LOOK_MAX`), entortá-la e esquentar até vermelho-brasa (olhos, luz
  vermelha, vinheta com batimento); com 5 s dispara no gato (1 vida). 5 s sem ninguém encarar (ou
  20 s no total, `BORED_SECS`) ela sai rastejando de costas até a borda do móvel e só então levanta;
  sair num cômodo aceso a bane (escondida a luz não a bane). Encurralada com o gato a menos de 3 m
  por 6 s (`CORNER_SECS`), esquenta igual e ataca. Ousadia (`boldness`, zera toda vez que ela some e volta, `reset()`):
  no 2º flagra esconde por metade do tempo e não perde estágio; do 3º em diante não foge mais (modo
  `stalk`): recua 2–3 m sem sair da tela, encara esquentando e dispara em ~5 s; se o gato se afasta,
  segue acelerando de 0,8 a 6 m/s. Só cômodo aceso ou a caixa de papelão a tiram. Escondida, o painel
  mostra o cômodo (`hidden_room()`) sem marcador no mundo; ela respira/ri de lá. Fantasmas só vão
  em linha reta com `Threat.path_clear` (esfera contra a camada do mundo), senão pela rota. Miado tira
  a pessoa do transe de qualquer lugar e ela volta à cama; com o aparelho possuído o Sussurrador a
  chama de novo 6 s depois de deitar. Sussurrador: semáforo no aparelho e no fio (verde 0%, amarelo
  25%, vermelho 60% de bola ao puxar); a bola sai do aparelho com um rosto (`whisper_face.gdshader`),
  encara o gato 3 s e persegue de 0,6 até 3,6 m/s (nunca mais rápida que o gato correndo).
  Cão: anda pela casa toda, escadas incluídas (não pisa no sótão; no lance usa `route_from` e as duas pontas como destino, cola nos degraus e inclina o corpo); ronda a 0,8 m/s, ao ver o gato late 1 s e persegue a 2,1 m/s (o gato andando); no alto, late
  3 s e some numa fumaça, reaparece em outro lugar depois. Afogadora pelas pegadas molhadas, Visitante só lá fora (na
  janela fica parado, de braços baixos; só na porta bate. Só some se o gato sair e bufar de perto: 40%
  ele some, senão persegue o gato com passadas longas, do andar do gato (2,1) ao correr (4,4 m/s) em
  14 s, até o gato entrar em casa, e some tocando o chapéu; reto só com `Threat.path_clear`, senão contorna a casa por dois anéis de pontos a 0,8 e 3 m das paredes, `_detour`; com o gato a menos de 3,2 m da entrada ele
  para de bater, respira no vidro e olha para o gato). A Boneca
  anda (não teleporta) e não caça o gato; fora da tela ela apressa o passo e vira de frente para o
  gato (toda vez que você olha, ela já está te olhando) e às vezes ri quando você desvia o olhar. A Coisa (`thing.glb`) é uma massa de braços e tentáculos com
  um olho que abre no aviso; não ataca: acorda quando metade dos 5 objetos da noite 7 (foto, coleira, chave e
  2 de Ivone) foi tirada do lugar e só deixa a casa mais difícil. O ritual (segurar 3 s) completa quando
  tudo está no círculo (`Game.ritual_ready()`).
- Não há Visão de Gato: o que dá para usar ganha contorno creme (`InteractMarks`,
  `interact_outline.gdshader`; campo `outline` em `Interactions`) e o botão aparece sobre ele
  (`UI.prompt_at`). Os objetos de Ivone se destacam de mais longe (6 m). Interação de segurar mostra
  "Segure" sob o anel. HUD fixo: silhuetas no canto de baixo à esquerda à noite (Clara e Davi vermelhas, esvaziam com o medo; o gato verde, esvazia com o cansaço `cat.sleep`; `UI.vitals`), painel de tarefas sempre visível (TAB só o relógio), marcador de
  objetivo (`game.objective_target()`: losango na tela, seta na borda), cartão "como vencer"
  (`THREAT_INFO.howto`) que aparece quando a ameaça nova da noite surge e fica até o amanhecer (nunca
  em outras noites). Não há mais fileira de ameaças no canto. Dicas vistas ficam no save (`tips`). A pausa (ESC) tem um painel ao lado: "Conversas" (toda fala
  da fase atual, mesmo com legenda desligada; `UI._talk_log`, zera no início de cada fase) e, à noite,
  "Ameaças" (o "como vencer" de todas as da noite e do Cão, a nova em cima; `Game._night_threat_list`),
  que abre primeiro.
- Colisão: o gato tem cápsula no comprimento do tronco + esfera da cabeça (`col_yaw`, giro só se
  couber), pulo varrido ao longo do arco e colisão no voo; janelas e corrimão do 1º andar têm paredes
  invisíveis só para o gato (`HouseBuilder.LAYER_CAT_BLOCK`). Fora da cerca/abaixo do chão ele volta ao
  último ponto. Lá fora, "Arranhar a porta" (frente/fundos) leva para dentro. Rotas das pessoas e
  fantasmas conferidas com `godot --headless --path godot res://scenes/navcheck.tscn` (deve dar
  `NAVCHECK CLEAN`; `-- --cattest` testa o gato). Não há mais cobertor.
- **Partículas e luz** (detalhes em `docs/ESTILO_VISUAL.md`): poeira fina na casa toda (`House.haze`, `FX.haze_mat`) e uma nuvem densa nos feixes de sol/lua por janela
  (`FX.beam_dust`, `House.aim_beams`) com o feixe desenhado (`light_shaft.gdshader`, `House._shaft_mesh`)
  e uma neblina interna `fog_in` (tudo desligado no low), folhas, vaga-lumes no
  entardecer e sereno no poste à noite, puf de poeira do gato ao pousar e vapor da banheira.
- **A noite só acaba com a missão**: levar os objetos de Dona Ivone (`Story.RELICS`) ao círculo do
  porão. Cada noite tem uma regra (`rule`): N2 fita suja (lavar na pia do banheiro de baixo, do chão ou em cima dela), N3 anel no ralo da pia
  de baixo, N4 peça que só aparece com a luz apagada, N5 carta na caixa de correio da porteira, N6
  ordem do diário (`Story.RELIC_ORDER_HINT`). A portinhola da despensa está liberada desde o dia 1; as manhãs liberam as outras rotas (duto, basculante, janela do porão, árvore), a caixa de
  papelão (refúgio de um uso) e a luz noturna (`Story.MORNING_TASKS`). A luz noturna mantém o
  cômodo aceso contra a Sombra, mas é um aparelho (`House.Device` "nightlight") onde o Sussurrador
  pode entrar; tirá-la da tomada apaga a proteção até ele religar.
- **Tardes**: comer sempre e mais 2 tarefas sorteadas por dia de `Story.PATIENCE_POOL` (carinho,
  ratinho, novelo, água, sol). Banho e pijama são cenas privadas (`_go_private`): ela fecha todas as
  portas do cômodo e o gato é posto para fora num piscar; no banho o gato arranha a porta para ela
  abrir, e o fantasma sobe devagar da água. `Owner.side_trip` encaixa um recado na rotina dela.
  (`game.gd` `_arrival_steps` / `_scene_steps` / `_close_steps`, falas em
  `Story.AFTERNOON_LINES`, `CLOSE_LINES`, `TASK_COMMENTS`): ela chega no escuro e acende as luzes,
  larga as chaves, agacha para a ração; no fim "fecha a casa" (tranca a porta, confere janelas, mais
  checagens com os dias), comenta pelo caminho o que o gato mudou de manhã e deita. **A tarde só acaba
  quando o gato deita com ela** ("Deitar com a Clara", 2 s de ronrono). Lista em
  `refresh_afternoon_tasks()` (`Story.AFTERNOON_TASKS`); comer põe `cat.eating` por 4 s. O save novo
  começa na tarde do dia 1 (a mudança: caixa; missões "Coma com a Clara", ela espera na tigela, e
  "Leve a chave para a Clara no porão", chave carregável sobre a caixa, `give_key`); dia 2 TV "Amor de Porteira" e o colo (alvo de
  pulo, `cat.mode = "lap"`); dia 3 banho (porta fechada, espuma, toalha `clara_bath` e turbante); dia 4 chegada do Davi (mala,
  lençol de poeira, boneca da caixa de Ivone); dia 5 telefone; dia 6 o diário vem do Davi (ela espera no hall, `DIARY_WAIT`, lê no sofá ao lado dele e passa o livro para ele); dia 7
  tremor do porão e a luz do quarto acesa até ~01:00. Pessoas nunca usam a escada do sótão. O sótão tem paredes baixas de 0,9 m (`ATTIC.knee` no `layout.json`) sob o telhado, para ninguém bater a cabeça. A escada do sótão é um lance reto como as outras (16 espelhos de 0,1875 m, ~41°), encostado na parede da varanda na ponta da frente do corredor (x 6,65–7,4, pé em z 3,85 junto ao guarda-corpo da escada principal, topo rente ao piso do sótão em z 0,45; `ATTIC`/`HATCH` no layout, `attic_stair` em `house_furnish.py`; a porta da varanda fica em z 4,6–5,5). O cordão (corredor, x 6,97 z 2,75) abre a folha única do alçapão (`HATCH_W`, deita no piso do sótão) e a escada (`LADDER`) aparece com a rampa na camada do mundo (a sondagem de chão do gato ignora a camada 32: rampa ali o fazia deslizar) e paredes invisíveis só do gato ao longo do corrimão (só acima dos degraus: a escada é vazada e o gato passa por baixo) e no guarda-corpo do buraco (`House._ramp_box`). Os itens do sótão são conferidos com `godot --headless --path godot res://scenes/navcheck.tscn -- --atticcheck [--atticgap=0.35]` (sobreposição, telhado, `ATTICCHECK DONE 0` a menos de itens duplicados). Falas de Clara e Davi nunca se sobrepõem (`Owner._other_talking`, respiro de 0,12–0,55 s). Davi não segura mais o diário.
- **Controlador ao vivo** (preferir a reabrir o jogo a cada teste): `godot --path godot -- --devctl [--phase=afternoon --day=6]`
  (em segundo plano) e `python tools/dev/devctl.py --wait "cmd" ...` (`godot/scripts/dev/devctl.gd`): `state`,
  `steps clara`, `ff idx('clara') >= 42` (avança rápido até a condição), `jump`, `phase night 6`, `wait`,
  `eval EXPR` (g, clara, davi, cat, rig), `arg KEY=VAL` (qualquer flag do autopilot), `focus davi side 1.6`,
  `cam`, `shot PATH`, `quit`. Mudança em script exige reiniciar o jogo.
- Testes rápidos: `godot --headless --path godot -- --selftest`; caças com
  `-- --phase=night --day=N --threat=ID --stage=S --meet=ID --huntlog` (`autopilot.gd`). Tardes com
  `-- --phase=afternoon --day=N --steplog` (joga a tarde até deitar); ponta a ponta tarde+noite 1
  `--e2e=1 [--timescale=K]` (`E2E PASS`); Sombra `--shadowtest=1|2|3|4|5 [--walkaway] [--shadowbold=N] [--shadownook=ID] [--shadowblock] [--awayang=RAD]` (log `min_cat`; 4 = no
  cômodo com o esconderijo no canto da tela, sem encarar: ela tem de sair em 5 s); Visitante
  `--visitorat=ID --visitorhiss=SEC --vislog`; Sussurrador `--whisperlog --whisperodds`; Coisa
  `--killthing=SEC`; ritual da noite 7 `--phase=night --day=7 --ritualtest --dirlog`; espiada da Sombra presa num nook `--peekat=ID [--peekshots=DIR] [--peekheat=0..1] [--peekfurn=near] [--peeklook=0]` (log
  `face_to_cat`/`stares` por vista); Clara andando `--claraat=x,y,z,yaw --clarato=nós --follow=34`; cama `--bedpose=`.
  Mais: `--shadowtest=6` (luz acesa com ela escondida), `--carry=ID|relic:KIND --catcam=ANG`, `--carrytune=all|ID,... --tunedir=DIR [--carryfile=GRIPS.json]`
  (cada item na boca em sequência, fotos de perto em 4 vistas; offsets em `Carry.GRIPS`),
  `--bathtest`, `--orbtest`, `--dirlog`, `--ending=good`, `--intrude`, `--ruletest`, `--esctest`, `--clarahold=book|book_open`, `--holdtune=FILE.json --tunedir=DIR [--views=front,34,side]` (várias tentativas de braço × ângulos numa só execução), `--dolltarget=davi`, `--catgo=YAW` (o gato anda nessa direção; no devctl `arg catgo=PI` / `unarg catgo`, com `g.rig.yaw` apontando para lá), `--lang=en`, `--shotfrom=SEC`.
  Prints: `tools/dev/shrink.py` (folha de contato). Trailer: `--nohud`, `--campath=FILE.json` (chaves
  `t/pos/look/fov/roll/hand/ease`, `rel` ao gato/Clara; devctl `campath FILE`), `--scene=lap|bowl|bed|peek|doll`
  (`scripts/dev/trailer.gd`); grava um plano em MP4 com `python tools/dev/capture.py OUT.mp4 --size=1080x1920
  --secs=6 --from=4 --path=CAM.json -- <flags>` (Movie Maker; `godot/override.cfg` temporário fixa o tamanho). Flicker: `blender -b -P tools/blender/zfight_check.py`.
  Vozes: estilo Animal Crossing (`Sfx._bank_voice`): sílabas de voz humana (Kokoro, offline) em
  `godot/assets/audio/voice_bank`, aceleradas 1,7× e encadeadas por sílaba do texto a cada 0,115 s
  (`tools/audio/animalese.py`; venv em `tools/vendor/kokoro_venv`); a mesma voz em PT e EN.
  Idiomas: o português é o `msgid` e o padrão; `godot/i18n/en.po`, `tools/i18n/extract.py --missing`.
  Rodar o jogo com argumentos de dev nunca grava o save.
- Os testes do autopilot gravam no save do jogo (`%APPDATA%/Godot/app_userdata/Sete Vidas/save.json`):
  faça backup antes.

O estilo visual (humanos anime cel-shaded vindos do VRoid, casa semi-realista quente, fantasmas
espectrais) e a animação dos humanos (mocap da Quaternius + camadas procedurais) estão descritos em
detalhe abaixo. Siga-os em qualquer mudança visual.

@docs/ESTILO_VISUAL.md
