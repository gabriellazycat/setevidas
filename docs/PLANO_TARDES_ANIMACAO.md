# Tardes vivas: rotina da Clara, animação dos humanos, sono, alçapão e inimigos (Sombra, Visitante, Coisa)

## Situação (22/10/2026)
Executado, fases 0 a 4, incluindo a roupa `clara_bath`. Desvios e pendências:
- O retarget dos clipes é feito no Godot (`godot/scripts/dev/retarget.gd`), não no Blender.
- Ajoelhar usa o agachamento do clipe (a biblioteca não tem ajoelhar em loop).
- A toalha deixa ver um pouco do avesso no peito de frente: aceito, não será corrigido.
- Espiada da Sombra com máscara (só cabeça e mão): feita e conferida no guarda-roupa; os outros 9
  esconderijos foram reposicionados, mas não conferidos em captura.
- A boneca do dia 4 fica sobre a caixa `box_hosp_b`: falta pôr uma cômoda (`dresser` do kit) no
  quarto de hóspedes.

## Contexto
Revisamos o fim de tarde da Clara (`game.gd` `start_afternoon()`/`_scene_steps()`). Ele tem o mesmo
esqueleto todo dia, 28 s parada (tigela + telefone), contradições (dia 7 "luz acesa" e ela apaga
tudo; diário sem origem), dias 4/7 sem pista da ameaça nova, e o dia 1 nem tem tarde. Além disso os
humanos são duros: em `human_rig.gd` todas as juntas mudam de pose juntas no mesmo ritmo, o andar é
um seno fixo sem aceleração e com os pés deslizando, parada ela é uma estátua, a cabeça nunca olha
nada, o rosto não mexe (`build_vroid.py` descarta as expressões do VRoid) e o cabelo não balança. E o
alçapão do sótão abre por cima da escada. Dormindo, eles parecem de olhos abertos e o cobertor
atravessa o corpo. Por fim, a Sombra passa a ter outra regra (foge do olhar do jogador, espia do
esconderijo e ataca se for encarada), o Visitante e a Coisa ganham animação nova, e o
Sussurrador ganha um semáforo de cores que decide o risco de puxar a tomada. O usuário
autorizou baixar e instalar o que for preciso.

## Fase 0: backup
Copiar para `tools/backup/afternoon_anim_<data>/` tudo que for alterado: `game.gd`, `owner.gd`,
`human_rig.gd`, `story.gd`, `interactions.gd`, `cat.gd`, `house.gd`, `save_game.gd`,
`build_vroid.py`, `house_furnish.py`, `shadow.gd`, `ghost_body.gd`, `visitor.gd`, `thing.gd`,
`blanket.gd`, `whisperer.gd`, `layout.json`, os GLBs de `godot/assets/models/people/`, os GLBs da casa e o
save (`%APPDATA%/Godot/app_userdata/Sete Vidas/save.json`).

## Fase 1: alçapão do sótão
- `tools/blender/house_furnish.py` ~l.449: dobradiça em `(H.x0, 5.8, H.z0)` em vez de `z1`. O painel
  cai atrás do topo da escada (z 1,25) e não atravessa mais os degraus.
- `godot/scripts/world/house.gd` ~l.823: girar `+hatch_open * 1.45` (confirmar o sinal na tela).
- Reconstruir a casa no Blender headless e reimportar.

## Fase 1b: personagens dormindo (olhos abertos + cobertor atravessando)
**Achados no código:**
- Cobertor (`game.gd` `_blankets` ~l.2155 → `house.fit_blanket` → `blanket.gd`): é moldado **uma
  vez**, 0,25 s depois de a pose virar `lie`. Mas a pose chega com `lerp` exponencial a taxa 5, então
  nesse instante as juntas só andaram ~70% do caminho. O cobertor fica com a forma de um corpo meio
  deitado e o corpo continua descendo e atravessa. Ele também é feito de **cápsulas nos ossos** com
  raios das MPFB (`capsules_for`: tronco 0,13, braço 0,05…), que não cobrem o volume do VRoid (peito,
  roupa, cabelo). E some quando ela senta ou se abraça (`pose != "lie"`), aparecendo de novo depois.
- Olhos: `eyes_closed` só fecha com `asleep` (`owner.gd` `_bed_behaviour`). Com medo entre 32 e 58
  ela fica **deitada acordada** na mesma pose `lie`, de olhos abertos e parada, e parece "dormindo de
  olho aberto". Também preciso confirmar na tela que o `eyes_closed` do VRoid fecha por inteiro (1º
  passo: captura `lookdev -- --people --shots=clara_bed,davi_bed`).

**Correções:**
- O cobertor passa a ser moldado pela **malha de verdade**: `MeshInstance3D.bake_mesh_from_current_skeleton_pose()`
  em corpo, roupa e cabelo; o heightfield (`Blanket.build`) usa a altura máxima dos vértices por
  célula mais uma folga de 1,5 cm, no lugar das cápsulas (as cápsulas ficam só para as pernas, se
  precisar). Só molda **depois de a pose assentar** (todas as juntas a < 0,02 rad do alvo), não por
  tempo.
- O cobertor **acompanha a pose**. Mesma grade de vértices, então dá para interpolar entre duas
  formas em ~0,5 s. Deitada: cobre até o queixo. Sentada (`sitUp`), abraçada (`hug`) ou chorando
  (`cry`): escorrega até a cintura (`from_x` na pelve) em vez de sumir. A respiração entra como uma
  ondulação pequena no peito (o cobertor sobe e desce), não como malha nova.
- Sono legível: **dormindo** = olhos fechados, respiração lenta e funda, cabeça de lado, boca
  entreaberta (shape `mouth_a` leve). **Acordada na cama** = olhos abertos piscando, olhar para a
  porta e para os barulhos (`look_target`), às vezes vira de lado.
- A troca de roupa noite/dia, o `bed_offset` e as alturas do colchão continuam como estão.

## Fase 2: base de animação (mocap + procedural)
**Downloads** (CC0, OpenGameArt, sem login), cada um numa pasta nova `tools/vendor/quaternius/<pack>/`:
- `universal_animation_librarystandard.zip` (14,5 MB), Universal Animation Library 1 Standard, 45 clipes.
- Universal Animation Library 2 Standard (~10 MB).
O rig "universal humanoid" usa nomes no estilo Unreal, os mesmos que o `build_vroid.py` já dá aos
ossos (`pelvis`, `spine_01`, `thigh_l`…). Primeiro listo os clipes (Blender headless) e escolho:
parada, andar, trote (`hurry`), sentar/sentado/levantar, agachar/ajoelhar e gestos. **O que não
tiver clipe** continua procedural (deitar, banho, abraçar, chorar, paralisia, telefone, beber).

**Retarget no Blender** (`tools/blender/retarget_ual.py`, novo, headless): faz o bake dos clipes no
esqueleto de cada personagem (Clara e Davi, rotações por delta em espaço de mundo a partir da A-pose
de 42,5°, translação da pelve na escala da altura do quadril) e exporta para
`godot/assets/models/people/anims_<who>.glb`. O mesmo esqueleto serve para as duas roupas.

**Rosto** (`build_vroid.py` `trim_shape_keys`): além do `eyes_closed`, manter `Fcl_MTH_A/I/O`,
`Fcl_ALL_Joy`, `Fcl_ALL_Surprised`, `Fcl_ALL_Sorrow` e `Fcl_EYE_Joy`, com nomes curtos
(`mouth_a`, `joy`…). Rebuild com `blender -b -P tools/blender/build_vroid.py`.

**Rig no Godot** (`human_rig.gd`, todas as classes conferidas no Godot 4.7.2):
- `AnimationPlayer` + `AnimationTree` por roupa: blend idle↔walk↔jog pela velocidade (passo
  sincronizado, sem deslizar) e one-shots `sit_down`/`stand_up`/`kneel_down`/`kneel_up`/gestos.
- As poses procedurais passam para um `SkeletonModifier3D` próprio, que roda depois do mixer, com
  peso de mistura. Cada junta ganha atraso (tronco → braços → cabeça) e curva ease-in-out no lugar
  do `lerp` exponencial único.
- Parada viva: troca de peso, microvariações da cabeça e gestos aleatórios por personagem.
- `LookAtModifier3D` em cadeia: olhos (ossos de olho do VRoid), cabeça, pescoço e `spine_03`, com
  pesos, limites e mola amortecida. Fora do limite, o corpo gira.
- `TwoBoneIK3D`: pés no chão/degrau; mão no gato (carinho, colo) e na tigela.
- `SpringBoneSimulator3D` nos ossos de cabelo `J_Sec_Hair*` (fecha o item em aberto do
  ESTILO_VISUAL); saia da Clara de dia se houver ossos.
- Boca anima durante `say()` (alterna A/I/O pelo texto); expressão por humor: alegria ao fazer
  carinho, susto, tristeza com medo alto; olhos ^^ ronronando.
- Olhos fechados dormindo: já existe (`asleep and in_bed`). Conferir na tela e corrigir se o
  `eyes_closed` não fecha ou se `asleep` não chega a `true`.

**Movimento** (`owner.gd`): aceleração e frenagem (0→1,2 m/s em ~0,4 s), curvas suaves no caminho
(olhando à frente, sem quina a cada nó), giro no lugar com passinhos (clipe de virar ou passo
procedural), `look_target` automático (gato a < 3 m e visível ou miando, quem fala, a TV, um barulho).
Novos tipos de passo: `look`, `anim` (one-shot), `kneel_talk` (ajoelha virada para o gato, fala, levanta)
e `lap`.

## Fase 3: rotina das tardes (`game.gd`, `story.gd`)
**Esqueleto** (todos os dias):
- A+B: falas de chegada e da tigela por dia (`Story.AFTERNOON_LINES[day]`), em tom que acompanha a
  semana. Ela acende as luzes ao entrar (gesto no interruptor) em vez de já chegar tudo aceso. Agacha
  para despejar a ração.
- E "fechar a casa" no lugar dos 16 s no telefone: tranca a porta da frente (gira a chave), confere a
  janela da sala e acrescenta checagens com os dias. Pelo caminho até a cama comenta o que o gato
  mudou de manhã (`_task_done`), sem desfazer e sem efeito no jogo: duto, caixa, basculante,
  portinhola, luz noturna, cordão do sótão, janela do porão. Só comenta o que fica no caminho.
- Animações de vida espalhadas: largar chaves/bolsa, espreguiçar, bocejar antes de subir, olhar por
  cima do ombro (dia 5+), abraçar o próprio corpo (depois do banho), abraçar almofada (dias 6–7),
  ajoelhar para falar com o gato quando ele chega perto (`kneel_talk`, com intervalo de recarga).
- Davi: empurra os óculos, chega com a mala na mão (dia 4), digita no laptop, cruza os braços e
  **espirra quando o gato chega perto**.
- Pessoas nunca sobem nem descem a escada do sótão (só o gato).

**Dia 1 (novo):** o save novo começa em `afternoon` do dia 1 (`SaveGame.new_save`, `_begin_snapshot`,
`continue_game`). Ela entra com uma caixa (`carry`): "Chegamos, {cat}! Casa nova!". Tigela e dicas
de Paciência/mover/pular passam para cá (saem da noite 1). Para na porta do porão: "Barata demais
pra ser verdade… Porão eu vejo amanhã." Tranca a porta e vai para a cama. "Escolher noite" continua
abrindo na noite.

**Cenas:**
- Dia 2 (refeita): senta no sofá, bate na coxa "Vem, {cat}!" e aparece o círculo de pulo no colo
  (alvo de pulo em `interactions.gd`). O gato deita (`cat.mode = "lap"`, ronrona, Foco sobe como no
  `purr`) e a mão dela faz carinho de fato (IK). Na TV passa uma novela inventada ("Amor de
  Porteira"): quadros gerados para o shader da tela (`screen_mat`, novo modo "programa") com música
  e vozes abafadas. Por volta dos 30 s a imagem trava, uma voz lenta diz "...vem aqui..." (a das
  fitas), um rosto pisca na tela e entra o chiado alto. O gato pula do colo, ela leva o susto (`anim`
  susto + expressão), vai até a TV e **tira da tomada** (`house.set_plugged`): "Pronto. Sem TV hoje."
  Se o gato não subir no colo em ~15 s, a cena segue sem colo.
- Dia 3 banho (refeito, hoje ela entra de roupa):
  - **Roupa de banho nova `clara_bath`**: 3ª roupa no mesmo projeto VRoid (`tools/vroid/clara.vroid`,
    pelo computer-use como nas outras), com vestido tomara-que-caia das axilas até os joelhos e
    textura de toalha felpuda creme (`tools/textures/gen_towel.py` → PNG importado no VRoid), descalça.
    O cabelo vai num **turbante de toalha**, malha rígida presa ao osso da cabeça, no mesmo esquema
    dos óculos do Davi (`human_rig.gd` `_build_glasses`), modelada em `tools/blender/` e escondendo o
    rabo de cavalo. Exporta `clara_bath.vrm` → `build_vroid.py` (`CHARACTERS["clara_bath"]`) →
    `set_outfit("bath")`.
  - **Sequência:** "Vou tomar um banho quentinho..." → sobe → entra no banheiro de cima e a porta
    fecha (som de chuveiro/água enchendo ~5 s; a troca de roupa acontece aqui, fora da vista) → a porta
    entreabre (o gato entra) → ela está na banheira de toalha, pose `bath`, com a água a 0,8 e
    **espuma** na superfície (novo parâmetro no shader da água da banheira). As mãos aparecem como
    hoje. Saindo, por conta própria ou puxada pelo gato: levanta, abraça o próprio corpo ("Brr...") e
    vai para o quarto (porta fecha ~3 s). Sai com a **roupa de noite** e segue a rotina (fechar a
    casa) já de pijama.
  - Consequência igual: se ninguém a tirar da água, a noite começa com 20 de medo.
- No fim do dia 3, ao fechar a casa: "Ainda bem que o Davi chega amanhã." (prepara a mudança).
- **Dia 4, a chegada do Davi** (roteiro completo; substitui `_davi_afternoon` do dia 4 e a cena
  "davi"). Ninguém usa a escada do sótão:
  1. A Clara chega como sempre ("Hoje chega visita, {cat}. Comporta-se."), põe a tigela.
  2. Barulho de carro na estrada de terra e buzina. Clara: "É ele!" Ela abre a porta da frente.
  3. O Davi entra **com a mala na mão** (prop preso ao osso `hand_r` com `model.hold()`, novo, no
     esquema dos óculos) e a mochila nas costas: "Então é aqui a casa barata? Gostei, Clara." Ela
     acena e sorri. Se o gato estiver perto: "{cat}, né? Espero que não solte muito pelo. Sou
     alérgico." e espirra.
  4. Clara: "O quarto de hóspedes é lá em cima, o da direita." Os dois sobem a escada principal.
  5. No quarto de hóspedes, o Davi larga a mala (o prop vai para o lugar dele e os
     `GUEST_MOVEIN` aparecem nesse momento, não no começo da tarde) e **puxa o lençol de poeira** da
     cama (gesto de puxar, `GUEST_DUST` some com uma nuvem de poeira e ele espirra): "Quarto de
     hóspedes... cheio de caixa. Perfeito."
  6. Ele abre uma caixa velha de Dona Ivone, deixada no quarto, e **tira a boneca de porcelana**
     (cópia visual na mão): "Olha o que tinha aqui!" Clara: "Credo. Guarda isso." Ele põe a boneca
     em cima da cômoda. À noite ela sai do baú do sótão como hoje: voltou sozinha.
  7. Clara: "Obrigada por vir. Eu não queria ficar sozinha aqui." / Davi: "Não acredito em fantasma.
     Mas acredito em preço bom." / Clara: "Se ouvir barulho de noite, é a casa velha. Né?"
  8. Eles descem. O Davi senta no sofá e mexe no celular. A Clara fecha a casa e vai dormir. À noite
     o Davi trabalha na escrivaninha e depois deita, como hoje (`_setup_davi`).
- **Dias 5–7, rotina do Davi** (`_davi_afternoon`): chega uns 10 s depois da Clara (barulho de carro),
  com uma fala do dia, larga as chaves e senta no sofá/escrivaninha (empurra os óculos, digita,
  espirra se o gato chegar perto).
  - Dia 5: "Clara, você mexeu naquela boneca? Sumiu do meu quarto."
  - Dia 6: entrega o diário: "Tinha isso na caixa da boneca, no fundo."
  - Dia 7: a conversa da véspera no sofá.
- Dia 5 telefone: igual, sem a volta ao telefone depois.
- Dia 6 diário: veio da caixa de Ivone do quarto de hóspedes (dia 4), entregue pelo Davi. Ela nota
  páginas arrancadas (as da noite 1) e o 3º trecho (`Story.DIARY_LINES`) aponta o porão.
- Dia 7: baque/tremor do porão no meio da conversa ("Você ouviu isso?" / Davi: "Cano velho."). Ela
  deixa a luz do quarto acesa: exceção ao `lights.set_all(false)` do `_reset_world` na noite 7, e a
  lâmpada queima sozinha por volta da 01:00.

## Fase 3b: a Sombra nova (`threats/shadow.gd`, `ghost_body.gd`, `story.gd`, `layout.json`)
Regras combinadas:
- Inverte o olhar: quem olha é o **jogador** (câmera), não a Sombra. Some o "gato à vista dela por
  2,5 s → caça" (`_watch_cat`).
- **No aberto, olhar espanta**: com a Sombra na tela (frustum + linha de vista sem parede, perto o
  bastante), ela foge de quatro, rápida e aos trancos, até o esconderijo mais perto fora da vista e
  em cômodo escuro. Barulho de arranhão e batidas e a porta rangendo dizem onde ela foi.
- **Escondida, olhar provoca**: olhando para o esconderijo, a cabeça dela aparece (inclinada, mão no
  batente) e os olhos esquentam até o vermelho em **2 s**; a cabeça endireita e ela dispara direto
  no gato (mais rápida que o gato correndo): **1 de vida** (`Game.cat_hit`), some em fumaça (repel).
  Desviar o olhar antes dos 2 s cancela.
- Sai do esconderijo **5 s** depois de ninguém olhar e volta a ir atrás da pessoa (esconder só
  atrasa). Olhar para ela ao lado da cama a afasta da cama.
- **Luz mata ao sair**: os esconderijos são escuros por dentro. Acender o cômodo não a bane enquanto
  ela está escondida; ela é banida quando sai e pisa na luz. Andando, a luz do cômodo continua banindo
  e ela continua drenando lâmpadas no caminho.
- **Visão de Gato através da parede não conta** como olhar: só com linha de vista. A Visão é a forma
  segura de achar o esconderijo.
- Esconderijos marcados na casa (`layout.json`, novo `SHADOW_NOOKS`: posição, ponto e ângulo da
  espiada, cômodo onde ela sai): atrás de porta entreaberta, armário, debaixo da cama, atrás do sofá,
  vão da escada.
- Animações: andar lento e pesado (hoje ela desliza: `shadow.gd` não passa velocidade ao rig), fuga
  de quatro aos trancos (pose mudando a ~10 fps), espiada, disparo até a câmera, susto na tela.
- A noite 1 ensina: "Ela foge do seu olhar… mas não encare onde ela se esconde."

Implementação:
- `shadow.gd`: os estágios atuais (1–5: surge, drena, anda até a pessoa, ao lado da cama,
  paralisia) continuam como estado **andando**. Entram os estados `FLEE → HIDDEN ⇄ PEEK → CHARGE`
  e `EMERGE`, que voltam para **andando** com `_build_route()`.
- `_seen_by_player()`: alguns pontos do corpo (cabeça, peito, pés) dentro do frustum de `w.cam`, sem
  `house.blocked` entre câmera e ponto, até ~14 m. Precisa valer ~0,3 s seguidos para não disparar
  com um relance. Na espiada usa o ponto da cabeça no batente.
- `FLEE`: escolhe o nook com `nav.route_from` (penalidade de luz) cujo ponto não esteja visível
  pela câmera e cujo cômodo esteja escuro; anda a ~6 m/s; som de arranhões e batidas
  (`Sfx.creak`/`thud` curtos); porta do nook range (`Door.set_state("ajar")` quando houver).
- `HIDDEN`: invisível (alpha 0, x-ray continua para a Visão). Olhado → `PEEK`; 5 s sem olhar →
  `EMERGE`. `PEEK`: cabeça sai do batente devagar, `glare` sobe em 2 s com zumbido crescente,
  desviar → baixa e volta a `HIDDEN`. Em 1,0 → `CHARGE` se `Director.may_hunt_cat` deixar; se não,
  recolhe a cabeça e fica escondida.
- `CHARGE`: ~8 m/s direto (nav se precisar); ao alcançar, `w.cat_hit("shadow", pos)`, susto de tela
  (a cara dela enche a câmera por alguns quadros, `w.sting`, `w.flash`), fumaça, `repel()`.
- `EMERGE`: sai do nook para o cômodo de saída; se estiver aceso, `_banish()` com o susto atual.
- Remover `_watch_cat`, os `on_hunt_*` antigos e o `HUNT_SPEED`; atualizar `describe_death`,
  `Story.THREAT_INFO["shadow"]` (dica e fuga) e a frase da Sombra no `CLAUDE.md`.
- Nooks (`SHADOW_NOOKS` no `layout.json`, ~8–10): armário do quarto, debaixo da cama da Clara e da do
  Davi, atrás da porta do banheiro, atrás do sofá, vão da escada, despensa, lavanderia, porão.
  Cada um com `p` (onde ela fica), `peek` (posição e ângulo da cabeça), `exit` (nó de saída e
  cômodo).
- Animação (`human_rig.gd` + mocap):
  - andar lento e pesado com passos de verdade (`rig.speed` passa a ser usado, clipe de zumbi da
    Universal Animation Library 2 mais lento);
  - pose `crawl` de quatro com ciclo próprio e "trancos" (a pose só muda a ~10 fps, a posição anda
    liso), clipe de engatinhar como base;
  - pose `peek` (corpo de lado escondido, cabeça inclinada ~80°, mão no batente via IK);
  - tique de cabeça aleatório na espiada e endireitada brusca antes do `CHARGE`.

## Fase 3c: outros inimigos
- **Visitante** (aprovado): na porta, braço batendo no ritmo de `Sfx.knock`, cabeça encostada na
  porta "escutando"; na janela, rosto colado no vidro; cabeça acompanhando a voz falsa. Quando o gato
  bufa, **dá a volta na casa** visível pelas janelas em vez de teleportar para a outra entrada.
  Perseguição: passadas longas demais com cadência baixa, tronco reto, braços colados, chapéu firme.
  Ao desistir, toca o chapéu num cumprimento e some.
  Implementação: `visitor.gd` ganha poses `knock`/`listen`/`window_press` e um caminho externo entre
  as entradas (nós do quintal no `NAV`), andado de fora com o próprio passo. Na perseguição,
  `rig.style = "stalk"`, novo estilo com passada e cadência próprias.
- **Coisa** (aprovado): corpo novo no lugar dos 9 cilindros e da esfera. Massa de braços e
  tentáculos saindo do círculo de giz, com um **olho que abre** no núcleo durante o aviso (`tell`).
  Os tentáculos sobem e batem no chão na onda de choque, os mais perto se esticam para o gato, e no
  fim do ritual tudo se recolhe no círculo e desaba.
  Implementação: `thing.gd` + `tools/blender/build_thing.py` (novo) → `godot/assets/models/thing.glb`.
  Os tentáculos são cadeias de ossos movidas por `SplineIK3D`/procedural e mantêm o shader atual de
  tentáculo (`TENTACLE` em `thing.gd`) para a pele; o olho tem pálpebra (shape key) ligada a `tell`.
- **Sussurrador, semáforo no aparelho** (`whisperer.gd`, `house.gd`, `Story.THREAT_INFO`):
  - O aparelho possuído (tela, painel do rádio, lâmpada da luz noturna) **e o plugue/fio** piscam
    verde, amarelo e vermelho, **trocando de cor sem ordem**, a cada 0,4–1,2 s. A aspereza
    (`harsh`) puxa o sorteio: chiado manso fica mais no verde, áspero mais no vermelho.
  - Ao puxar a tomada, a cor daquele instante decide a bola: **verde 0%, amarelo 25%, vermelho
    60%** (substitui `_orb_chance()`). Sem bola, segue a regra atual: pula para outro aparelho
    (`0,7 − hops × 0,28`) ou morre.
  - O chiado continua como pista de longe e muda junto com a cor: zumbido no verde, estalos no
    amarelo e chiado áspero no vermelho (acessível sem depender só da cor).
  - Cores: material emissivo no `screen_mat`/plugue (novo parâmetro `light_col`) e na luz 14 que
    já acompanha o aparelho. Dica e `THREAT_INFO` atualizadas: "Puxe no verde."
- Afogadora e Cão ficam como estão nesta rodada.

## Fase 4: docs
`docs/ESTILO_VISUAL.md` (seção Personagens: pipeline de mocap/retarget, camadas do rig, expressões,
cabelo) e `CLAUDE.md` (tardes por dia, dia 1 com tarde).

## Verificação
- `godot --headless --path godot -- --selftest` e `godot --headless --path godot res://scenes/check.tscn`
  → `CHECK DONE`.
- Retarget: `--preview` com quadros dos clipes no Blender; no jogo,
  `res://scenes/lookdev.tscn -- --people --shots=...` (rosto falando, sentada, ajoelhada).
- Tardes: `autopilot.gd` `-- --phase=afternoon --day=N` para N = 1..7 com `--shots=DIR --every=5`.
  Conferir cada beat, que nada trava e que a tarde termina na noite (backup do save antes).
- Andar: capturas de lado e 3/4 andando, virando e subindo escada (pés sem deslizar, sem ficar
  presos), no padrão do `cat_anim.tscn`.
- Alçapão: captura `--cam` do corredor de cima, aberto, com a escada livre.
- Dia 4: a mala na mão sem atravessar a perna, o lençol de poeira sumindo, a boneca na cômoda de
  tarde e no baú à noite.
- Sombra: `-- --phase=night --day=1 --threat=shadow --huntlog` com câmera fixa e com o autopilot
  (`autopilot.gd`) em três roteiros:
  1. olhar → foge para o nook;
  2. encarar o nook 2 s → espiada, vermelho, carga, 1 vida a menos e ela some;
  3. olhar, acender o cômodo de saída, desviar → sai após 5 s e é banida.
  Conferir também que a Visão através da parede não dispara nada e capturas de cada pose (andar,
  `crawl`, `peek`, carga).
- Sussurrador: `--day=2 --threat=whisperer --huntlog`, cores trocando no aparelho e no plugue, e
  puxões forçados em cada cor (log com a contagem de bolas em ~50 puxões por cor, perto de
  0/25/60%).
- Visitante: `--day=5 --threat=visitor`, batidas, volta pela casa após o bufo e perseguição no quintal.
- Coisa: `--day=7 --threat=thing --stage=2`, olho abrindo no aviso, tentáculos batendo e recolhendo.
- Noite 7: luz do quarto acesa no começo e apagada depois das 01:00; Sombra continua funcionando.
- Dormindo: capturas `clara_bed`/`davi_bed` e no jogo (`--phase=night --day=4`, câmera no quarto
  de cada um), com olhos fechados dormindo, abertos acordados, cobertor sem atravessar deitada nem
  sentada (vários ângulos, inclusive rente ao colchão) e a transição deitar↔sentar sem buraco.
- Banho: `lookdev -- --people --shots=clara_bath` e captura do dia 3 no jogo. A toalha cobre das
  axilas aos joelhos de todos os ângulos, sem buraco no corpo por baixo e sem o turbante atravessar
  o cabelo.
