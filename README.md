# Sete Vidas

Terror em 3D em que você é Mingau, o gato da casa. Só você vê o que anda pelos corredores. Proteja Clara (e depois Davi) por sete noites.

## Versão Godot (atual)

Refeita em **Godot 4.7** com modelos e texturas feitos no **Blender 5.2**:

- Casa de campo modelada no Blender, com móveis de um kit procedural próprio (`tools/blender/house_kit.py`), texturas e céus HDRI da Poly Haven (CC0) e quintal com mata em volta.
- Mingau em estilo anime toon como os humanos, com andar e sentar procedurais.
- Clara e Davi feitos no VRoid Studio em estilo anime cel-shaded (toon + contorno), com roupas de dia, de noite e (Clara) de banho. Animação com clipes de mocap da Quaternius (CC0) retargetados no Godot e camadas procedurais por cima: olhar, IK de pés e mãos, cabelo e saia balançando, boca na fala e expressões. O cobertor é moldado pela malha de quem dorme. Estilo e animação em `docs/ESTILO_VISUAL.md`.
- Tardes com rotina própria a cada dia (a mudança, a TV com o gato no colo, o banho, a chegada do Davi, o telefone, o diário, a véspera).
- Assombrações com carne espectral, fumaça e contorno na Visão de Gato. A Sombra foge do seu olhar e espia do esconderijo; o Sussurrador pisca verde, amarelo e vermelho no aparelho; o Visitante dá a volta na casa; o Cão Fantasma e a Coisa no Porão (braços, tentáculos e um olho) são modelados no Blender.
- Neblina volumétrica, raios de luar, iluminação global (VoxelGI), SSAO/SSIL, chuva, relâmpagos, poeira, mariposas no poste, pós-processamento de medo e de visão.
- Todo o áudio é sintetizado offline (`tools/audio/synth.py`) e tocado com oclusão por cômodo, reverberação e trilha adaptativa.

**Jogar:** abra `build/SeteVidas/SeteVidas.exe` (ou extraia `build/SeteVidas.zip` em outro computador).

**Editar:** abra a pasta `godot/` no Godot 4.7. Ferramentas de geração em `tools/`: `tools/blender/build_house.py` e `house_kit.py` (casa e móveis), `build_cat2.py` (gato), `build_humans.py` (fantasmas), `build_vroid.py` (Clara e Davi), `build_hound.py`, `build_thing.py`, `build_turban.py`; animações com `godot/scripts/dev/retarget.gd`; áudio com `tools/audio/synth.py`. Regras do jogo e testes em `CLAUDE.md`.

**Exportar:** `godot --headless --path godot --export-release "Windows Desktop"` (gera `build/SeteVidas/SeteVidas.exe`).

## Versão web (original)

Feita com TypeScript, Three.js e Web Audio, com tudo procedural.

## Como rodar

```bash
npm install
npm run dev
```

Abra http://localhost:5173. Para gerar a versão final (pasta `dist/`, pronta para itch.io ou qualquer servidor estático):

```bash
npm run build
```

## Controles

| Ação | Teclado e mouse | Controle |
| --- | --- | --- |
| Mover / câmera | WASD / mouse | Analógicos |
| Pular (até o círculo que aparece) | Espaço | A |
| Interagir (segure para ações longas) | E ou clique | X |
| Visão de Gato | Botão direito ou V | LT |
| Miar | Q | Y |
| Bufar | F | RB |
| Correr / esgueirar | Shift / Ctrl ou C | RT / B |
| Hora e tarefas | Tab | Select |
| Pausar | Esc | Start |

## Estrutura

- `src/world` — a casa como dados (`Layout.ts`), construção, móveis, luzes por cômodo, portas, colisão e navegação
- `src/actors` — o gato (modelo, física, pulo assistido, câmera) e a Clara (modelo, poses, IA)
- `src/threats` — as seis assombrações e o diretor que equilibra as noites
- `src/game` — ciclo de jogo, fases (manhã, tarde, noite), interações, história e finais
- `src/audio` — síntese de todos os sons e da música
- `src/render` — materiais com luz mascarada por cômodo, texturas, céu e pós-processamento
- `src/ui` — menus, opções, legendas e HUD

O progresso e as opções ficam salvos no navegador (localStorage).
