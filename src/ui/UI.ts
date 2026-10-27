import { Settings, type SettingsData } from '../core/Settings';
import { KEY_LABEL, type Action, type Device } from '../core/Input';
import { CREDITS } from '../game/Story';

type Cb = () => void;

function el<K extends keyof HTMLElementTagNameMap>(tag: K, cls = '', html = ''): HTMLElementTagNameMap[K] {
  const e = document.createElement(tag);
  if (cls) e.className = cls;
  if (html) e.innerHTML = html;
  return e;
}

const esc = (s: string) => s.replace(/[&<>]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;' })[c]!);

export class UI {
  root: HTMLElement;
  private hud: HTMLElement;
  private promptEl: HTMLElement;
  private promptText: HTMLElement;
  private promptKey: HTMLElement;
  private promptRing: SVGCircleElement;
  private subsEl: HTMLElement;
  private hintsEl: HTMLElement;
  private titleEl: HTMLElement;
  private threatEl: HTMLElement;
  private tasksEl: HTMLElement;
  private clockEl: HTMLElement;
  private assistEl: HTMLElement;
  private arrowEl: HTMLElement;
  private overlay: HTMLElement | null = null;
  private loadingEl: HTMLElement | null = null;
  private clickPlay: HTMLElement;
  private alertEl: HTMLElement;
  private hissEl: HTMLElement;
  private alertKey = '';
  private hissState = '';
  onSound?: (k: 'hover' | 'select' | 'back') => void;
  device: Device = 'kbm';
  private navCooldown = 0;
  private padPrev: boolean[] = [];
  private backHandler: Cb | null = null;

  constructor(parent: HTMLElement) {
    this.root = el('div');
    this.root.id = 'ui';
    parent.appendChild(this.root);
    this.hud = el('div', 'layer');
    this.root.appendChild(this.hud);

    this.promptEl = el('div', 'prompt');
    const ring = el('div', 'ring');
    ring.innerHTML = `<svg viewBox="0 0 30 30"><circle cx="15" cy="15" r="13" fill="rgba(0,0,0,.35)" stroke="rgba(255,255,255,.25)" stroke-width="1.5"/><circle class="p" cx="15" cy="15" r="13" fill="none" stroke="#e8b46a" stroke-width="2.2" stroke-dasharray="81.7" stroke-dashoffset="81.7"/></svg><span class="k"></span>`;
    this.promptRing = ring.querySelector('circle.p')!;
    this.promptKey = ring.querySelector('.k')!;
    this.promptText = el('span');
    this.promptEl.append(ring, this.promptText);
    this.promptEl.style.opacity = '0';
    this.subsEl = el('div', 'subs');
    this.hintsEl = el('div', 'hints');
    this.titleEl = el('div', 'titlecard', '<div class="big"></div><div class="small"></div>');
    this.threatEl = el('div', 'threatcard', '<div class="lab">Nova ameaça</div><div class="nm"></div><div class="ds"></div>');
    this.tasksEl = el('div', 'tasks hidden');
    this.clockEl = el('div', 'clock hidden');
    this.assistEl = el('div', 'assist hidden');
    this.arrowEl = el('div', 'arrow hidden', '<i></i>');
    this.clickPlay = el('div', 'layer clickplay hidden', 'Clique para continuar');
    this.alertEl = el('div', 'alertbar');
    this.hissEl = el('div', 'hissprompt');
    this.hud.append(this.promptEl, this.hissEl, this.alertEl, this.subsEl, this.hintsEl, this.titleEl, this.threatEl, this.tasksEl, this.clockEl, this.assistEl, this.arrowEl, this.clickPlay);
    this.applySubSize();
    Settings.onChange(() => this.applySubSize());

    window.addEventListener('keydown', (e) => this.onKey(e));
  }

  private applySubSize() {
    this.subsEl.classList.toggle('l', Settings.data.subtitleSize === 'l');
  }

  key(a: Action) {
    return KEY_LABEL[a][this.device];
  }

  /* ============================================================ loading */
  showLoading() {
    const l = el('div', 'layer loading interactive');
    l.innerHTML = `<div class="title">Sete Vidas</div><div class="bar"><i></i></div><div class="msg">Preparando a casa</div><div class="tip">Use fones de ouvido. Neste jogo, o som é metade do medo.</div>`;
    this.root.appendChild(l);
    this.loadingEl = l;
  }
  loading(p: number, msg: string) {
    if (!this.loadingEl) return;
    (this.loadingEl.querySelector('.bar i') as HTMLElement).style.width = `${Math.round(p * 100)}%`;
    (this.loadingEl.querySelector('.msg') as HTMLElement).textContent = msg;
  }
  hideLoading() {
    const l = this.loadingEl;
    if (!l) return;
    l.style.opacity = '0';
    setTimeout(() => l.remove(), 1300);
    this.loadingEl = null;
  }

  /* ============================================================ overlays */
  private setOverlay(o: HTMLElement | null, back: Cb | null = null) {
    this.overlay?.remove();
    this.overlay = o;
    this.backHandler = back;
    if (o) {
      this.root.appendChild(o);
      const first = o.querySelector<HTMLElement>('.btn:not(:disabled), .small-btn');
      setTimeout(() => first?.focus({ preventScroll: true }), 30);
    }
  }
  closeOverlay() {
    this.setOverlay(null);
  }
  get overlayOpen() {
    return !!this.overlay;
  }

  private button(label: string, cb: Cb, disabled = false, extra = '') {
    const b = el('button', 'btn', esc(label) + (extra ? `<small>${extra}</small>` : ''));
    b.disabled = disabled;
    b.addEventListener('mouseenter', () => {
      if (!b.disabled) {
        b.focus({ preventScroll: true });
        this.onSound?.('hover');
      }
    });
    b.addEventListener('click', () => {
      if (b.disabled) return;
      this.onSound?.('select');
      cb();
    });
    return b;
  }

  showMenu(o: { canContinue: boolean; continueLabel: string; unlocked: number; onNew: Cb; onContinue: Cb; onNight: (n: number) => void; onSettings: Cb; onCredits: Cb }) {
    const m = el('div', 'layer menu interactive');
    const block = el('div', 'block');
    block.innerHTML = `<h1>Sete Vidas</h1><div class="tag">Ela não vê o que anda pela casa. Você vê.</div>`;
    const nav = el('nav');
    if (o.canContinue) nav.append(this.button('Continuar', o.onContinue, false, o.continueLabel));
    nav.append(this.button('Novo jogo', o.onNew));
    const nightsBtn = this.button('Escolher noite', () => {
      nights.classList.toggle('hidden');
    }, o.unlocked < 2);
    nav.append(nightsBtn);
    const nights = el('div', 'nights hidden');
    for (let i = 1; i <= 7; i++) {
      const b = el('button', 'n', String(i));
      b.disabled = i > o.unlocked;
      b.addEventListener('click', () => {
        this.onSound?.('select');
        o.onNight(i);
      });
      nights.append(b);
    }
    nav.append(nights);
    nav.append(this.button('Opções', o.onSettings), this.button('Créditos', o.onCredits));
    block.append(nav);
    m.append(block, el('div', 'foot', 'Fones de ouvido recomendados · v1.0'));
    this.setOverlay(m);
  }

  showPause(o: { onResume: Cb; onRestartNight: Cb | null; onRestartDay: Cb | null; onSettings: Cb; onMenu: Cb; title: string }) {
    const v = el('div', 'layer veil interactive');
    const p = el('div', 'panel');
    p.innerHTML = `<h2>Pausado</h2><div class="sub">${esc(o.title)}</div>`;
    const nav = el('nav');
    nav.append(this.button('Continuar', o.onResume));
    if (o.onRestartNight) nav.append(this.button('Recomeçar a noite', o.onRestartNight));
    if (o.onRestartDay) nav.append(this.button('Recomeçar o dia', o.onRestartDay));
    nav.append(this.button('Opções', o.onSettings), this.button('Menu principal', o.onMenu));
    p.append(nav);
    v.append(p);
    this.setOverlay(v, o.onResume);
  }

  showFail(o: { title: string; sub: string; why?: string; tip?: string; facts?: string[]; onNight: Cb; onDay: Cb | null; onMenu: Cb }) {
    const v = el('div', 'layer veil interactive fail');
    const p = el('div', 'panel');
    p.innerHTML = `<h2>${esc(o.title)}</h2><div class="sub">${esc(o.sub)}</div>`;
    if (o.why) p.append(el('p', 'why', esc(o.why)));
    if (o.facts?.length) p.append(el('ul', 'facts', o.facts.map((f) => `<li>${esc(f)}</li>`).join('')));
    if (o.tip) p.append(el('div', 'tip', `<b>Como evitar</b>${esc(o.tip)}`));
    const nav = el('nav');
    nav.append(this.button('Recomeçar a noite', o.onNight, false, 'mantém o preparo'));
    nav.append(this.button('Recomeçar o dia', o.onDay ?? (() => {}), !o.onDay, o.onDay ? 'volta para a manhã' : 'não há manhã antes da noite 1'));
    nav.append(this.button('Menu principal', o.onMenu));
    p.append(nav);
    v.append(p);
    this.setOverlay(v);
  }

  showSummary(o: { title: string; lines: [string, string][]; onContinue: Cb; button?: string }) {
    const v = el('div', 'layer veil interactive summary');
    const p = el('div', 'panel');
    p.innerHTML = `<h2>${esc(o.title)}</h2><div class="sub">Clara sobreviveu</div>`;
    for (const [a, b] of o.lines) p.append(el('div', 'line', `<span>${esc(a)}</span><span>${esc(b)}</span>`));
    const act = el('div', 'actions');
    const c = el('button', 'small-btn primary', o.button ?? 'Continuar');
    c.addEventListener('click', () => {
      this.onSound?.('select');
      o.onContinue();
    });
    act.append(el('span'), c);
    p.append(act);
    v.append(p);
    this.setOverlay(v);
    setTimeout(() => c.focus(), 50);
  }

  /** sequence of black cards with text */
  showCards(cards: string[], onDone: Cb, perCard = 3.6) {
    const v = el('div', 'layer letter interactive');
    const card = el('div', 'card');
    v.append(card, el('div', 'skip', `Pular · ${this.key('confirm')}`));
    this.setOverlay(v, () => finish());
    let i = 0;
    let timer = 0;
    let done = false;
    const finish = () => {
      if (done) return;
      done = true;
      clearTimeout(timer);
      v.style.opacity = '0';
      setTimeout(() => {
        if (this.overlay === v) this.setOverlay(null);
        onDone();
      }, 900);
    };
    const next = () => {
      if (i >= cards.length) return finish();
      card.classList.remove('on');
      setTimeout(() => {
        card.textContent = cards[i++];
        card.classList.add('on');
        timer = window.setTimeout(next, perCard * 1000);
      }, i === 0 ? 300 : 1200);
    };
    v.addEventListener('click', () => finish());
    this.skipHandler = finish;
    next();
  }
  skipHandler: Cb | null = null;

  showEnding(title: string, lines: string[], onDone: Cb) {
    const v = el('div', 'layer ending interactive');
    const h = el('h2', '', esc(title));
    v.append(h);
    const ps = lines.map((l) => {
      const p = el('p', '', esc(l));
      v.append(p);
      return p;
    });
    this.setOverlay(v);
    setTimeout(() => h.classList.add('on'), 400);
    ps.forEach((p, i) => setTimeout(() => p.classList.add('on'), 2600 + i * 3200));
    const total = 2600 + ps.length * 3200 + 2500;
    const cont = el('button', 'small-btn', 'Continuar');
    cont.style.marginTop = '40px';
    cont.style.opacity = '0';
    cont.style.transition = 'opacity 1.5s';
    cont.addEventListener('click', () => onDone());
    v.append(cont);
    setTimeout(() => {
      cont.style.opacity = '1';
      cont.focus();
    }, total);
  }

  showCredits(onDone: Cb) {
    const v = el('div', 'layer ending credits interactive');
    for (const [a, b] of CREDITS) {
      const c = el('div', 'c on', `<b>${esc(a)}</b>${b ? `<span>${esc(b)}</span>` : ''}`);
      v.append(c);
    }
    const back = el('button', 'small-btn', 'Voltar');
    back.style.marginTop = '30px';
    back.addEventListener('click', () => {
      this.onSound?.('back');
      onDone();
    });
    v.append(back);
    this.setOverlay(v, onDone);
  }

  /* ============================================================ settings */
  showSettings(onClose: Cb) {
    const v = el('div', 'layer veil interactive');
    const p = el('div', 'panel settings');
    p.innerHTML = `<h2>Opções</h2><div class="sub">As mudanças são salvas automaticamente</div>`;
    const tabs = el('div', 'tabs');
    const rows = el('div', 'rows');
    const tabNames = ['Jogo', 'Controles', 'Vídeo', 'Áudio', 'Acessibilidade'];
    const s = Settings;
    const slider = (label: string, k: keyof SettingsData, min: number, max: number, step: number, desc = '', fmt = (x: number) => x.toFixed(2)) => {
      const r = el('div', 'row');
      const lab = el('label', '', `${esc(label)}${desc ? `<span class="desc">${esc(desc)}</span>` : ''}`);
      const wrap = el('div');
      wrap.style.display = 'grid';
      wrap.style.gridTemplateColumns = '1fr 48px';
      wrap.style.gap = '10px';
      wrap.style.alignItems = 'center';
      const inp = el('input') as HTMLInputElement;
      inp.type = 'range';
      inp.min = String(min);
      inp.max = String(max);
      inp.step = String(step);
      inp.value = String(s.data[k]);
      inp.className = 'interactive';
      const val = el('span', '', fmt(Number(inp.value)));
      val.style.fontSize = '12px';
      val.style.color = 'var(--muted)';
      inp.addEventListener('input', () => {
        s.set(k, Number(inp.value) as never);
        val.textContent = fmt(Number(inp.value));
      });
      wrap.append(inp, val);
      r.append(lab, wrap);
      return r;
    };
    const toggle = (label: string, k: keyof SettingsData, desc = '') => {
      const r = el('div', 'row');
      const lab = el('label', '', `${esc(label)}${desc ? `<span class="desc">${esc(desc)}</span>` : ''}`);
      const t = el('button', 'toggle' + (s.data[k] ? ' on' : ''));
      t.addEventListener('click', () => {
        s.set(k, !s.data[k] as never);
        t.classList.toggle('on', !!s.data[k]);
        this.onSound?.('select');
      });
      r.append(lab, t);
      return r;
    };
    const select = (label: string, k: keyof SettingsData, opts: [string, string][], desc = '') => {
      const r = el('div', 'row');
      const lab = el('label', '', `${esc(label)}${desc ? `<span class="desc">${esc(desc)}</span>` : ''}`);
      const sel = el('select', 'interactive') as HTMLSelectElement;
      for (const [v, t] of opts) {
        const o = el('option') as HTMLOptionElement;
        o.value = v;
        o.textContent = t;
        sel.append(o);
      }
      sel.value = String(s.data[k]);
      sel.addEventListener('change', () => s.set(k, sel.value as never));
      r.append(lab, sel);
      return r;
    };
    const text = (label: string, k: keyof SettingsData, desc = '') => {
      const r = el('div', 'row');
      const lab = el('label', '', `${esc(label)}${desc ? `<span class="desc">${esc(desc)}</span>` : ''}`);
      const inp = el('input', 'interactive') as HTMLInputElement;
      inp.type = 'text';
      inp.maxLength = 16;
      inp.value = String(s.data[k]);
      inp.addEventListener('change', () => s.set(k, (inp.value.trim() || 'Mingau') as never));
      inp.addEventListener('keydown', (e) => e.stopPropagation());
      r.append(lab, inp);
      return r;
    };
    const pct = (x: number) => `${Math.round(x * 100)}%`;
    const pages: (() => HTMLElement[])[] = [
      () => [
        text('Nome do gato', 'catName', 'Como Clara chama você'),
        slider('Velocidade das noites', 'nightSpeed', 0.7, 1, 0.05, 'Valores menores deixam as assombrações mais lentas', pct),
        toggle('Visão de Gato alterna', 'visionToggle', 'Desligado: segure o botão'),
        toggle('Esgueirar alterna', 'sneakToggle', 'Desligado: segure o botão'),
        toggle('Tremor de câmera', 'cameraShake'),
      ],
      () => {
        const wrap = el('div', 'keys');
        wrap.append(el('div', 'h', 'Ação'), el('div', 'h', 'Teclado'), el('div', 'h', 'Controle'));
        const list: [string, string, string][] = [
          ['Mover', 'W A S D', 'Analógico esq.'],
          ['Câmera', 'Mouse', 'Analógico dir.'],
          ['Pular (aponte para o círculo)', 'Espaço', 'A'],
          ['Interagir / segurar', 'E · clique', 'X'],
          ['Visão de Gato', 'Botão direito · V', 'LT'],
          ['Miar', 'Q', 'Y'],
          ['Bufar', 'F', 'RB'],
          ['Correr', 'Shift', 'RT · L3'],
          ['Esgueirar', 'Ctrl · C', 'B'],
          ['Hora e tarefas', 'Tab', 'Select'],
          ['Pausar', 'Esc', 'Start'],
        ];
        for (const [a, k, g] of list) wrap.append(el('div', '', esc(a)), el('div', '', `<span class="kbd">${esc(k)}</span>`), el('div', '', `<span class="kbd">${esc(g)}</span>`));
        return [
          slider('Sensibilidade do mouse', 'sensitivity', 0.2, 3, 0.05),
          slider('Sensibilidade do controle', 'padSensitivity', 0.3, 2.5, 0.05),
          toggle('Inverter eixo vertical', 'invertY'),
          wrap,
        ];
      },
      () => [
        select('Qualidade', 'quality', [
          ['low', 'Baixa'],
          ['medium', 'Média'],
          ['high', 'Alta'],
          ['ultra', 'Ultra'],
        ], 'Sombras, antisserrilhado e resolução'),
        slider('Escala de resolução', 'renderScale', 0.5, 1, 0.05, '', pct),
        slider('Campo de visão', 'fov', 55, 90, 1, '', (x) => `${x}°`),
        slider('Brilho', 'brightness', 0.7, 1.6, 0.02, 'Ajuste até o gato quase sumir no escuro', pct),
        toggle('Brilho das luzes (bloom)', 'bloom'),
        toggle('Granulado de filme', 'grain'),
      ],
      () => [
        slider('Volume geral', 'master', 0, 1, 0.01, '', pct),
        slider('Música', 'music', 0, 1, 0.01, '', pct),
        slider('Efeitos', 'sfx', 0, 1, 0.01, '', pct),
        slider('Ambiente', 'ambience', 0, 1, 0.01, '', pct),
      ],
      () => [
        toggle('Modo assistido', 'assist', 'Mostra barras de Medo, Paciência e Foco, e uma seta para o perigo'),
        toggle('Legendas', 'subtitles'),
        select('Tamanho das legendas', 'subtitleSize', [
          ['m', 'Normal'],
          ['l', 'Grande'],
        ]),
        toggle('Reduzir sustos e flashes', 'reduceFlashes', 'Sem clarões e com sustos mais suaves'),
      ],
    ];
    let cur = 0;
    const render = () => {
      rows.innerHTML = '';
      for (const r of pages[cur]()) rows.append(r);
      tabs.querySelectorAll('.tab').forEach((t, i) => t.classList.toggle('on', i === cur));
    };
    tabNames.forEach((n, i) => {
      const t = el('button', 'tab', n);
      t.addEventListener('click', () => {
        cur = i;
        render();
        this.onSound?.('hover');
      });
      tabs.append(t);
    });
    const act = el('div', 'actions');
    const reset = el('button', 'small-btn', 'Restaurar padrões');
    reset.addEventListener('click', () => {
      Settings.reset();
      render();
    });
    const close = el('button', 'small-btn primary', 'Voltar');
    close.addEventListener('click', () => {
      this.onSound?.('back');
      onClose();
    });
    act.append(reset, close);
    p.append(tabs, rows, act);
    v.append(p);
    render();
    this.setOverlay(v, onClose);
  }

  /* ============================================================ HUD */
  private promptState = '';
  prompt(text: string | null, action: Action = 'interact', hold = 0) {
    if (!text) {
      if (this.promptState !== '') {
        this.promptEl.style.opacity = '0';
        this.promptState = '';
      }
      return;
    }
    const key = this.key(action);
    const st = text + key;
    if (st !== this.promptState) {
      this.promptState = st;
      this.promptText.textContent = text;
      this.promptKey.textContent = key.length > 3 ? key.slice(0, 1) : key;
      this.promptEl.style.opacity = '1';
    }
    this.promptRing.style.strokeDashoffset = String(81.7 * (1 - hold));
  }

  say(speaker: string, text: string, dur: number, kind = 'normal') {
    if (!Settings.data.subtitles && kind !== 'narrator' && kind !== 'ghost') return;
    const line = el('div', `sub-line ${kind}`, `${speaker ? `<b>${esc(speaker)}</b>` : ''}${esc(text)}`);
    this.subsEl.append(line);
    while (this.subsEl.children.length > 3) this.subsEl.firstElementChild?.remove();
    setTimeout(() => {
      line.style.opacity = '0';
      setTimeout(() => line.remove(), 450);
    }, dur * 1000);
  }

  hint(html: string, dur = 6) {
    const h = el('div', 'hint', html);
    this.hintsEl.append(h);
    while (this.hintsEl.children.length > 3) this.hintsEl.firstElementChild?.remove();
    setTimeout(() => {
      h.style.opacity = '0';
      h.style.transform = 'translateX(-10px)';
      setTimeout(() => h.remove(), 550);
    }, dur * 1000);
  }
  clearHints() {
    this.hintsEl.innerHTML = '';
    this.subsEl.innerHTML = '';
  }

  title(big: string, small: string, dur = 3.5) {
    (this.titleEl.querySelector('.big') as HTMLElement).textContent = big;
    (this.titleEl.querySelector('.small') as HTMLElement).textContent = small;
    this.titleEl.classList.add('on');
    clearTimeout((this.titleEl as any)._t);
    (this.titleEl as any)._t = setTimeout(() => this.titleEl.classList.remove('on'), dur * 1000);
  }

  threat(name: string, desc: string) {
    (this.threatEl.querySelector('.nm') as HTMLElement).textContent = name;
    (this.threatEl.querySelector('.ds') as HTMLElement).textContent = desc;
    this.threatEl.classList.add('on');
    clearTimeout((this.threatEl as any)._t);
    (this.threatEl as any)._t = setTimeout(() => this.threatEl.classList.remove('on'), 8000);
  }

  tasks(title: string | null, list: { text: string; done: boolean }[], foot = '') {
    if (!title) {
      this.tasksEl.classList.add('hidden');
      return;
    }
    this.tasksEl.classList.remove('hidden');
    this.tasksEl.innerHTML = `<h4>${esc(title)}</h4>${list.map((t) => `<div class="t ${t.done ? 'done' : ''}"><i></i><span>${esc(t.text)}</span></div>`).join('')}${foot ? `<div class="tm">${esc(foot)}</div>` : ''}`;
  }
  tasksVisible(v: boolean) {
    this.tasksEl.style.opacity = v ? '1' : '0';
  }

  clock(text: string | null, small = '') {
    if (!text) {
      this.clockEl.classList.add('hidden');
      return;
    }
    this.clockEl.classList.remove('hidden');
    this.clockEl.innerHTML = `<small>${esc(small)}</small>${esc(text)}`;
  }

  assist(v: { people: { name: string; fear: number; patience: number }[]; focus: number; arrow: number | null } | null) {
    if (!v) {
      this.assistEl.classList.add('hidden');
      this.arrowEl.classList.add('hidden');
      return;
    }
    this.assistEl.classList.remove('hidden');
    const bar = (label: string, x: number, color: string) => `<div>${label}<div class="b"><i style="width:${Math.round(x)}%;background:${color}"></i></div></div>`;
    this.assistEl.innerHTML =
      v.people.map((p) => bar(`Medo · ${esc(p.name)}`, p.fear, '#d9574a') + bar(`Paciência · ${esc(p.name)}`, p.patience, '#e8b46a')).join('') + bar('Foco', v.focus, '#7ff4ff');
    if (v.arrow === null) this.arrowEl.classList.add('hidden');
    else {
      this.arrowEl.classList.remove('hidden');
      this.arrowEl.style.transform = `rotate(${v.arrow}rad)`;
    }
  }

  /** who is being attacked right now and what to do about it */
  alert(title: string | null, hint = '') {
    const key = title ? `${title}|${hint}` : '';
    if (key === this.alertKey) return;
    this.alertKey = key;
    if (!title) {
      this.alertEl.classList.remove('on');
      return;
    }
    this.alertEl.innerHTML = `<div class="lab">Ataque em andamento</div><div class="nm">${esc(title)}</div><div class="ds">${esc(hint)}</div>`;
    this.alertEl.classList.add('on');
  }

  /** contextual "Bufar" button prompt */
  hiss(state: 'off' | 'ready' | 'weak') {
    const key = `${state}|${this.device}`;
    if (key === this.hissState) return;
    this.hissState = key;
    if (state === 'off') {
      this.hissEl.classList.remove('on', 'weak');
      return;
    }
    this.hissEl.innerHTML = `<span class="kbd">${esc(this.key('hiss'))}</span><span>${state === 'weak' ? 'Bufar (pouco Foco)' : 'Bufar'}</span>`;
    this.hissEl.classList.toggle('weak', state === 'weak');
    this.hissEl.classList.add('on');
  }

  showClickToPlay(v: boolean) {
    this.clickPlay.classList.toggle('hidden', !v);
  }

  hudVisible(v: boolean) {
    this.hud.style.display = v ? '' : 'none';
  }

  /* ============================================================ navigation (keyboard + gamepad) */
  private focusables(): HTMLElement[] {
    if (!this.overlay) return [];
    return Array.from(this.overlay.querySelectorAll<HTMLElement>('.btn:not(:disabled), .small-btn, .tab, .toggle, input, select, .nights .n:not(:disabled)')).filter((e) => e.offsetParent !== null);
  }

  private move(dir: number) {
    const f = this.focusables();
    if (!f.length) return;
    const i = f.indexOf(document.activeElement as HTMLElement);
    const n = f[(i + dir + f.length) % f.length];
    n.focus({ preventScroll: false });
    this.onSound?.('hover');
  }

  private onKey(e: KeyboardEvent) {
    if (!this.overlay) return;
    if (this.skipHandler && (e.code === 'Enter' || e.code === 'Space' || e.code === 'Escape') && this.overlay.classList.contains('letter')) {
      e.preventDefault();
      const s = this.skipHandler;
      this.skipHandler = null;
      s();
      return;
    }
    const target = e.target as HTMLElement;
    const isRange = target instanceof HTMLInputElement && target.type === 'range';
    if (e.code === 'ArrowDown' || (e.code === 'Tab' && !e.shiftKey)) {
      e.preventDefault();
      this.move(1);
    } else if (e.code === 'ArrowUp' || (e.code === 'Tab' && e.shiftKey)) {
      e.preventDefault();
      this.move(-1);
    } else if (e.code === 'Escape') {
      if (this.backHandler) {
        e.preventDefault();
        this.onSound?.('back');
        this.backHandler();
      }
    } else if ((e.code === 'ArrowLeft' || e.code === 'ArrowRight') && !isRange && target.classList.contains('tab')) {
      e.preventDefault();
      this.move(e.code === 'ArrowRight' ? 1 : -1);
    }
  }

  /** poll the gamepad for menu navigation */
  navUpdate(dt: number) {
    if (!this.overlay) return;
    this.navCooldown -= dt;
    const pads = navigator.getGamepads ? navigator.getGamepads() : [];
    const pad = Array.from(pads).find((p) => p && p.connected);
    if (!pad) return;
    const btn = (i: number) => !!pad.buttons[i]?.pressed;
    const edge = (i: number) => {
      const v = btn(i);
      const was = this.padPrev[i];
      this.padPrev[i] = v;
      return v && !was;
    };
    const ay = pad.axes[1] ?? 0;
    if (this.navCooldown <= 0) {
      if (btn(13) || ay > 0.6) {
        this.move(1);
        this.navCooldown = 0.22;
      } else if (btn(12) || ay < -0.6) {
        this.move(-1);
        this.navCooldown = 0.22;
      }
    }
    const active = document.activeElement as HTMLElement | null;
    if (edge(0)) {
      if (this.skipHandler && this.overlay.classList.contains('letter')) {
        const s = this.skipHandler;
        this.skipHandler = null;
        s();
      } else active?.click();
    }
    if (edge(1) || edge(9)) {
      if (this.backHandler) this.backHandler();
    }
    if (active instanceof HTMLInputElement && active.type === 'range' && this.navCooldown <= 0) {
      const ax = pad.axes[0] ?? 0;
      if (Math.abs(ax) > 0.6 || btn(14) || btn(15)) {
        const dir = btn(14) || ax < 0 ? -1 : 1;
        active.value = String(Number(active.value) + dir * Number(active.step));
        active.dispatchEvent(new Event('input'));
        this.navCooldown = 0.08;
      }
    }
  }
}
