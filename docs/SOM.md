# Som do Sete Vidas

## O que dá medo (pesquisa)

- **Silêncio é ferramenta.** Os momentos sem música, só com o ruído da casa, deixam o jogador sozinho
  com a imaginação; o susto pesa mais depois deles. Amnesia constrói o pavor assim, e Alien: Isolation
  enche os corredores vazios com o zumbido das máquinas e os estalos da estação.
  ([Wayline](https://www.wayline.io/blog/silence-is-scary-sound-design-horror-games),
  [PC Gamer: The sound of silence](https://www.pcgamer.com/the-sound-of-silence/))
- **Som diegético conta onde o perigo está.** Em Alien: Isolation o barulho do alien nos dutos e a
  respiração da Ripley dizem quando ele está perto; quem se esconde no escuro joga de ouvido.
  ([PC Gamer: the audio of Alien: Isolation](https://www.pcgamer.com/uk/the-audio-of-alien-isolation),
  [gamemusic.net](https://gamemusic.net/sound-design-in-horror-games/))
- **Contraste de volume.** Antes do susto o mix afunda (ducking) e o susto entra alto e seco.
- **Sons fora do lugar.** Um passo ou um estalo atrás do jogador, onde a câmera não olha.
- **A música sai da frente na calmaria** e só sobe quando algo está vindo.

## Como o jogo aplica

- **Diretor de som** (`Game._night_sound`, lê `Director.phase()`):
  - `calm`: estalos da casa espaçados, drone quase sumido, sem música de tensão.
  - `buildup`: estalos mais frequentes; passos, rangidos e respiração **atrás do gato** (3–5 m, onde a
    câmera não olha) a cada 16–28 s; quando um fantasma chega ao estágio 3 o mix **afunda** (`Sfx.duck`).
  - `peak`: sem lógica própria em `_night_sound`; o stinger toca no barramento Sfx, mais alto, com
    ambiente e música abaixados (`Sfx.sting` chama `duck`). Stings a menos de 0,6 s um do outro valem
    por um só (o segundo só toca se for mais forte).
  - `relax`: estalos raros (multiplicador 0,6); o ambiente volta porque o duck decai.
  - Os sustos ambientais (`Ambient`: olhos, vulto, porta) só começam em `calm`
    (`Director.allows_ambient()`); em outras fases os timers pausam.
- **Pool 2D cheio**: corta o som mais antigo, nunca o `sting` nem o trovão. Som pedido que não existe
  gera um aviso único no log.
- **Música** (`music.gd`): drone `0,18 + 0,5·t` (0,18 → 0,68) com a tensão `t`; a camada de tensão só entra acima de 15%.
- **Sons gravados CC0** (portas, tranca, chaves, piso, interruptor, batidas): `tools/audio/import_cc0.py`,
  licenças em `godot/assets/audio/LICENSES.md`. O resto continua sintetizado (`tools/audio/synth.py`),
  que não sobrescreve os gravados.
- **Vozes**: balbucio suave (`soft_syllable`), entonação por frase em `Sfx.voice`.
