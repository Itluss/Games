# -*- coding: utf-8 -*-
import base64, os, json

SP = os.path.dirname(os.path.abspath(__file__))
ANGLES = [('profil', 'Profil'), ('troisquarts', 'Trois quarts'), ('face', 'Face'),
          ('dos', 'Dos'), ('misenjoue', 'Mise en joue')]

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
    <h1>Marche tactique et mise en joue</h1>
    <span class="sub mono">30 fps &middot; camera d&rsquo;accompagnement &middot; poignets redresses</span>
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
    <div class="spec"><dt>Poignets en visee</dt><dd>16 <small>deg (43 avant)</small></dd></div>
    <div class="spec"><dt>Pivot en fin d&rsquo;appui</dt><dd>0,0 <small>mm de derive</small></dd></div>
    <div class="spec"><dt>Genou en poussee</dt><dd>0 <small>inversion</small></dd></div>
    <div class="spec"><dt>Coudes en visee</dt><dd>162 <small>deg, sous l&rsquo;epaule</small></dd></div>
  </dl>

  <section class="checks">
    <h2>Ce qui rend la marche souple, et les controles</h2>
    <ul>
      <li><b>Les poignets etaient casses en visee : 43&deg; a droite, 40&deg; a gauche.</b> Trois causes empilees, trouvees en mesurant l&rsquo;angle avant-bras / main image par image plutot qu&rsquo;en deplacant les coudes au jugé.</li>
      <li><b>Le ressort de l&rsquo;arme courait derriere une cible qui avance.</b> Il tournait sur le personnage en deplacement, a 1 m/s : il accumulait donc un retard permanent de <b>8 cm</b> au lieu de ne repondre qu&rsquo;aux accelerations. L&rsquo;arme etait plaquee contre la poitrine et la phase de port ne coincidait meme plus avec l&rsquo;animation de marche. Elle y correspond aujourd&rsquo;hui a <b>0,0 mm</b>.</li>
      <li><b>L&rsquo;arme visait 8 cm au-dessus de la ligne d&rsquo;epaule.</b> L&rsquo;avant-bras devait monter vers les mains alors que la main, elle, pointe vers l&rsquo;avant-bas &mdash; une crosse de pistolet est inclinee de 16&deg;. Les deux directions se contrariaient et le poignet encaissait tout l&rsquo;ecart. Hauteur ramenee a <b>1,43 m</b>, hauteur de poitrine de la cible.</li>
      <li><b>La direction du coude est desormais calculee, pas choisie.</b> Sur le cercle de rotation du coude on retient la position la plus BASSE qui garde le poignet sous 16&deg; <em>et</em> l&rsquo;humerus a plus de 2 cm du torse. Sans cette seconde contrainte l&rsquo;optimum du poignet rentre le coude jusqu&rsquo;au sternum &mdash; il traversait meme le buste au milieu du depliement.</li>
      <li>Poignets en visee : <b>14 a 18&deg;</b> des deux cotes, contre 39 a 50&deg;. Coudes <b>2 a 5 cm sous l&rsquo;epaule</b>, flechis a <b>162&deg;</b>, jamais verrouilles.</li>
      <li><b>La jambe arriere tremblait avant de decoller.</b> La distance hanche&ndash;cheville se rallongeait de <b>6,3 mm</b> sur la derniere image d&rsquo;appui : la cheville ne faisait que monter, alors que le pied roule sur le coussinet et qu&rsquo;elle doit decrire un arc autour de lui &mdash; monter <em>et</em> avancer. Elle avance maintenant de <b>4,0 cm</b>, autour d&rsquo;un point de contact qui ne bouge pas d&rsquo;un <b>dixieme de millimetre</b>.</li>
      <li>La poussee accelere desormais jusqu&rsquo;au decollement au lieu de s&rsquo;essouffler : le genou passe de <b>5&deg; a 59&deg;</b> sans une seule inversion. La seule inflexion restante, 2,6&deg; a l&rsquo;attaque du talon, est la flexion d&rsquo;amortissement.</li>
      <li>Proportions d&rsquo;origine : etirement d&rsquo;os maximal <b>0,08 %</b>, <b>aucun</b> os dont l&rsquo;echelle differe de 1. Degagement bras / torse <b>+1,7 cm</b>, plus aucune valeur negative.</li>
    </ul>
  </section>

  <p class="note">Decor volontairement vide : fond et sol gris uni, aucun element de scene, pour ne juger que les postures. La camera avance a la vitesse du personnage ; le sol etant uni, la reprise de boucle est invisible. Les actions exportees pour le moteur sont, elles, sur place et bouclables. En <b>0,25&times;</b> : sur l&rsquo;onglet Profil, suivez la jambe arriere quand le talon se leve ; sur l&rsquo;onglet Mise en joue, regardez l&rsquo;alignement avant-bras / arme une fois les bras deployes. Espace = lecture/pause, fleches gauche et droite = image par image.</p>
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
