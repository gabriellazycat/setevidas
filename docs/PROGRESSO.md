# Progresso da rodada de correções (out/2026)

Plano: `C:\Users\gabri\.claude\plans\ainda-temos-algumas-corre-oes-structured-meadow.md`.
Backups desta rodada: `tools/backup/rodada_20261023/` (save.json + cada arquivo antes de mexer).
Ferramentas: Godot `"$LOCALAPPDATA/Microsoft/WinGet/Packages/GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe/Godot_v4.7.2-stable_win64_console.exe"`,
Blender `"/c/Program Files/Blender Foundation/Blender 5.2/blender.exe"`, ffmpeg no PATH, Python 3.9 + Pillow.

Legenda: [ ] a fazer · [~] feito, falta testar · [x] testado

## 1. Bugs rápidos
- [x] ESC fecha o menu (`--esctest`)
- [x] New game sem clique extra (Controls.capture na tarde)
- [x] Vidas no HUD (tarde/manhã, new_game, record_night)
- [x] Sombra banida pela luz (--shadowtest=6) (memória 0,5 s, expulsa quando escondida, lâmpada não queima)

## 2. Gato
- [x] Item na boca (mouth_frame + Carry.GRIPS; --carry=ID --catcam=ANG)
- [x] Ração no pote (grãos, diminui ao comer) + spot da Clara
- [x] Pose `curl` na cama (refeita em "C" de lado, cabeça baixa; `cat_anim.tscn --clip=curl --view=top`), gato encostado nela

## 3. Clara e Davi
- [x] Clara na cama (bed_offset (-0.11,0,-0.3), pose lie nova). Falta: Davi na cama. Tênis somem na cama (`HumanRig.hide_shoes`)
- [x] Escada: bocejo trocado por olhar para cima + chamar o gato
- [x] Cena privada (banho, pijama, 2 portas, teleporte; `--steplog --intrude`, `--bathtest`)
- [x] Davi: chega andando da porteira e bate (DAVI_ROAD, walk "points"), só mala, sofá (sofaR x 3,08, seat_deep/seat_adj, pose sit). Baú IVONE_BOX + cômoda DRESSER_hosp no house_furnish.py: casa reconstruída, tampa e boneca na cômoda conferidas em captura
- [~] Vozes balbucio melhorado (soft_syllable no synth.py, entonação por frase em Sfx.voice; demo em tools/captures/voice_demo.wav, falta o usuário ouvir)

## 4. Inimigos e diretor
- [x] Diretor com ritmo calm/buildup/peak/relax (`--dirlog`; noite 2: nunca 2 fantasmas; Cão só em calmaria)
- [x] Sussurrador (sai do aparelho, rosto `whisper_face.gdshader`, 3 s encarando, 0,6→3,6 m/s; `--orbtest`)
- [x] Cão (vez própria na vaga do diretor, `Hound.waiting`; ronda 0,8, late 1,1 s, persegue 2,1, no alto late 3 s e some; falta ver em captura)
- [x] Cartões como vencer + marcador só na 1ª noite (objective_target por NEW_ON_NIGHT)
- [x] Aviso da noite (visto em inglês e português)

## 5. Missões
- [~] Tardes com sorteio (comer + 2 de PATIENCE_POOL: carinho, ratinho, novelo, água, sol; Owner.side_trip)
- [x] Noites com regras: N2 lavar fita, N3 anel no ralo da pia de baixo, N4 sapatinho só no escuro, N5 carta na caixa de correio, N6 ordem do diário (`--ruletest`, noites 2–6 PASS)

## 10. História
- [x] docs/HISTORIA.md
- [~] Textos de story.gd/game.gd reescritos (abertura, falas dos dias, Davi irmão, telefone do Rafael, diário, véspera, manhãs, finais, CVV nos créditos)
- [~] Conversas (Story.CHATTER/TALKS, Game._tick_chatter)
- [x] Montagem do final (MEMORY_SHOTS, `--ending=good`)

## 11. Auditoria de animações
- [ ] tools/dev/contact_sheet.py + gravação
- [ ] Lista de problemas e correções

## 6. Som
- [x] docs/SOM.md (pesquisa)
- [~] Diretor de som (Game._night_sound por fase, Sfx.duck, música só com tensão)
- [x] Sons CC0 baixados e importados (tools/audio/import_cc0.py; tranca, chaves, portas, piso, interruptor, batidas)
- [ ] Mixagem

## 7. Exterior
- [x] Paredes/quinas/escada sem z-fighting (tools/blender/zfight_check.py), porta dos fundos movida para x 6,5–7,35 com a escada; NAVCHECK CLEAN

## 8. Atmosfera (+ tarde bonita/noite com medo)
- [x] Tarde escurece aos poucos (env.set_daylight), lâmpadas tremem com fantasma por perto (RoomLight.presence), aberração cromática com caçada/medo. Luar já entra pelas janelas (luz direcional com sombra)

## 9. Idioma
- [x] tr() nas entradas da UI + modelos com %, `godot/i18n/en.po` (≈790 entradas, conferido menu/tarde/noite em inglês), opção Idioma na aba Jogo, `--lang=en`; `tools/i18n/extract.py --missing` lista o que falta

## Próximos passos (para a retomada)
1. Item 11: auditoria de animações em mais cenas (escada de perto, levantar do sofá, gestos do Davi,
   fantasmas: Boneca, Visitante, Afogadora, Coisa) com `--follow`, `--catcam`, `--shotfrom` e
   `tools/dev/shrink.py`; corrigir o que aparecer e anotar em `docs/ESTILO_VISUAL.md`.
2. Item 8: luar pelas janelas à noite, grão/aberração cromática subindo com o medo; conferir com o teste
   da casa (sala, quarto, cozinha, hall; dia e noite).
4. Sobra de flicker: rodapé de pedra em z 10,1 dentro da ala dos fundos (`house_shell.py` porch()).
5. Usuário: ouvir `tools/captures/voice_demo.wav` e o jogo com os sons CC0.

## Decisões tomadas sem o usuário
- 23/10: o usuário autorizou tudo nesta conversa (downloads de sons CC0 inclusive), gravar a tela sempre, e as permissões ficaram fixas em `.claude/settings.local.json`.
- Ração: grãos feitos no Godot (`House._build_kibble`, `set_food`), sem reconstruir a casa no Blender. Spot `bowl` da Clara z 4,6 → 4,32.

## Sons CC0 aguardando aprovação

## Última bateria (23/10)
selftest OK · CHECK DONE · NAVCHECK CLEAN · E2E PASS · ruletest noites 2–6 PASS · save do usuário restaurado.

## Rodada 2 (24/10) — o que escapou no teste do usuário
Plano: `C:\Users\gabri\.claude\plans\eu-testei-o-jogo-happy-cerf.md`. Backups: `tools/backup/rodada2_20261024/`.
- [x] Diretor: chegadas uma por vez, casa quieta + intervalo (`wake_gap`), fila única com o Cão, calma depois de um monstro sair (`--dirlog` noites 2/4)
- [x] Boneca vai até onde a pessoa está e só assusta de perto (`--dolltarget=davi`: foi ao escritório)
- [x] Card "como vencer" só na primeira noite do fantasma
- [x] Clara na cama: pose decidida uma vez por quadro (fim do congelamento) + braços por cima em lie/lieSide/sitUp/paralysis (capturas com --fear 45/65 e --purr, sem forçar pose)
- [x] Gato enrolado: patas de trás dobradas sob a barriga (CURL_HIND, CURL_IN)
- [x] Escada do sótão: subida animada degrau a degrau (`Game.climb_ladder`, `--laddertest`); manhã 4 abre o alçapão
- [x] Davi lendo: pescoço 0,12, olhar preso no livro, sem espirro sentado
- [x] Voz E2 escolhida (Animalese: banco de sílabas de voz humana `godot/assets/audio/voice_bank`, `tools/audio/animalese.py`; `Sfx._bank_voice`, rate 1,7, passo 0,115 s; mesma voz em PT e EN; `--voicelog`). Idioma padrão agora é português.
Bateria: selftest OK · CHECK DONE · NAVCHECK CLEAN · cattest · E2E PASS · ruletest 2/6 PASS · save restaurado · build exportado.
