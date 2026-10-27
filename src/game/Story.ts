import type { ThreatId } from './World';

export const INTRO_CARDS = [
  'Clara comprou a casa barata.',
  'Barata demais, disse a mãe dela.',
  'A antiga moradora, Dona Ivone, viveu ali sozinha por quarenta anos.\nUm dia, simplesmente sumiu.',
  'Hoje é a primeira noite na casa nova.',
  'Clara não vê o que anda pelos corredores.\nVocê vê.',
];

export const THREAT_INFO: Record<ThreatId, { name: string; hint: string }> = {
  shadow: { name: 'A Sombra', hint: 'Ela não suporta luz. Acenda a luz do cômodo onde ela está.' },
  whisperer: { name: 'O Sussurrador', hint: 'Ele fala pelos aparelhos. Puxe o fio da tomada.' },
  drowner: { name: 'A Afogadora', hint: 'Ela vem pela água. Feche a torneira que abriu sozinha.' },
  doll: { name: 'A Boneca', hint: 'Só se move quando ninguém olha. Encare-a e leve-a de volta ao baú.' },
  visitor: { name: 'O Visitante', hint: 'Não é quem diz ser. Chegue à porta antes de Clara e bufe.' },
  hound: { name: 'O Cão Fantasma', hint: 'Ele caça você, não eles. Esconda-se, suba em móveis ou fuja pelo duto.' },
  thing: { name: 'A Coisa no Porão', hint: 'Leve os três objetos ao círculo e complete o ritual.' },
};

export interface MorningTask {
  id: string;
  text: string;
}

export const MORNING_TASKS: Record<number, MorningTask[]> = {
  2: [
    { id: 'mark2', text: 'Investigue as marcas com a Visão de Gato' },
    { id: 'duct', text: 'Abra a grade do duto na lavanderia' },
    { id: 'foto', text: 'Procure algo nas caixas do porão' },
  ],
  3: [
    { id: 'mark3', text: 'Investigue as torneiras com a Visão de Gato' },
    { id: 'basculante', text: 'Abra a janela basculante do banheiro de cima' },
  ],
  4: [
    { id: 'mark4', text: 'Investigue o baú do sótão com a Visão de Gato' },
    { id: 'coleira', text: 'Procure atrás da máquina de lavar' },
  ],
  5: [
    { id: 'mark5', text: 'Investigue a porta da frente com a Visão de Gato' },
    { id: 'hatch', text: 'Puxe o cordão do sótão, no corredor' },
  ],
  6: [{ id: 'chave', text: 'Encontre a chave no sótão' }],
  7: [{ id: 'ritual', text: 'Leve a foto, a coleira e a chave ao círculo no porão' }],
};

export const DAY_SCENES: Record<number, string> = {
  2: 'tv',
  3: 'bath',
  4: 'davi',
  5: 'phone',
  6: 'diary',
  7: 'eve',
};

export const DIARY_LINES = [
  '“Ele não dorme. Passa a noite inteira olhando para a porta do porão.”',
  '“Hoje o tranquei do lado de fora. Miou tanto... eu precisava de silêncio.”',
  '“Sem ele, a casa ficou fria. Algo sobe a escada quando eu apago a luz.”',
];

export const ENDINGS = {
  good: {
    title: 'Amanhecer',
    lines: [
      'O círculo se fechou com um som de vidro quebrando ao contrário.',
      'Pela primeira vez, a casa ficou em silêncio de verdade.',
      'Quando o sol nasceu, Clara dormia tranquila, com {cat} no peito. Davi roncava no quarto ao lado.',
      'Eles nunca souberam de nada. E é melhor assim.',
    ],
  },
  secret: {
    title: 'Sete vidas',
    lines: [
      'O círculo se fechou. A casa respirou aliviada.',
      'No telhado, à luz da manhã, um gato preto observava a janela do quarto.',
      'Ele piscou devagar para {cat}. Depois de tantos anos, foi embora em paz.',
      'Você nunca saiu do lado deles. Nem uma noite.',
    ],
  },
  bad: {
    title: 'Mudança',
    lines: [
      'Clara e Davi sobreviveram às sete noites.',
      'Na semana seguinte, colocaram a casa à venda e nunca mais voltaram.',
      'A nova família chegou num domingo de sol. Trouxeram um cachorro.',
      'No porão, alguma coisa continuava esperando.',
    ],
  },
};

export const CREDITS = [
  ['Sete Vidas', ''],
  ['Um jogo de terror sobre proteger quem você ama', ''],
  ['Design, código, arte procedural e áudio sintetizado', 'feitos com Claude'],
  ['Motor', 'Three.js + Web Audio'],
  ['Obrigado por jogar.', ''],
];
