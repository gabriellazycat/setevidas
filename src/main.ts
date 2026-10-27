import '@fontsource/cormorant-garamond/400.css';
import '@fontsource/cormorant-garamond/500.css';
import '@fontsource/cormorant-garamond/400-italic.css';
import '@fontsource/inter/400.css';
import '@fontsource/inter/500.css';
import '@fontsource/inter/600.css';
import './ui/style.css';
import { Game } from './game/Game';

const app = document.getElementById('app')!;

function webglOk() {
  try {
    const c = document.createElement('canvas');
    return !!c.getContext('webgl2');
  } catch {
    return false;
  }
}

if (!webglOk()) {
  app.innerHTML = '<div style="display:flex;height:100%;align-items:center;justify-content:center;font-family:serif;font-size:22px;color:#ccc;text-align:center;padding:24px">Sete Vidas precisa de WebGL 2.<br/>Atualize o navegador ou ative a aceleração de hardware.</div>';
} else {
  const game = new Game(app);
  (window as unknown as { game: Game }).game = game;
  game.boot().catch((e) => {
    console.error(e);
    app.insertAdjacentHTML('beforeend', `<pre style="position:fixed;left:12px;bottom:12px;color:#f88;font-size:12px;white-space:pre-wrap;max-width:90vw">${String(e?.stack ?? e)}</pre>`);
  });
}
