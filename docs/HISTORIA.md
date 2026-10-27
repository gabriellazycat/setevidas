# Sete Vidas: a história

Fonte da verdade para todos os textos do jogo (falas, cartões, diário, finais) e para a tradução.
Os textos em `godot/scripts/game/story.gd` e as falas em `game.gd` seguem este documento.

## A ideia

Clara está atravessando o pior ano da vida dela: um noivado longo acabou e, no mesmo ano, ela perdeu
o emprego. Ela não desaba na frente de ninguém. É prática, faz piada, resolve as coisas, diz "tô
ótima" para todo mundo, e comprou uma casa barata no campo "para recomeçar". Por dentro está tudo
doendo, e isso só aparece nos detalhes: o celular virado para baixo, a insônia, o banho que demora
demais, a mudança rápida de assunto.

O Mingau vê esses pedaços como fantasmas que atacam a Clara à noite. No fim descobrimos que **nunca
houve fantasmas**: era um gato cuidando dela.

## Tom

- A Clara **nunca é a personagem que chora**. É forte, segura as pontas, às vezes seca, às vezes
  engraçada. A dor está no que ela não diz e no que ela faz sozinha de madrugada.
- Com o Mingau ela baixa um pouco a guarda: é com ele que ela é honesta.
- O jogo é carinho de tarde e medo de noite. A tarde é quente, calma, cheia de conversa; a noite é a
  mesma casa, escura, onde o que ela carrega ganha corpo.

## Personagens

- **Clara** (31). Ex-analista de projetos. Organizada, irônica, generosa com os outros, dura consigo.
  Diz "tá tudo certo" quando nada está. Gosta de novela antiga ("Amor de Porteira") e de tricô.
- **Davi** (22), irmão mais novo. Leve, brincalhão, óculos redondos, um pouco desastrado, alérgico a
  gato (e mesmo assim faz carinho). Veio "passar uns dias" porque a mãe pediu, mas diz que veio porque
  quis. Ela sabe; ele finge que não sabe que ela sabe.
- **Mingau**, o gato laranja. O jogador.
- **Dona Ivone**, a antiga moradora (o espelho, ver abaixo). Viveu sozinha 40 anos e um dia sumiu.
- **Breu**, o gato preto de Ivone, que ela trancou do lado de fora.
- **A mãe** (só por telefone e citada). **O ex**, Rafael (só por telefone e citado).

## O que cada fantasma é

A fala da tarde sempre anuncia o fantasma novo daquela noite (`Config.NEW_ON_NIGHT`).

| Noite | Fantasma | O que é na vida dela | Pista da tarde | O que o gato "realmente" fez |
|---|---|---|---|---|
| 1 | Sombra | O que ela não fala, guardado nos cantos | Ela fica no sofá com a luz apagada "só descansando os olhos" | Acendeu a luz da sala de madrugada; ela foi deitar |
| 2 | Sussurrador | O celular e o notebook de madrugada: e-mails de "não, obrigado", mensagens do ex | Notificação; ela vira o celular: "Mais um 'não' educado." | Puxou o carregador; ela largou o celular e dormiu |
| 3 | Afogadora | A pressão que sobe; lavar louça às 3h com a água correndo | "Um banho bem quente e eu fico nova." | Fechou a torneira que ela esqueceu aberta |
| 4 | Boneca | A vida que ela tinha planejado (casamento, a filha cujo nome ela já tinha escolhido) | O Davi acha a boneca: "Guarda isso. ...Eu já tinha escolhido o nome, sabia? Deixa." | Guardou a boneca no baú |
| 5 | Visitante | O ex, que liga e aparece querendo voltar ("não é quem diz ser") | Telefonema: "Não, Rafael. Já falei. Não vem." | Bufou na porta; ela não atendeu a ligação das 2h |
| 2+ | Cão | O único que é do gato: o medo de perdê-la | Davi: "Você cuida dela, né, Mingau? Ela não deixa ninguém cuidar." | Nada. Era o gato com medo |
| 7 | Coisa no porão | Tudo o que ela empurrou para baixo e trancou (o porão trancado do dia 1) | Ela finalmente fala com o Davi: "Eu tô cansada, Davi. Muito." | Ficou do lado dela na noite mais difícil |

## Dona Ivone, o espelho

Ivone existiu. Viveu sozinha 40 anos, trancou o Breu do lado de fora para ter silêncio e se perdeu.
Os objetos dela são reais e o Mingau os leva ao círculo do porão para "fechar" a história dela. No dia
6, o Davi traz o diário; a Clara lê e reage forte: "Quarenta anos sozinha aqui. Ninguém veio ver ela."
O Davi responde: "Por isso eu vim." Ivone é o que acontece com quem fica sozinho. A Clara não fica,
porque tem o Mingau e o Davi.

Ritual da noite 7: **a foto** (Clara e Davi pequenos), **a coleira** (do Mingau), **a chave** (da casa
nova, o recomeço). O que a segura.

## Pistas ao longo da semana

- O Davi nunca vê nada e dorme a noite toda.
- O Sussurrador sussurra trechos do que a Clara disse à tarde.
- O Visitante bate com três batidas curtas: o jeito do Rafael, que ela comenta no telefonema.
- As manhãs mostram consequências "normais": celular desligado no chão, torneira fechada, luz da sala
  acesa ("Dormi no sofá de novo? Quem acendeu a luz?").

## Os dias (falas-chave)

- **Dia 1, a mudança.** Animada, prática, lista de tarefas. O celular vibra e ela o vira para baixo.
  "Recomeço, Mingau. Casa nova, vida nova." Noite: a Sombra.
- **Dia 2, a TV.** "Amor de Porteira" passa um casamento; ela troca de canal com uma piada. E-mail:
  "Mais um 'não' educado." Noite: o Sussurrador.
- **Dia 3, o banho.** "Dormi mal. Um banho bem quente e eu fico nova." Noite: a Afogadora.
- **Dia 4, o Davi.** Chega com a mala, abraço de irmão, implicância. Acha a boneca no baú de Ivone.
  Noite: a Boneca.
- **Dia 5, o telefone.** Rafael liga; ela é firme e desliga, e depois fica um tempo calada. O Davi faz
  uma piada ruim de propósito para ela rir. Noite: o Visitante.
- **Dia 6, o diário.** O Davi traz o diário de Ivone do fundo do baú. Noite: tudo junto (sem novo).
- **Dia 7, a véspera.** Na sala, ela finalmente fala: "Eu tô cansada, Davi. Muito." Ele não diz nada,
  só senta mais perto. Noite: a Coisa.

## Tardes com conversa

- A Clara fala com o Mingau quando ele está perto (falas soltas por dia e por cômodo, sem repetir).
- A partir do dia 4, conversas Clara e Davi (cozinha, sala, varanda) que acontecem se o gato estiver
  perto. O Davi também fala com o gato ("Ô, Mingau. Ela tá bem mesmo?").

## Abertura (cartões)

1. Clara comprou a casa barata. Disse que era um recomeço.
2. Ela diz que está tudo bem. Ela diz isso para todo mundo.
3. Só com você ela fica em silêncio.
4. À noite, você vê o que anda pelos corredores. Proteja a Clara.

## Finais

- **Amanhecer (bom).** Ela dorme a noite inteira pela primeira vez. Montagem das noites sem fantasmas
  (o gato sibilando para um corredor vazio, puxando o carregador, fechando a torneira, arranhando a
  porta do banheiro, acendendo a luz com ela no escuro). Cartão: "Nunca houve fantasmas. Só um gato
  que não saiu do lado dela." Na cozinha, o Davi diz que fica mais umas semanas; ela, sem drama: "Vou
  ligar praquela terapeuta que a mãe indicou. Só pra conversar." Ela enche a tigela do Mingau.
- **Sete vidas (secreto).** O mesmo, e no telhado o Breu pisca devagar para o Mingau e vai embora.
- **A sétima vida.** Sem o gato por perto, ela segurou as pontas sozinha, até não segurar mais. Como
  Ivone. (Nada explícito.)
- **Mudança.** Sobreviveram à semana, mas nada mudou: venderam a casa e levaram tudo junto.
- Créditos: "Se você está passando por algo parecido, fale com alguém. CVV 188 (Brasil)." /
  "If you are going through something similar, talk to someone: findahelpline.com".
