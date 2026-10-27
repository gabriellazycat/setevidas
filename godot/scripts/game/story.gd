class_name Story
extends RefCounted
## The story's text: intro cards, ghost cards, morning tasks, day scenes, diary, endings, credits.
## Port of Story.ts.

const INTRO_CARDS := [
	"Clara comprou a casa barata.\nDisse que era um recomeço.",
	"Ela diz que está tudo bem.\nEla diz isso para todo mundo.",
	"A antiga moradora, Dona Ivone, viveu ali sozinha por quarenta anos.\nUm dia, simplesmente sumiu.",
	"Só com você a Clara fica em silêncio.",
	"À noite, você vê o que anda pelos corredores.\nProteja a Clara.",
]

## name, the card's line when it shows up, what to do when it hunts the cat, and how to beat it (the
## "como vencer" card kept in the corner the night it is new)
const THREAT_INFO := {
	"shadow": {"name": "A Sombra", "hint": "Ela não suporta luz e foge do seu olhar. Mas não encare onde ela se esconde.", "escape": "Ela vem rápida demais: corra para um cômodo aceso!",
		"howto": "Olhe para ela e ela foge para um canto escuro. Acenda a luz desse cômodo: quando ela sair, a luz a bane. Não fique encarando o esconderijo."},
	"whisperer": {"name": "O Sussurrador", "hint": "Ele fala pelos aparelhos. Puxe o fio da tomada: puxe no verde. No vermelho a bola quase sempre sai.", "escape": "Fique longe dos aparelhos ligados: a bola segue você pelos corredores e se apaga sozinha.",
		"howto": "Ache o aparelho que chia e puxe o fio com a luz verde. Se ele levar alguém em transe, mie para acordar."},
	"drowner": {"name": "A Afogadora", "hint": "Ela vem pela água. Feche a torneira que abriu sozinha.", "escape": "Ela segue as suas pegadas molhadas. Corra até secarem ou seque as patas num tapete.",
		"howto": "Feche a torneira que abriu sozinha (segure). Pisou na água? Seque as patas num tapete."},
	"doll": {"name": "A Boneca", "hint": "Só se move quando ninguém olha. Encare-a e leve-a de volta ao baú.",
		"howto": "Mantenha-a na tela, pegue-a na boca e guarde-a no baú do sótão."},
	"visitor": {"name": "O Visitante", "hint": "Não é quem diz ser. Saia de casa, chegue perto dele e bufe.", "escape": "Volte para dentro de casa!",
		"howto": "Quando baterem, saia de casa e bufe para ele de perto: ele pode sumir ou perseguir você, cada vez mais rápido. Corra para dentro de casa e ele desiste."},
	"hound": {"name": "O Cão Fantasma", "hint": "Ele caça você, não eles. Esconda-se, suba em móveis ou fuja pelo duto.",
		"howto": "Ele caça pelo som. Ande devagar, esconda-se e fique parado, ou suba num móvel até ele ir embora."},
	"thing": {"name": "A Coisa no Porão", "hint": "Ela acordou. Não ataca, mas a casa fica mais difícil: termine o ritual.",
		"howto": "Leve a foto, a coleira, a chave e as coisas de Ivone ao círculo, depois segure sobre ele para completar o ritual. A Coisa não ataca: só deixa a casa mais difícil."},
}

## each morning the cat prepares the night: a new way through the house, a refuge or a helper
const MORNING_TASKS := {
	2: [
		{"id": "mark2", "text": "Investigue as marcas"},
		{"id": "duct", "text": "Abra a grade do duto na lavanderia"},
	],
	3: [
		{"id": "mark3", "text": "Investigue as torneiras"},
		{"id": "box0", "text": "Empurre a caixa de papelão até um bom lugar (refúgio de uma vez só)"},
	],
	4: [
		{"id": "mark4", "text": "Investigue o baú do sótão"},
		{"id": "basculante", "text": "Abra a janela basculante do banheiro de cima"},
	],
	5: [
		{"id": "mark5", "text": "Investigue a porta da frente"},
		{"id": "flap", "text": "Empurre a portinhola da despensa para o quintal"},
	],
	6: [
		{"id": "nightlight", "text": "Leve a luz noturna para um cômodo escuro"},
		{"id": "box1", "text": "Empurre a segunda caixa de papelão até um bom lugar"},
	],
	7: [
		{"id": "hatch", "text": "Puxe o cordão do sótão, no corredor"},
		{"id": "porao_win", "text": "Abra a janela do porão"},
	],
}

## Ivone's things the cat brings to the circle each night (night 7 is the ritual with the clues)
const RELICS := {
	1: [
		{"kind": "page", "name": "uma página do diário", "text": "“Breu chegou numa noite de chuva. Miou na porta até eu abrir. Ficou.”"},
		{"kind": "page", "name": "uma página do diário", "text": "“Ele dorme virado para a porta do porão. Quando apago a luz, ele rosna para o escuro.”"},
		{"kind": "page", "name": "uma página do diário", "text": "“Hoje vi uma mancha no canto do corredor. Ela se mexeu quando acendi a luz.”"},
	],
	2: [
		{"kind": "tape", "name": "uma fita cassete", "text": "Na fita, a voz de Ivone: “Se alguém ouvir isto... não deixe o rádio ligado à noite.”"},
		{"kind": "tape", "name": "uma fita cassete", "rule": "wash", "text": "Chiado. Depois, uma voz que imita a de Ivone, devagar demais: “...vem aqui...”"},
		{"kind": "tape", "name": "uma fita cassete", "text": "Ivone, cansada: “Breu puxa os fios com a boca. Acho que ele sabe de alguma coisa.”"},
	],
	3: [
		{"kind": "ring", "name": "o anel de Ivone", "rule": "drain", "text": "O anel de casamento. Ela o tirava para lavar a louça e o deixava ao lado da pia."},
		{"kind": "pin", "name": "um grampo de cabelo", "text": "Um grampo com uma florzinha. Ainda úmido, como se tivesse saído da água agora."},
		{"kind": "pin", "name": "um grampo de cabelo", "text": "Outro grampo, preso num fio de cabelo branco e comprido."},
	],
	4: [
		{"kind": "clothes", "name": "um vestidinho da boneca", "text": "Costurado à mão. Na barra, bordado: “Para a minha menina, que nunca veio.”"},
		{"kind": "clothes", "name": "uma touca de renda", "text": "Uma touca minúscula. Cheira a naftalina e a baú fechado."},
		{"kind": "clothes", "name": "um sapatinho", "rule": "dark", "text": "Um sapatinho de pano. A sola está gasta, como se alguém tivesse andado muito com ele."},
		{"kind": "clothes", "name": "um laço de fita", "text": "Um laço vermelho. Ivone escreveu no diário que a boneca não gostava de ficar sem ele."},
	],
	5: [
		{"kind": "letter", "name": "uma carta fechada", "text": "Da mãe de Ivone, de muitos anos atrás: “Filha, não abra a porta para ninguém depois que escurecer.”"},
		{"kind": "letter", "name": "uma carta fechada", "rule": "mailbox", "text": "Sem remetente. Dentro, só uma linha: “É a mamãe. Abre.”"},
		{"kind": "letter", "name": "uma carta fechada", "text": "Da prefeitura: aviso de que a casa estava abandonada havia dois anos."},
		{"kind": "letter", "name": "uma carta fechada", "text": "De Ivone para ninguém: “Tranquei Breu do lado de fora. Me perdoa. Eu precisava de silêncio.”"},
	],
	6: [
		{"kind": "page", "name": "a última página do diário", "text": "“Sem ele, a casa ficou fria. Algo sobe a escada quando eu apago a luz.”"},
		{"kind": "tape", "name": "a última fita", "text": "Só água correndo. E, no fim, um miado longe, do lado de fora."},
		{"kind": "ring", "name": "a aliança de Ivone", "text": "A outra aliança, a do marido. Estava no ralo da banheira."},
		{"kind": "clothes", "name": "o lenço de Ivone", "text": "O lenço que ela usa na foto. Tem pelos pretos de gato presos no tecido."},
		{"kind": "letter", "name": "um bilhete na porta", "text": "Com a letra tremida de Ivone: “Breu, se você voltar, eu deixo a janela aberta.”"},
	],
	# the last night: these two come with the three of the ritual (foto, coleira, chave)
	7: [
		{"kind": "page", "name": "uma página solta do diário", "text": "“Se alguém ler isto: o círculo não prende ninguém. Ele só lembra à casa quem mora nela.”"},
		{"kind": "letter", "name": "uma carta nunca enviada", "text": "“Breu, a casa é sua. Eu só cuidei dela enquanto você não voltava.”"},
	],
}

## what each rule asks of the cat (shown after the object's name in the night list)
const RELIC_RULES := {
	"wash": "suja de lama: lave na pia do banheiro",
	"drain": "caiu no ralo da pia do banheiro de baixo",
	"dark": "só aparece com a luz do cômodo apagada",
	"mailbox": "na caixa de correio, lá fora, na porteira",
}
## night 6: the circle takes Ivone's last things only in the order of her diary
const RELIC_ORDER_NIGHT := 6
const RELIC_ORDER_HINT := "o diário, a fita, a aliança, o lenço e por último o bilhete"

const DAY_SCENES := {1: "move_in", 2: "tv", 3: "bath", 4: "davi", 5: "phone", 6: "diary", 7: "eve"}

## Clara getting home: arriving and filling the bowl, in a tone that follows the week
const AFTERNOON_LINES := {
	1: {"arrive": "Chegamos, {cat}! Casa nova!", "box_down": "Êêêêê! Acabou a mudança!", "bowl": "Primeira janta na casa nova. Vem comer comigo, {cat}.",
		"call": ["{cat}! Vem comer!", "Psss, psss... {cat}? A ração tá aqui.", "Vem, {cat}, antes que esfrie. Brincadeira, é ração."],
		"ate": "Isso! Come tudo, gatinho.", "ate_late": "Ah, deixa. Você come depois.",
		"key_ask": "{cat}, me traz a chave que ficou na caixa? Vou abrir o cadeado do porão.",
		"key_down": "Vou descer e ver esse porão de uma vez.",
		"key_wait": ["{cat}? A chave, lá na sala, em cima da caixa!", "Cadê você, {cat}? Tô aqui embaixo.", "Traz a chave pra mim, {cat}?"],
		"key_thanks": "Você trouxe! Que gato esperto.", "key_lock": "Abriu! Só caixa velha da Dona Ivone... amanhã eu olho com calma.",
		"key_none": "Deixa pra lá. Amanhã eu acho essa chave."},
	2: {"arrive": "Cheguei, {cat}! Mais uma entrevista. Foi ótima. Acho.", "bowl": "Sua ração, senhor gato. Pelo menos um de nós janta direito."},
	3: {"arrive": "Oi, {cat}. Dormi mal de novo... mas tá tudo certo.", "bowl": "Come. Eu preciso é de um banho bem quente."},
	4: {"arrive": "Hoje chega o Davi, {cat}! Meu irmão. Se comporta.", "bowl": "Come antes que o Davi chegue e roube a sua atenção."},
	5: {"arrive": "{cat}? Ah, tá aí. Essa casa tá cada dia mais fria.", "bowl": "Come. Eu tô sem fome nenhuma."},
	6: {"arrive": "Cheguei... Ficou bem sozinho aqui, {cat}?", "bowl": "Aqui. Hoje fica pertinho de mim, tá?"},
	7: {"arrive": "Última noite da semana, {cat}. A gente consegue.", "bowl": "Come bem. A noite hoje vai ser longa."},
}

## what the cat is asked to do each afternoon (the tasks panel); the patience extras and the bed come after
const AFTERNOON_TASKS := {
	1: [{"id": "fed", "text": "Coma com a Clara"}, {"id": "key", "text": "Leve a chave para a Clara no porão"}],
	2: [{"id": "lap", "text": "Suba no colo da Clara"}],
	3: [{"id": "bath", "text": "Tire a Clara da banheira"}],
	4: [{"id": "scene", "text": "Receba o Davi com a Clara"}],
	5: [{"id": "scene", "text": "Fique com a Clara no telefonema"}],
	6: [{"id": "scene", "text": "Veja o que o Davi trouxe"}],
	7: [{"id": "scene", "text": "Fique de olho com eles na sala"}],
}

## the extras that win Clara's patience for the night
const PATIENCE_TASKS := [
	{"id": "pet", "text": "Peça carinho"},
	{"id": "fed", "text": "Coma a ração"},
	{"id": "played", "text": "Leve o ratinho para a Clara"},
]
## eating is every afternoon; two of these change from day to day (Game._aft_extras)
const PATIENCE_POOL := [
	{"id": "pet", "text": "Peça carinho"},
	{"id": "played", "text": "Leve o ratinho para a Clara"},
	{"id": "yarn", "text": "Leve o novelo de lã (do sofá) para a Clara"},
	{"id": "water", "text": "Mie na tigela de água vazia"},
	{"id": "sun", "text": "Tire um cochilo no sol da janela da sala"},
]
const YARN_LINES := ["Meu novelo! Você desfez tudo, né? Tudo bem, vem cá.", "Ah, era isso que você queria? Brincar de novelo?"]
const WATER_LINES := ["Acabou a sua água? Desculpa, {cat}. Já vou.", "Tô indo, tô indo. Água fresquinha pro senhor."]
const SUN_LINES := ["Olha ele no solzinho... queria ser gato.", "Isso, aproveita o sol, {cat}."]

## in bed at the end of every afternoon, waiting for the cat
const BED_CALL := "Vem, {cat}. Vem deitar comigo."

## on her way to bed Clara notices what the cat changed in the morning (only what is on her way):
## task id -> [where it is, what she says]
const TASK_COMMENTS := {
	"duct": [Vector3(10.8, 0.0, 3.6), "Quem abriu a grade do duto? ...Foi você, {cat}?"],
	"box0": [Vector3(0, 0, 0), "Essa caixa não tava aí. Ou tava?"],
	"box1": [Vector3(0, 0, 0), "Outra caixa fora do lugar... {cat}, você anda empurrando as coisas?"],
	"basculante": [Vector3(10.4, 3.0, 6.0), "A janelinha do banheiro aberta... foi o vento, né?"],
	"flap": [Vector3(11.8, 0.0, 9.2), "A portinhola da cozinha tá solta. Você que empurrou, né?"],
	"nightlight": [Vector3(0, 0, 0), "Ué, a luz noturna saiu da despensa?"],
	"hatch": [Vector3(6.4, 3.0, 2.6), "O alçapão do sótão aberto... eu não mexi nisso."],
	"porao_win": [Vector3(4.0, -0.5, 0.2), "Tá entrando um ventinho... a janela do porão tá aberta?"],
}

## closing the house: extra checks as the week goes on, and her last word before bed
const CLOSE_LINES := {
	1: "Pronto, trancado. Amanhã eu desfaço as caixas.",
	2: "Porta trancada. Janela fechada. Tudo certo... né?",
	3: "Ainda bem que o Davi chega amanhã. Não que eu precise. Mas é bom.",
	4: "Trancado. Agora somos três nesta casa.",
	5: "Conferi duas vezes. Tá tudo fechado.",
	6: "Tranquei tudo. E deixei a chave na fechadura.",
	7: "Tudo trancado. Seja o que for, já tá aqui dentro.",
}

## the diary Davi finds at the bottom of the doll's box (day 6); the pages of night 1 are torn out
const DIARY_LINES := [
	"“Ele não dorme. Passa a noite inteira olhando para a porta do porão.”",
	"“Hoje o tranquei do lado de fora. Miou tanto... eu precisava de silêncio.”",
	"“Sem ele, a casa ficou fria. Aquilo mora no porão, embaixo do círculo. É de lá que sobe quando eu apago a luz.”",
]

const ENDINGS := {
	"good": {
		"title": "Amanhecer",
		"lines": [
			"O círculo se fechou com um som de vidro quebrando ao contrário.",
			"Pela primeira vez em meses, Clara dormiu a noite inteira.",
			"Nunca houve fantasmas. Só um gato que não saiu do lado dela.",
			"Na cozinha, Davi disse que ia ficar mais umas semanas. Clara não discutiu.",
			"\"Vou ligar praquela terapeuta que a mãe indicou. Só pra conversar.\" E encheu a tigela de {cat}.",
		],
	},
	"secret": {
		"title": "Sete vidas",
		"lines": [
			"O círculo se fechou. A casa respirou aliviada.",
			"Pela primeira vez em meses, Clara dormiu a noite inteira, com {cat} no peito.",
			"Nunca houve fantasmas. Só um gato que não saiu do lado dela. Nem uma noite.",
			"No telhado, à luz da manhã, um gato preto piscou devagar para {cat}. Depois de tantos anos, foi embora em paz.",
		],
	},
	"lives": {
		"title": "A sétima vida",
		"lines": [
			"A última vida de {cat} se apagou no escuro da casa.",
			"Sem ninguém por perto à noite, Clara segurou as pontas sozinha. Até não segurar mais.",
			"Os dias ficaram iguais. As cortinas, fechadas. Como na casa de Dona Ivone.",
			"No telhado, agora são dois gatos olhando a janela, esperando alguém abrir.",
		],
	},
	"bad": {
		"title": "Mudança",
		"lines": [
			"Clara e Davi passaram pelas sete noites.",
			"Na semana seguinte, colocaram a casa à venda. Clara disse que tava tudo bem.",
			"Levaram as caixas, os móveis e, sem perceber, todo o resto também.",
			"No porão, alguma coisa continuava esperando.",
		],
	},
}

## Clara on waking up after night N: what the night left behind looks ordinary in daylight
const MORNING_LINES := {
	1: "Bom dia, {cat}. Dormi no sofá de novo? ...Quem acendeu a luz da sala?",
	2: "Meu celular tava desligado no chão. Foi você que puxou o fio, né?",
	3: "A torneira da cozinha tava aberta de madrugada. Ainda bem que você não deixou alagar.",
	4: "Sonhei com aquela boneca. Que bobagem.",
	5: "Alguém ligou às duas da manhã. Eu nem atendi. Melhor assim.",
	6: "Dormi um pouco melhor. Acho que foi você, {cat}.",
}

## what Clara (and from day 4 Davi) says to the cat when it hangs around them in the afternoon,
## in order, each once (Game._tick_chatter)
const CHATTER := {
	1: {"clara": ["Cheiro de tinta nova. Gostou da casa, {cat}?", "Amanhã eu monto a estante. Ou depois de amanhã.", "Recomeço, {cat}. Casa nova, vida nova. Né?"]},
	2: {"clara": ["Sabe o que é mandar trinta currículos, {cat}? Pois é.", "Tô ótima. Sério. Para de me olhar assim.", "Você nunca precisou de emprego. Sortudo."]},
	3: {"clara": ["Acordei às três da manhã de novo. Fiquei olhando o teto.", "Se eu ficar parada, eu penso. Então eu não fico parada.", "Você é o único que não me pergunta se eu tô bem, {cat}. Obrigada."]},
	4: {"clara": ["O Davi vai rir da casa. Deixa ele.", "Ele tem vinte e dois anos e ainda me liga pra perguntar como frita ovo."],
		"davi": ["Ô, {cat}. Cuidando bem dela?", "Atchim! Tudo bem, tudo bem. Vale a pena."]},
	5: {"clara": ["Se o telefone tocar à noite, a gente não atende. Combinado?", "Eu não vou voltar, {cat}. Não vou."],
		"davi": ["Ela tá bem mesmo, {cat}? Pisca uma vez pra sim.", "Ela acha que eu não percebo. Eu percebo."]},
	6: {"clara": ["Essa Ivone... ninguém veio ver ela. Quarenta anos.", "Ainda bem que você tá aqui, {cat}."],
		"davi": ["Você cuida dela, né, {cat}? Ela não deixa ninguém cuidar.", "Amanhã é o último dia. Depois a gente vê."]},
	7: {"clara": ["Hoje eu deixo a luz do quarto acesa. Não ri.", "Fica comigo hoje, {cat}?"],
		"davi": ["Eu tô aqui, mana. Tô aqui."]},
}

## short talks between Clara and Davi when both are near each other and the cat is close
## ([who, line] in order)
const TALKS := {
	4: [[["davi", "Mana, a mãe mandou dizer que..."], ["clara", "Eu sei o que a mãe mandou dizer."], ["davi", "Ela mandou dizer que te ama. E que você tá magra."], ["clara", "...Fala pra ela que eu tô ótima."]]],
	5: [[["davi", "Quem era no telefone?"], ["clara", "Ninguém."], ["davi", "O Rafael."], ["clara", "Ninguém, Davi."], ["davi", "Tá. Quer pão de queijo? Comprei na estrada."], ["clara", "...Quero."]]],
	6: [[["clara", "Ela trancou o gato do lado de fora pra ter silêncio. Dá pra acreditar?"], ["davi", "Dá. As pessoas fazem isso. Trancam tudo pra fora."], ["clara", "Eu não tranquei ninguém."], ["davi", "Não. Só não deixa ninguém entrar."]]],
	7: [[["davi", "Mana."], ["clara", "Hm."], ["davi", "Nada. Só... tô aqui."], ["clara", "Eu sei, Davi. Eu sei."]]],
}

const CREDITS := [
	["Sete Vidas", ""],
	["Um jogo de terror sobre proteger quem você ama", ""],
	["Se você está passando por algo parecido, fale com alguém.", "CVV 188 (Brasil) · findahelpline.com"],
	["Design, código, modelos 3D, texturas e áudio sintetizado", "feitos com Claude"],
	["Motor", "Godot 4 + Blender"],
	["Texturas, modelos e céus", "Poly Haven (CC0)"],
	["Pessoas", "VRoid Studio · fantasmas MakeHuman / MPFB (CC0)"],
	["Animações", "Quaternius, Universal Animation Library (CC0)"],
	["Obrigado por jogar.", ""],
]
