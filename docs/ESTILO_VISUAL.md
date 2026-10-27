# Estilo visual do Sete Vidas

Referência de *estilo* (não de conteúdo): jogos como MiSide. Personagens humanos em anime cel-shaded,
mundo semi-realista estilizado, quente e coeso. **Nenhuma imagem, modelo ou asset do MiSide entra no
projeto**; dele só usamos medidas de proporção tiradas das imagens oficiais da loja Steam.

## Princípios

1. **Humanos anime, mundo pintado.** Clara e Davi são toon (2 faixas de luz, contorno fino). A casa é
   "limpa" como a do MiSide: paredes de cor lisa (no máximo uma estampa grande de baixo contraste),
   madeira mel clara com veio quase invisível, móveis simples com chanfro, luz macia em gradiente e um
   contorno leve da cor do próprio objeto (nunca preto).
2. **Calor e coesão.** Paleta puxada para o quente (creme, madeira, rosa antigo, verde-sálvia). Nada de
   branco puro nem cinza frio dentro de casa. Sombras levemente tingidas (rosado/vinho), nunca pretas.
3. **A noite continua assustadora.** O passe quente vale para cômodos com luz acesa. Com as luzes
   apagadas a casa fica escura e azulada; não "clarear tudo".
4. **Fantasmas não são anime.** Ivone, Visitante e Sombra seguem MPFB + shader espectral (Sombra e
   Visitante com clipes de mocap: andar de zumbi (nas noites 4–6 a Sombra anda com o `walk_formal` da Clara, `ShadowThreat._set_gait`), `walk_formal`; o resto procedural). A Sombra é menos
   transparente que os outros (`dissolve` 0,12) e troca de corpo: correndo, `shadow_run.glb` (membros,
   pescoço e dedos longos) de costas como aranha; escondida, `shadow_peek.glb` (só cabeça e duas mãos
   de dedos curvos), cada peça posta por pontos (`head`, `hand`, `side`, `yaw`, `tilt`, `hands` no
   nook do `layout.json`). O aviso é o uniform `heat` do `spectral.gdshader` (carne vinho, contorno e
   rachaduras vermelhas) + olhos que crescem e luz vermelha. A Coisa é um
   modelo próprio (`tools/blender/build_thing.py`) com o shader de tentáculo. O contraste
   entre humanos toon e fantasmas realistas/espectrais é intencional.
5. **Proporções medidas, não inventadas.** `tools/blender/anime_proportions.json` é a única fonte de
   verdade (≈6 cabeças, olhos grandes de rosto adulto, não chibi). Tolerância ±3%.

## Personagens (Clara e Davi)

- **Origem:** VRoid Studio (Steam), projetos em `tools/vroid/*.vroid`, exportados como VRM 1.0
  (`<id>.vrm`). Um corpo/rosto por personagem, duas roupas (dia/noite) no mesmo esqueleto.
- **Visual atual:**
  - Clara (1,70 m): cabelo castanho-escuro `#3B2620`; dia = rabo de cavalo baixo, suéter creme e saia
    longa xadrez; noite = trança, colete rosa e calça clara.
  - Davi (1,80 m): cabelo quase preto `#2A1E1A`, óculos redondos de arame (gerados no rig); dia =
    suéter creme e calça bege; noite = colete azul e calça xadrez.
  - Clara de banho (`clara_bath.vroid`, cópia da noite): toalha tomara-que-caia das axilas aos joelhos,
    descalça, turbante. É o modelo "Sleeveless Dress" do VRoid (saia estreita 100, comprimento 25) com
    a textura `tools/textures/gen_towel_dress.py` → `tools/vroid/towel_dress.png` (felpudo creme; acima
    das axilas, mangas e punhos com alfa 0) carregada como camada, as outras camadas ocultas; "Inner
    Top" com a camada padrão oculta (pele limpa). Os sapatos são apagados no Blender (`DROP` no
    `build_vroid.py`, depois da escala, para o esqueleto bater com as outras roupas). Na banheira a saia
    abaixo do quadril some (`HumanRig.hide_skirt`, uniform `hide_v` nos shaders toon/outline), senão
    ela atravessa a água por cima dos joelhos dobrados.
- **Pipeline:** `tools/blender/measure_vrm.py` (confere razões) → `tools/blender/build_vroid.py`
  (ossos com nomes do jogo, A-pose de 42,5°, partes `_body/_eyes/_eyebrows/_eyelashes/_hair/_cloth`,
  shape key `eyes_closed`, MToon → Principled, escala, export GLB + `<id>.toon.json`).
  Rodar sempre headless: `blender -b -P tools/blender/build_vroid.py -- [--only clara_day] [--preview DIR]`.
- **No Godot:** `godot/scripts/actors/human_rig.gd` → ramo `_dress_anime` (flag `"anime": true` em
  `LOOKS`). Materiais:
  - `godot/shaders/toon.gdshaderinc` (+ `toon.gdshader` corte de alfa, `toon_blend.gdshader` mistura):
    ramp de 2 faixas com borda suave, `shade_color` do MToon (pele rosada), rim light, anel de brilho no
    cabelo.
  - `godot/shaders/outline.gdshader`: casco invertido em `next_pass`, cor da peça escurecida (×0,38),
    espessura ~1,2–1,8 mm. Sem contorno em olhos, sobrancelhas, delineado e boca.
  - O deslocamento do MToon tem sinal invertido no nosso ramp (`shade_shift = -shift`); o rosto do VRoid
    usa ~0,7 para ficar limpo.
- **Rosto:** o `build_vroid.py` mantém, além do `eyes_closed`, `mouth_a/i/o`, `joy`, `surprised`,
  `sorrow` e `eye_joy` (das `Fcl_*` do VRoid). A boca segue as vogais da fala (`HumanRig.talk`); o humor
  (`set_mood`): ^^ com o gato ronronando, susto, tristeza com medo alto. Dormindo: olhos fechados,
  respiração lenta e funda, cabeça de lado, boca entreaberta.
- **Animação (mocap):** clipes CC0 da Quaternius (Universal Animation Library 1 e 2 Standard, em
  `tools/vendor/quaternius/`), retargetados no próprio Godot por `godot/scripts/dev/retarget.gd`
  (`godot --headless --path godot --script res://scripts/dev/retarget.gd`) para cada modelo
  (`godot/assets/anims/<id>.res`): delta de rotação em espaço de mundo a partir da A-pose, pelve na
  escala da altura do quadril, metadados de velocidade e de altura da pelve por clipe. Feito no Godot e
  não no Blender porque as faixas dependem dos rests exatos importados.
- **Camadas do rig** (`human_rig.gd`, por esqueleto, nesta ordem):
  1. `AnimationTree`: idle/andar/trote misturados pela velocidade com o ciclo sincronizado ao chão;
     o andar é o `walk_formal` (o `Walk_Loop` da biblioteca anda curvado, de punho fechado, "de
     lutador"). Parados (idle, `talk`, telefone, braços cruzados) as pernas do clipe, que ficam em
     base de luta, voltam a uma postura simples (`_plain_stance`: coxas na vertical, pés lado a lado) e as
     clavículas caem pela metade. Andando, o olhar segue o caminho (`Owner._auto_look`); o gato só ganha
     uma olhadinha de 0,8 s a cada 5–8 s, e o pescoço não curva as costas. Estados em loop (sentado, agachado, telefone, braços cruzados...) e one-shots (`sit_down`,
     `stand_up`, susto, abrir caixa...). Sentar: ela para no chão à frente do assento e o clipe leva o
     quadril para trás; a altura do assento é corrigida (`seat_lift`).
  2. `HumanPoseMod` (`SkeletonModifier3D`): as poses procedurais de `POSES` (deitar, banho, abraçar os
     joelhos, `crawl` e `spider` da Sombra, `knock`/`listen`/`window_press` do Visitante) por junta sobre
     os clipes, cada junta com atraso (tronco → braços → cabeça) e ease; braços procedurais relativos ao
     peito. Gestos (`GESTURES`: óculos, cabelo, bocejo, espreguiçar, espirro, chave, interruptor...),
     respiração, tremor, olhar em cadeia (olhos, cabeça, pescoço, peito; mola amortecida, -35°/+30° de
     inclinação, fora do alcance o corpo gira). Fora do pass do modificador o `Skeleton3D` devolve a
     pose sem modificações: use `bone_global()`/`bone_world()` (cópia `_final`).
  3. `TwoBoneIK3D`: pés no chão/degrau (raycast; ignora desníveis > 0,25 m), mãos em `hand_target`
     (carinho no gato, colo).
  4. `SpringBoneSimulator3D`: cabelo `J_Sec_Hair*` e saia da Clara de dia (colisores na cabeça e pernas).
- **Objetos na boca do gato:** presos ao quadro da boca (`CatRig.mouth_frame`, segue a cabeça), com o
  ponto de mordida e o jeito de pendurar de cada objeto em `Carry.GRIPS` (planos pendem pela borda de
  cima, inclinados para a frente do peito).
- **Objetos nas mãos:** `HumanRig.hold(node, kind)` (`box`, `suitcase`, `doll`, `book`, `cushion`,
  `backpack`, `book` abraçado ao peito, `book_open` aberto para ler) com pose de braços própria. No `book_open` as mãos vão por IK às bordas do livro (cotovelos para fora, nunca dentro do tronco) e um modificador depois do IK (`HumanRig._post_modify`, `HumanPoseMod.post`) vira as palmas para a capa de trás, com os dedos rumo à lombada; o livro fica preso ao peito, mais alto em pé. Afinar com `--holdtune` (`"_grip"`) e `--tunefocus --views=front,under,eyes`. Turbante de toalha do banho: `tools/blender/build_turban.py`
  → `turban.glb`, textura `tools/textures/gen_towel.py`, preso à cabeça como os óculos do Davi.
- **Poses:** quedas de quadril de sentar/deitar/banho são absolutas (altura do assento/colchão):
  `pelvis_d` (altura da pelve nova − MPFB) entra nas quedas grandes. Sem cobertor (removido: bugava).
  Deitada o tronco fica plano e o travesseiro ergue a cabeça (pose `lie`). `bed_offset` (`owner.gd`)
  da Clara = (-0,11, 0, -0,3) (no travesseiro do lado dela, longe da cabeceira; uma mão na barriga,
  joelhos um pouco dobrados); Davi = (-0,2, -0,12, 0) (colchão de hóspedes em 3,55). Sentado, o Davi
  entra mais no assento (`seat_deep` 0,45, `seat_adj` -0,07 no cfg).

## Gato (Mingau)

- Anime toon como a Clara e o Davi (mesmo `toon.gdshader` + `outline`). O gato do jogo é a variante
  `mingau_bolinha` (`CatRig.GAME`): corpo de sempre, modelo `cat_mingau_d.glb`
  (`build_cat2.py --face decal`: sem globos oculares; olhos, nariz e boca são decalques chatos
  projetados na cara). Pelagem branca com capuz laranja que desce pelas bochechas (focinho e listra
  entre os olhos brancos), sela listrada e rabo laranja, pintada pela posição 3D de cada texel
  (`tools/blender/bake_cat_pos.py` → `tools/textures/gen_cat_coat.py bolinha --model cat_mingau_d
  --name mingau_bolinha`; o atlas UV da malha gerada é picotado, não pinte nele). Olho de fenda
  amarelo-verde, contorno grosso e brilho (`cat_eye_anime.gdshader` com `decal`, parâmetros
  `SLIT_EYE` no `cat_rig.gd`; ainda pisca e dilata). Estilo inspirado nos olhos pintados do Little
  Kitty, Big City (só referência). Estudos descartados: `mingau_a*`, `mingau_creme`,
  `build_cat3.py`/`build_cat4.py` (gatos do zero), folhas em `tools/review/gato_*`.
- Malha de `tools/blender/build_cat2.py` com o tronco +75% (`--stretch`, padrão 1,75): só barriga e
  costas alongam, cabeça/patas/rabo iguais. Pesos por zona (`zone_weights()`): tudo à frente da base
  da cabeça é `head` rígido (olhos, bigodes, focinho), só o pescoço (`neck` + `neck1`) mistura,
  `jaw` só no queixo; sentar nivela mais pela coluna que pelo pescoço (a cara não amassa). Comer:
  `st_eat` (cabeça na tigela, mastiga em rajadas), revisar com `--clip=eat`.
- Dormindo com a Clara: pose `curl` (`CatRig.CURL`): o pão deitado com a coluna dobrada de lado em
  "C", cabeça baixa encostada no corpo, rabo dando a volta; revisar com `--clip=curl --view=top`.
- Animação procedural em `cat_rig.gd`: andar em sequência lateral com passo que cresce com a velocidade
  e patas niveladas; sentar com pose resolvida do esqueleto (`_solve_sit`) e IK nas patas.
  Revisar com `godot --path godot res://scenes/cat_anim.tscn -- --cat --shots=stand --clip=walk|run|sit --view=side|34 --out=DIR`.
- Atuação (`Cat`, seção "acting"; escolhidas entre as variações de `tools/review/gato_anim`):
  `swat_at(alvo, ao_tocar)` (pata por IK até o objeto, olhando para ele; passinho até alcançar, e diante
  de móvel alto se apoia de pé na borda sem atravessá-la; usado no "Derrubar"), `pounce_at` (rebolada
  curta e bote; brincar com novelo/ratinho), `startle(de)` (pulo arqueado, `arch` no rig; nunca trava o
  andar), `tilt_to` (cabeça inclinada quando a Clara fala), `slow_blink` (piscada lenta com a cabeça
  baixando). Clipes: `--clip=aim` (pata em 4 alvos) e os `swat_*`/`cup_*`/`startle_*`/`pounce_*`/`tilt_*`/`blink_*`.

## Mundo (casa)

- `godot/shaders/surface.gdshader` (modo limpo):
  - `flatten` (padrão 0,85 via `Surfaces.FLATTEN`) puxa cada texel para a média da textura ou para
    `base` (cor sRGB do `materials.json`); sobra só um "fantasma" do veio. Com `flatten` > 0 a superfície
    fica no máximo acetinada (rugosidade ≥ 0,55, `SPECULAR` 0,2), senão o piso espelha as paredes.
  - `pattern` procedural em metros (`diamond`/`stripe`/`dot`, `pattern_color`, `pattern_scale`,
    `pattern_amt`), antialiasado com `fwidth`; substitui os papéis de parede `gen/wallpaper_*.jpg`.
  - `light()`: lambert envolvido largo (`wrap` 0,45, `soft` 0,35), sombra tingida, `spec_mul` 0,2.
- `godot/shaders/edge.gdshader`: contorno de tela num quad em tela cheia (`env.gd`), por profundidade +
  normal (só profundidade na qualidade low), cor da cena ×0,55, 1 px em 1080p, some com a distância
  (7–22 m) e no escuro. Intensidade por fase em `LOOKS[*]["edge"]` (noite 0,85, menu 0) e `set_edge(k)`.
  Personagens e o gato (`toon`, `outline`, `cat_eye_anime`) gravam stencil 2 e ficam fora dele.
- `godot/data/materials.json`: paleta por cômodo (sala bege com losango, quarto rosa antigo com bolinha,
  hall/corredor pêssego com listra, hóspedes sálvia, escritório verde-acinzentado, cozinha creme), pisos
  mel (`#C98F55`…), rodapé/sanca em pinho mel, lambri creme, tecidos e tapetes pastéis lisos. Sujeira só
  no porão, sótão, lavanderia e (pouca) no quarto de hóspedes.
- Móveis: kit procedural próprio (`tools/blender/house_kit.py` → `godot/assets/models/kit/<id>.glb`),
  no lugar dos modelos Poly Haven; `Surfaces.stylize_standard()` (`flatten`, `grime` 0) cobre o que
  sobrar em StandardMaterial3D.
- `godot/scripts/fx/env.gd`: tonemapper **AgX**, glow 0,65 / bloom 0,06, SSAO leve (0,7 / raio 0,5).
  De dia parte do ambiente azul do céu vira creme (`amb_col`, `amb_sky` 0,45–0,6) e `adj_sat` 1,12;
  à noite o ambiente continua só do céu (azulado). Luminárias de teto não projetam sombra da própria
  armação (`lights.gd`). Luz dos banheiros quente (`#fff1de` em `layout.json`); só a lavanderia
  mantém luz fria.
- `godot/shaders/post.gdshader`: `warm_grade` 0,3.
- Luz que entra pelas janelas: nuvem densa de poeira dentro do feixe de sol/lua (`FX.beam_dust` +
  `beam_dust.gdshader`: sem luz ambiente, acende só pelo sol/lua através da sombra, muito mais forte
  olhando contra a luz (`fwd` 5), lâmpadas fracas; 4× grãos de 1,6 cm, `dust` em `LOOKS` 5× o antigo).
  Um emissor por janela externa (`House._build_beams`), apontado ao longo
  da luz por `House.aim_beams(dir)` (chamado em `Env.apply` e `set_daylight`); some no preset low. O
  resto da casa tem poeira fina em todo cômodo (`dust_motes`, `House.haze`, ~26 grãos/m² de piso, 1,4 cm, translúcida: `opacity` 0,6, `core` 0 e some a menos de 1,5 m da câmera, `near_fade`)
  com o mesmo shader em `FX.haze_mat` (sol/lua a 0,6 do feixe, lâmpadas 0,4, brilho próprio `haze` em
  `LOOKS`: 4 de dia, 0,1 à noite para a casa continuar escura); no feixe as duas somam. Afinar ao vivo
  no devctl com `eval dust(...)` e `eval haze(...)`. O feixe é desenhado: um
  prisma da janela até o chão (no máximo 4,5 m para dentro, `House._shaft_mesh`) com o
  `light_shaft.gdshader` (aditivo, aceso só pelo sol/lua através da sombra, então árvore lá fora ou
  sol do outro lado o apagam; some perto da câmera, nas bordas e onde encosta em chão e móveis; força
  `shaft` em `LOOKS`: fraca de dia, forte à noite para a faixa de lua). Por baixo, uma neblina
  volumétrica fraca em cada cômodo (`FogVolume`, densidade `fog_in`; o sol entra nela com `sun_fog`, e
  o `volumetric_fog_gi_inject` é 0,08 para a névoa não ficar leitosa). A casa sai da neblina do
  quintal pelo buraco `hole_min`/`hole_max` do `ground_fog.gdshader` (no lugar do antigo volume
  negativo `carve`).
- Puf de poeira quando o gato pousa (`FX.dust_puff`, `Env.dust_puff`): fraco em qualquer piso, forte
  no sótão, porão e lavanderia. Vapor da banheira no banho (`steam_at`), além das torneiras quentes.
- Tarde: o sol começa mais baixo (sombras de janela compridas no chão) e passa por uma hora dourada
  antes de avermelhar e escurecer (`set_daylight`).
- Madeira clara some sob AgX + luz rosada das paredes: use bases de madeira mais escuras/saturadas do
  que parecem no seletor (`#C98F55` sai mel; `#D9A86C` saía bege).

## Casa de campo e quintal

- A casa fica no campo: sem rua nem vizinhos. Estrada de terra até a porteira, cerca de madeira
  fechando o quintal (x −8…20, z −5,6…20), mata de árvores secas em volta (`woods()`, cópias de 6
  variantes decimadas) e morros baixos no horizonte (`house_exterior.py`).
- Ala dos fundos térrea (z 10–13): sala de jantar (`wall_jantar` amarelo-manteiga com listra,
  `floor_jantar` = parquet da sala) e despensa (`wall_despensa` creme, piso xadrez). Teto plano com
  platibanda. Os cômodos antigos não mudaram de coordenada.
- Quintal: galpão (esconderijo), varal, horta, pilha de lenha (esconderijo), casinha de cachorro vazia,
  escada dos fundos e uma pedra sob a portinhola da despensa. À noite só o poste da porteira acende
  (luz 13, nó `street_lamp_head`); o resto fica escuro e azulado.
- Quintal vivo: folhas secas caindo e rolando com o vento (`FX.leaves`; somem ao tocar a casa),
  vaga-lumes só no entardecer (`FX.fireflies`, `set_daylight` com k < 0,4; nunca à noite) e sereno
  sob o poste só à noite (`FX.mist`). Sem chaminé.

## Como verificar uma mudança visual

- `godot --headless --path godot res://scenes/check.tscn` → deve imprimir `CHECK DONE`.
- Casa: `godot --path godot -- --phase=night --day=1 --lights --cam=x,y,z,tx,ty,tz --shots=DIR --name=sala --every=5 --count=1`
  (sala, quarto, cozinha e hall; de dia e de noite; compare com e sem `--lights`). Este é o teste que
  vale para a casa: o `lookdev.tscn` tem ambiente e luzes próprios (sem fases, sombra das armações das
  luminárias no teto); dele só o contorno de tela é igual ao do jogo.
- Personagens: `godot --path godot res://scenes/lookdev.tscn -- --people [--shots=clara_face,davi_face,clara_bed,clara_bath,...] [--ghost=ivone] --out=DIR`
  (`--ghost=shadow_run --ghostpose=spider@1.0 --ghostheat=0..1 --shots=ghost_side,ghost_front` para o corredor).
  Animação: `--clip=estado` (loop), `--clip=!clipe` (one-shot), `--clip=~gesto`, `--speed=1.2`, `--talk="fala"`,
  `--mood=joy|surprised|sorrow`, `--hand` (IK da mão), `--ghost=shadow --ghostpose=crawl@1.0`; no jogo,
  `-- --claraat=... --clarato=... --follow=34` (andar, escada, sentar) e `--bedpose=lie,sitUp@5`.
- Blender: `--preview DIR` no `build_vroid.py` (frente, rosto, perfil).

## Pontos em aberto

- Roupas de noite são roupas de casa montadas com presets (não pijama de verdade).
- Faixa de sombra marcada no rosto com luz lateral.
- Desvios de proporção aceitos: Clara perna +6,9% e olho estreito -9,4%; Davi cabeça -6,6% e olho alto +4,4%.
- Toalha de banho: o topo frouxo deixa ver um pouco do avesso no peito; descalça, os pés ficam ~1,6 cm
  acima de onde a sola do tênis apoiava (o IK dos pés compensa no chão).
- Ajoelhar é o agachamento do clipe (`Crouch_Idle`): a biblioteca não tem ajoelhar em loop.
- Espiada da Sombra (cabeça e mãos): conferida em captura nos 10 esconderijos; no sofá a cabeça
  deitada no chão fica pequena de longe. As camas são maciças até o chão (sem vão): nelas a Sombra
  espia por cima do colchão, do lado da parede (`"over": true` no nook, `ShadowThreat._peek_over`).
  Ajuste fino por nook com `tilt`/`hands`.
- As roupas de noite do VRoid têm sapato: na cama a superfície `Shoes_` some (`HumanRig.hide_shoes`,
  ligado ao `Owner.in_bed`) e ficam os pés do corpo.
- Boneca: os olhos de vidro brilham frio no escuro (`DollThreat._glass_eyes`, fraco em cômodo aceso).
  Afogadora com contorno verde-água e Cão com contorno em brasa, para lerem no escuro.

## Notas práticas do VRoid

- Campos dos sliders usam vírgula decimal (`0,5`); `0.5` vira 5.
- "Salvar como" só pelo menu ☰ quando o projeto ainda não tem arquivo.
- Cliques: o VRoid (Unity) às vezes perde clique rápido; aperte, segure ~0,3 s e solte. A janela pode
  perder o foco entre ações: um clique em área vazia antes.
- Texturas de roupa: carregar imagem como camada nova (ícone ao lado de "Layers"); alfa 0 vira buraco
  na roupa e "Delete Transparent Meshes" no export apaga o que sobrar. Para achar o UV, carregar uma
  imagem de faixas numeradas e ver onde caem no modelo.
- Loop de medição limitado a 3 rodadas por personagem. Eye Size X satura perto de 0,26 (olho/rosto);
  Leg Length mexe pouco na perna feminina e muito na masculina.

Backups do visual anterior (MPFB realista) em `tools/backup/`; casa antes do passe MiSide em
`tools/backup/house_style_*` (shaders, `env.gd`, `materials.json`, `surfaces.gd`, `lights.gd`).
