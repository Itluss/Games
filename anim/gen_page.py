# -*- coding: utf-8 -*-
import base64, os, json

SP = os.path.dirname(os.path.abspath(__file__))
ANGLES = [('cinematique', 'CINEMATIQUE'), ('profil', 'Profil'), ('troisquarts', 'Trois quarts'), ('face', 'Face'),
          ('dos', 'Dos'), ('misenjoue', 'Mise en joue'),
          ('viseeprofil', 'Marche en visee'), ('viseeface', 'Visee de face'),
          ('courseprofil', 'Course'), ('coursetroisquarts', 'Course 3/4'),
          ('coursetravers', 'Course - camera fixe')]

data = {}
for key, _ in ANGLES:
    d = os.path.join(SP, key)
    fr = []
    for n in sorted(os.listdir(d)):
        with open(os.path.join(d, n), 'rb') as f:
            fr.append('data:image/webp;base64,' + base64.b64encode(f.read()).decode('ascii'))
    data[key] = fr
    print(key, len(fr), 'images')

HEAD = '''<title>Cycle de marche - Policier</title>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Archivo:wght@400;500;600;700&family=IBM+Plex+Mono:wght@400;500&display=swap">
<style>
:root{
  --ground:#EEF0F3; --surface:#FFFFFF; --stage:#25282D;
  --ink:#191C21; --ink-dim:#636B76; --line:#D6DAE0;
  --accent:#C1701E; --accent-soft:rgba(193,112,30,.14);
  --ok:#3F7D5C;
  --shadow:0 1px 2px rgba(20,24,30,.06), 0 8px 24px rgba(20,24,30,.07);
}
@media (prefers-color-scheme: dark){
  :root:not([data-theme="light"]){
    --ground:#121418; --surface:#1B1E24; --stage:#1F2227;
    --ink:#E6E9ED; --ink-dim:#909AA6; --line:#2C313A;
    --accent:#E0873A; --accent-soft:rgba(224,135,58,.16);
    --ok:#63A883;
    --shadow:0 1px 2px rgba(0,0,0,.4), 0 10px 30px rgba(0,0,0,.35);
  }
}
:root[data-theme="dark"]{
  --ground:#121418; --surface:#1B1E24; --stage:#1F2227;
  --ink:#E6E9ED; --ink-dim:#909AA6; --line:#2C313A;
  --accent:#E0873A; --accent-soft:rgba(224,135,58,.16);
  --ok:#63A883;
  --shadow:0 1px 2px rgba(0,0,0,.4), 0 10px 30px rgba(0,0,0,.35);
}
*{box-sizing:border-box}
body{margin:0;background:var(--ground);color:var(--ink);
  font-family:Archivo,"Segoe UI",system-ui,sans-serif;
  -webkit-font-smoothing:antialiased;}
.wrap{max-width:940px;margin:0 auto;padding:32px 20px 56px;
  display:flex;flex-direction:column;gap:20px}
header{display:flex;flex-wrap:wrap;align-items:baseline;gap:10px 16px}
h1{margin:0;font-size:22px;font-weight:600;letter-spacing:-.01em;text-wrap:balance}
.sub{color:var(--ink-dim);font-size:14px}
.mono{font-family:"IBM Plex Mono",ui-monospace,monospace;font-variant-numeric:tabular-nums}

.tabs{display:flex;gap:4px;flex-wrap:wrap}
.tab{appearance:none;border:1px solid var(--line);background:var(--surface);color:var(--ink-dim);
  font:500 13px Archivo,sans-serif;padding:7px 14px;border-radius:6px;cursor:pointer;
  transition:color .15s,border-color .15s,background .15s}
.tab:hover{color:var(--ink)}
.tab[aria-selected="true"]{color:var(--ink);border-color:var(--accent);background:var(--accent-soft)}
.tab:focus-visible{outline:2px solid var(--accent);outline-offset:2px}

.stage{position:relative;background:var(--stage);border:1px solid var(--line);border-radius:10px;
  overflow:hidden;box-shadow:var(--shadow);aspect-ratio:640/380}
.stage canvas{display:block;width:100%;height:100%}
.badge{position:absolute;left:12px;top:12px;display:flex;gap:6px;align-items:center;
  background:rgba(0,0,0,.42);color:#EDEFF2;border-radius:5px;padding:4px 9px;
  font:500 11px "IBM Plex Mono",monospace;letter-spacing:.06em;text-transform:uppercase}
.loading{position:absolute;inset:0;display:grid;place-items:center;color:#B9BFC7;
  font:500 13px Archivo,sans-serif;background:var(--stage)}

.transport{display:flex;align-items:center;gap:14px;flex-wrap:wrap;
  background:var(--surface);border:1px solid var(--line);border-radius:10px;padding:12px 14px}
.play{appearance:none;border:none;background:var(--accent);color:#fff;width:38px;height:38px;
  border-radius:50%;display:grid;place-items:center;cursor:pointer;flex:none}
.play:focus-visible{outline:2px solid var(--accent);outline-offset:3px}
.play svg{width:15px;height:15px;fill:#fff}
.scrub{flex:1 1 220px;appearance:none;height:4px;border-radius:2px;background:var(--line);cursor:pointer}
.scrub::-webkit-slider-thumb{appearance:none;width:14px;height:14px;border-radius:50%;
  background:var(--accent);border:2px solid var(--surface);box-shadow:0 0 0 1px var(--accent)}
.scrub::-moz-range-thumb{width:12px;height:12px;border-radius:50%;background:var(--accent);border:2px solid var(--surface)}
.scrub:focus-visible{outline:2px solid var(--accent);outline-offset:4px}
.count{font-family:"IBM Plex Mono",monospace;font-size:13px;color:var(--ink-dim);
  font-variant-numeric:tabular-nums;flex:none}
.speeds{display:flex;gap:3px;flex:none}
.sp{appearance:none;border:1px solid var(--line);background:transparent;color:var(--ink-dim);
  font:500 12px "IBM Plex Mono",monospace;padding:5px 9px;border-radius:5px;cursor:pointer}
.sp[aria-pressed="true"]{color:var(--ink);border-color:var(--accent);background:var(--accent-soft)}
.sp:focus-visible{outline:2px solid var(--accent);outline-offset:2px}

.specs{display:grid;grid-template-columns:repeat(auto-fit,minmax(150px,1fr));gap:1px;
  background:var(--line);border:1px solid var(--line);border-radius:10px;overflow:hidden}
.spec{background:var(--surface);padding:13px 15px;display:flex;flex-direction:column;gap:3px}
.spec dt{font:500 11px Archivo,sans-serif;letter-spacing:.07em;text-transform:uppercase;color:var(--ink-dim)}
.spec dd{margin:0;font-family:"IBM Plex Mono",monospace;font-size:17px;font-variant-numeric:tabular-nums}
.spec dd small{font-size:12px;color:var(--ink-dim)}

.checks{background:var(--surface);border:1px solid var(--line);border-radius:10px;padding:16px 18px}
.checks h2{margin:0 0 10px;font-size:13px;font-weight:600;letter-spacing:.06em;text-transform:uppercase;color:var(--ink-dim)}
.checks ul{margin:0;padding:0;list-style:none;display:grid;gap:7px}
.checks li{display:flex;gap:10px;align-items:baseline;font-size:14px;line-height:1.45}
.checks li::before{content:"";flex:none;width:7px;height:7px;border-radius:2px;background:var(--ok);transform:translateY(-1px)}
.checks b{font-family:"IBM Plex Mono",monospace;font-weight:500;font-variant-numeric:tabular-nums}
.note{color:var(--ink-dim);font-size:13px;line-height:1.55;margin:0;max-width:70ch}
@media (prefers-reduced-motion:reduce){*{transition:none!important}}
</style>'''

BODY = '''<div class="wrap">
  <header>
    <h1>Cinematique : marche, course, mise en joue, tir</h1>
    <span class="sub mono">30 fps &middot; 9,5 s &middot; une seule action continue</span>
  </header>

  <div class="tabs" role="tablist" aria-label="Angle de vue">__TABS__</div>

  <div class="stage">
    <canvas id="cv" width="640" height="380"></canvas>
    <div class="badge"><span id="angleName">Profil</span></div>
    <div class="loading" id="loading">Chargement des images&hellip;</div>
  </div>

  <div class="transport">
    <button class="play" id="play" aria-label="Pause">
      <svg id="ico" viewBox="0 0 16 16" aria-hidden="true"><rect x="2.5" y="2" width="4" height="12" rx="1"></rect><rect x="9.5" y="2" width="4" height="12" rx="1"></rect></svg>
    </button>
    <input class="scrub" id="scrub" type="range" min="0" max="120" value="0" aria-label="Position dans le cycle">
    <span class="count" id="count">001 / 121</span>
    <div class="speeds" role="group" aria-label="Vitesse de lecture">
      <button class="sp" data-s="0.25">0,25&times;</button>
      <button class="sp" data-s="0.5">0,5&times;</button>
      <button class="sp" data-s="1" aria-pressed="true">1&times;</button>
    </div>
  </div>

  <dl class="specs">
    <div class="spec"><dt>Duree</dt><dd>9,5 <small>s &middot; 286 images</small></dd></div>
    <div class="spec"><dt>Vitesse</dt><dd>1,0 &rarr; 3,6 &rarr; 1,0 <small>m/s</small></dd></div>
    <div class="spec"><dt>A-coup maximal</dt><dd>0,17 <small>m/s par image</small></dd></div>
    <div class="spec"><dt>Canon au relevage</dt><dd>&minus;22 &rarr; +82 <small>deg</small></dd></div>
  </dl>

  <section class="checks">
    <h2>Ce qui rend la marche souple, et les controles</h2>
    <ul>
      <li><b>Le raccord qui manquait : la prise basse.</b> On ne passe pas d&rsquo;une arme au poing en courant a une arme haute a deux mains d&rsquo;un seul coup. Le personnage ralentit, sa main gauche vient saisir l&rsquo;arme <em>sur le cote droit, canon toujours vers le bas</em> &mdash; et c&rsquo;est seulement ensuite qu&rsquo;il la releve. Techniquement, le ralentissement ne vise plus le port haut mais une <b>prise basse</b> a deux mains ; un module de relevage fait ensuite monter la crosse de la hanche a la poitrine, canon de <b>&minus;22&deg; a +82&deg;</b>, les deux mains restant solidaires.</li>
      <li>Deroule mesure : marche arme haute &rarr; acceleration &rarr; <b>course</b> (arme dans la seule main droite, poignets ecartes de 98 cm) &rarr; ralentissement, les mains se rejoignent (98 &rarr; <b>10 cm</b>) sur une arme qui reste a <b>&minus;21&deg;</b> &rarr; <b>relevage</b> &rarr; port haut &rarr; mise en joue &rarr; <b>deux coups</b>.</li>
      <li><b>Ce qui manquait au depart n&rsquo;etait pas un clip, c&rsquo;etait un moteur.</b> Entre marche et course il faut franchir un facteur <b>3,5 en vitesse</b> et <b>1,7 en cadence</b>. Fondre les deux cycles image par image donnait <b>2,3 cm d&rsquo;enfoncement, 17 cm de glissement en une image et des vitesses negatives</b> &mdash; un quaternion ne sait rien du sol. Les jambes sont donc <em>recalculees</em> par un planificateur d&rsquo;appuis qui retient ou chaque pied est reellement pose ; seul le haut du corps, sans contrainte de contact, est fondu.</li>
      <li><b>Le tir.</b> Le recul est applique a la CROSSE, pas aux bras : ceux-ci etant resolus dessus, toute la chaine encaisse d&rsquo;elle-meme, comme dans la realite ou c&rsquo;est l&rsquo;arme qui repousse l&rsquo;epaule. Canon qui se cabre de <b>17&deg;</b> en une image et retombe en treize, crosse qui recule de <b>52 mm</b>, coude qui se ferme de 141 a <b>110&deg;</b>.</li>
      <li><b>Deux bogues trouves uniquement par la mesure.</b> Les bras etaient <b>en croix</b> sur toute la premiere moitie : la fonction de pose du corps ne traite que le bas et la colonne, les bras etant resolus ailleurs. Et le raccord sortie de course sautait de <b>2,6 m/s</b> parce que je calais le decalage sur un pas de marche (3,4 cm) la ou le personnage courait a 12 cm par image.</li>
      <li>Controles sur les 286 images : a-coup maximal <b>0,17 m/s</b>, point le plus bas <b>&minus;0,43 cm</b> sur <b>6 images</b> (2 %), etirement d&rsquo;os <b>0,17 %</b>, aucun os dont l&rsquo;echelle differe de 1.</li>
      <li><b>Reste a faire</b> : resorber ces 6 images, et l&rsquo;arret complet &mdash; le personnage vise toujours en marchant, il ne s&rsquo;immobilise jamais.</li>
    </ul>
  </section>

  <p class="note">Le premier onglet est la <b>cinematique complete</b> : marche, acceleration, course, freinage, marche, mise en joue, deux coups de feu &mdash; une seule action de 294 images, sans coupure ni saut de position. Les onglets suivants montrent chaque brique isolement. Le sol porte des barres tous les metres : sans repere aucune avancee n&rsquo;est perceptible, la camera suivant le personnage. Espace = lecture/pause, fleches gauche et droite = image par image.</p>
</div>
<script>
const SEQ = __DATA__;
const LABELS = __LABELS__;
const cv = document.getElementById('cv'), ctx = cv.getContext('2d');
const scrub = document.getElementById('scrub'), count = document.getElementById('count');
const playBtn = document.getElementById('play'), ico = document.getElementById('ico');
const loading = document.getElementById('loading'), angleName = document.getElementById('angleName');
const ICO_PAUSE = '<rect x="2.5" y="2" width="4" height="12" rx="1"></rect><rect x="9.5" y="2" width="4" height="12" rx="1"></rect>';
const ICO_PLAY = '<path d="M3 2l11 6-11 6z"></path>';
const cache = {};
let angle = 'profil', frame = 0, playing = true, speed = 1, acc = 0, last = 0;
let N = SEQ[angle].length;
scrub.max = N - 1;

function load(key){
  if (cache[key]) return Promise.resolve(cache[key]);
  loading.hidden = false;
  const imgs = SEQ[key].map(function(src){ const i = new Image(); i.src = src; return i; });
  return Promise.all(imgs.map(function(i){
    return i.decode ? i.decode().catch(function(){}) : Promise.resolve();
  })).then(function(){
    for (const k in cache) { if (k !== key) delete cache[k]; }
    cache[key] = imgs; loading.hidden = true; return imgs;
  });
}
function draw(){
  const imgs = cache[angle];
  if (!imgs) return;
  const im = imgs[frame];
  if (im && im.complete) ctx.drawImage(im, 0, 0, cv.width, cv.height);
  scrub.value = frame;
  count.textContent = String(frame + 1).padStart(3, '0') + ' / ' + N;
}
function tick(t){
  if (!last) last = t;
  const dt = t - last; last = t;
  if (playing && cache[angle]){
    acc += dt * speed;
    const step = 1000 / 30;
    while (acc >= step){ acc -= step; frame = (frame + 1) % N; }
    draw();
  }
  requestAnimationFrame(tick);
}
playBtn.addEventListener('click', function(){
  playing = !playing;
  ico.innerHTML = playing ? ICO_PAUSE : ICO_PLAY;
  playBtn.setAttribute('aria-label', playing ? 'Pause' : 'Lecture');
});
scrub.addEventListener('input', function(){
  frame = +scrub.value; playing = false; ico.innerHTML = ICO_PLAY;
  playBtn.setAttribute('aria-label', 'Lecture'); draw();
});
document.querySelectorAll('.sp').forEach(function(b){
  b.addEventListener('click', function(){
    speed = parseFloat(b.dataset.s);
    document.querySelectorAll('.sp').forEach(function(o){ o.setAttribute('aria-pressed', o === b); });
  });
});
document.querySelectorAll('.tab').forEach(function(b){
  b.addEventListener('click', function(){
    document.querySelectorAll('.tab').forEach(function(o){ o.setAttribute('aria-selected', o === b); });
    angle = b.dataset.a; angleName.textContent = LABELS[angle];
    N = SEQ[angle].length; scrub.max = N - 1;
    if (frame >= N) frame = 0;
    load(angle).then(draw);
  });
});
document.addEventListener('keydown', function(e){
  if (e.key === ' ') { e.preventDefault(); playBtn.click(); }
  if (e.key === 'ArrowRight') { playing = false; ico.innerHTML = ICO_PLAY; frame = (frame + 1) % N; draw(); }
  if (e.key === 'ArrowLeft')  { playing = false; ico.innerHTML = ICO_PLAY; frame = (frame + N - 1) % N; draw(); }
});
load(angle).then(function(){ draw(); requestAnimationFrame(tick); });
</script>'''

tabs = ''.join(
    '<button class="tab" role="tab" data-a="%s" aria-selected="%s">%s</button>'
    % (k, 'true' if i == 0 else 'false', lbl) for i, (k, lbl) in enumerate(ANGLES))
labels = dict(ANGLES)

html = HEAD + '\n' + (BODY.replace('__TABS__', tabs)
                          .replace('__DATA__', json.dumps(data))
                          .replace('__LABELS__', json.dumps(labels, ensure_ascii=True)))
out = os.path.join(SP, 'marche.html')
with open(out, 'w', encoding='utf-8') as f:
    f.write(html)
print('ecrit', out, round(os.path.getsize(out) / 1e6, 2), 'Mo')
