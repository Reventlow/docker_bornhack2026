#!/usr/bin/env bash
# Post-bundle patch for deck/index.html.
#
# The deck is compiled from source/*.dc.html (see scripts/build-deck.py).
# The bundler emits a generic outer shell (no favicon, no fullscreen
# handling) and — crucially — REPLACES the whole document element at boot,
# so anything injected into the static <head>/<body> does not survive into
# the live page. Only window/document-level listeners persist.
#
# This script therefore injects window-level <script> blocks, in this order:
#
#   deck-lang        (must run first — the others read window.__deckLang)
#     * picks the language: ?lang=da|en in the URL wins, then the choice
#       remembered in localStorage, then English
#     * when Danish: swaps the Danish slide block (script
#       __bundler/template-da, written by build-deck.py) into the bundler's
#       template BEFORE its DOMContentLoaded bootloader parses it, so the
#       runtime renders the Danish deck natively — rail, labels, print
#     * resolves ./assets/<file> paths in the template against the
#       __bundler/assets map (also from build-deck.py), so an image ships
#       once and is shared by both languages
#     * exposes window.__deckSetLang(lang): remembers the choice and reloads
#       with ?lang= set; deck-stage keeps the slide index in location.hash,
#       so the switch lands on the same slide
#
#   deck-extras
#     * re-asserts the tab title (per language) + favicon after the
#       bundler's document swap
#     * toggles fullscreen on "f"
#     * mirrors fullscreen state into the deck runtime's presenting mode
#       (__omelette_presenting postMessage), which hides the thumbnail rail,
#       suppresses the nav footer, and refits the stage to the full viewport
#
#   deck-presenter
#     * presenter bar (Slides "s" / Notes "n" / Fullscreen "f" / language
#       "l" buttons) and a speaker-notes panel, built entirely from JS so
#       they can be re-appended after the bundler's document swap (static
#       markup would be discarded). Labels and notes follow the language.
#
# Re-run after every rebuild:  ./scripts/patch-deck.sh   (build-deck.py does)
# Idempotent: each block is keyed by its id and REPLACED if already present,
# so edits to the notes below reach the deck on the next run.
set -euo pipefail
DECK="$(dirname "$0")/../deck/index.html"

read -r -d '' LANG_BLOCK <<'EOF' || true
  <script id="deck-lang">
    /* Language selection, added post-bundle by scripts/patch-deck.sh.
       Runs synchronously during parse, i.e. BEFORE the bundler's
       DOMContentLoaded bootloader reads script[type="__bundler/template"]. */
    (function () {
      var KEY = 'deck-lang';
      var LANGS = ['en', 'da'];
      var url = new URL(location.href);
      var fromUrl = url.searchParams.get('lang');
      var stored = null;
      try { stored = localStorage.getItem(KEY); } catch (e) {}
      var lang = LANGS.indexOf(fromUrl) >= 0 ? fromUrl
               : LANGS.indexOf(stored)  >= 0 ? stored : 'en';
      if (fromUrl === lang && stored !== lang) {
        try { localStorage.setItem(KEY, lang); } catch (e) {}
      }
      window.__deckLang = lang;
      window.__deckLangs = LANGS;

      /* Rewrite the bundler's template before its DOMContentLoaded
         bootloader reads it: swap in the Danish slides when Danish is
         chosen, and resolve ./assets/<file> paths against the asset map
         build-deck.py ships (one copy, shared by both languages). */
      var tplEl = document.querySelector('script[type="__bundler/template"]');
      if (tplEl) {
        var tpl = JSON.parse(tplEl.textContent);
        var before = tpl;

        var daEl = document.querySelector('script[type="__bundler/template-da"]');
        if (lang === 'da' && daEl) {
          var body = JSON.parse(daEl.textContent);
          /* Keep the bundler's own <x-import …> tag (its `from` is a manifest
             UUID); replace only the slides between it and </x-import>. A
             function replacer keeps any "$" in the markup literal. */
          tpl = tpl.replace(/(<x-import\b[^>]*>)[\s\S]*?(<\/x-import>)/,
            function (_, open, close) { return open + body + close; });
        }

        var aEl = document.querySelector('script[type="__bundler/assets"]');
        if (aEl) {
          var assets = JSON.parse(JSON.parse(aEl.textContent));
          tpl = tpl.replace(/src="\.\/assets\/([^"]+)"/g, function (m, name) {
            return assets[name] ? 'src="' + assets[name] + '"' : m;
          });
        }

        if (tpl !== before) tplEl.textContent = JSON.stringify(tpl);
      }

      window.__deckSetLang = function (next) {
        if (LANGS.indexOf(next) < 0 || next === window.__deckLang) return;
        try { localStorage.setItem(KEY, next); } catch (e) {}
        var u = new URL(location.href);
        u.searchParams.set('lang', next); /* explicit, so it beats a stale ?lang= */
        /* deck-stage mirrors the current slide into #N — it survives the reload. */
        location.replace(u.href);
      };
    })();
  </script>
EOF

read -r -d '' EXTRAS <<'EOF' || true
  <script id="deck-extras">
    /* Added post-bundle by scripts/patch-deck.sh — see that file for why.
       Everything here hangs off window/document, which survive the
       bundler's documentElement swap at boot. */
    (function () {
      var TITLE = window.__deckLang === 'da' ? 'Docker for de Nysgerrige'
                                             : 'Docker for the Curious';
      /* Terminal-prompt favicon in the deck palette: ink background
         (#242424), paper "$" (#D0D0C8), orange block cursor (#DE6A41). */
      var FAVICON = 'data:image/svg+xml,' + encodeURIComponent(
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64">' +
        '<rect width="64" height="64" rx="12" fill="#242424"/>' +
        '<text x="8" y="46" font-family="monospace" font-size="36"' +
        ' font-weight="700" fill="#D0D0C8">$</text>' +
        '<rect x="34" y="20" width="14" height="28" fill="#DE6A41"/></svg>');

      function ensureHead() {
        if (document.title !== TITLE) document.title = TITLE;
        if (!document.querySelector('link[rel="icon"]')) {
          var link = document.createElement('link');
          link.rel = 'icon';
          link.href = FAVICON;
          (document.head || document.documentElement).appendChild(link);
        }
      }
      ensureHead();
      /* The bundler replaces <html> during boot; observing the Document
         node catches that swap so we can re-apply title + favicon. */
      new MutationObserver(ensureHead).observe(document, { childList: true });
      addEventListener('load', ensureHead);

      /* Fullscreen <-> presenting mode. The deck-stage runtime listens for
         __omelette_presenting on window and hides the rail/footer itself. */
      function syncPresenting() {
        window.postMessage(
          { __omelette_presenting: !!document.fullscreenElement }, '*');
      }
      document.addEventListener('fullscreenchange', syncPresenting);

      addEventListener('keydown', function (e) {
        if (e.key !== 'f' && e.key !== 'F') return;
        if (e.ctrlKey || e.metaKey || e.altKey) return;
        /* Don't steal "f" while typing in a slide's form field. */
        var t = e.composedPath ? e.composedPath()[0] : e.target;
        if (t && (t.tagName === 'INPUT' || t.tagName === 'TEXTAREA'
                  || t.isContentEditable)) return;
        if (document.fullscreenElement) document.exitFullscreen();
        else document.documentElement.requestFullscreen();
      });
    })();
  </script>
EOF

read -r -d '' PRESENTER <<'EOF' || true
  <script id="deck-presenter">
    /* Presenter bar + speaker-notes panel, added post-bundle by
       scripts/patch-deck.sh. The bar/panel are BUILT FROM JS and re-appended
       via a MutationObserver because the bundler discards the static <body>
       at boot. Palette: ink #242424, paper #D0D0C8, orange #DE6A41. */
    (function () {
      var lang = window.__deckLang || 'en';
      var current = 0;
      var notesOpen = false;

      function stage()  { return document.querySelector('deck-stage'); }
      function slides() { var s = stage(); return s ? s.querySelectorAll('section') : []; }

      /* UI strings per language. The language button shows the language
         you would switch TO. */
      var UI = {
        en: { rail: 'Slides', notes: 'Notes', full: 'Fullscreen', lang: 'DA',
              head: 'Speaker notes', none: 'No notes for this slide.' },
        da: { rail: 'Slides', notes: 'Noter', full: 'Fuld skærm', lang: 'EN',
              head: 'Talenoter', none: 'Ingen noter til dette slide.' }
      }[lang];
      var OTHER = lang === 'da' ? 'en' : 'da';

      /* Speaker notes, keyed by each slide's data-label (identical in both
         language sources). They live here rather than as data-speaker-notes
         attributes because the slide markup sits inside the compiled bundle;
         the patch script is the layer we own. */
      var NOTES = {
        en: {
          "Title": "Welcome people as they settle, laptops out from the start. Zero prior experience expected, that is the audience. Mention that the very first task is installing Docker, so get on the wifi now.",
          "About": "Thirty seconds, not three minutes — they came for Docker, not for me. Day job is compliance at FynBus, which is why containers matter to me as something auditable and reproducible, not just convenient. Open source and the homelab are where the hands-on part comes from; everything in this deck is something I actually run. Then straight on to the format.",
          "Format": "Explain the shape: half explaining, half typing, eight tasks that each build on the last. Amber TASK badge means hands on keyboard. Finished early? Help the neighbors, teaching it is learning it twice. No laptop means pair up, one keyboard is plenty.",
          "Why": "Open with the works-on-my-machine story, everyone nods. Land the idea: an app is never just code, it drags along a runtime, libraries, config and machine quirks. A container packs the app together with everything it needs into one sealed unit.",
          "Container": "Three properties, one line each: isolated in its own filesystem, network and process list; lightweight because it shares your kernel and starts in milliseconds; portable because the same image runs identically anywhere. Land the demystifier: not magic, just a normal process in a sealed little world.",
          "VMs": "Walk both stacks side by side. VMs each carry a whole guest OS; containers share the one kernel you already run, which is why they are so light. Be fair to VMs: a different OS or kernel is still VM territory.",
          "Image vs Container": "The distinction the whole workshop leans on: image is the read-only blueprint, container is a disposable running copy with a thin writable layer. Plant the seed for task 3: the image never changes while containers run. One image, many containers.",
          "Pipeline": "Trace the loop on the slide: Dockerfile, build, push, Hub, pull, run. On naming: plain nginx is official, name-slash-image is somebody's remix, check pulls and last-updated before trusting one. Today we start on the right with pull and run, and end on the left building and pushing our own.",
          "Task 0 Install": "The messy task, budget 10 to 15 minutes and roam the room. Say it loudly and twice: after usermod you must log out and back in, or docker will deny you. If a distro misbehaves, the get.docker.com script is the fastest unblock. Checkpoint: everyone gets hello-world or a version string before moving on.",
          "Task 1 Run": "The magic moment: one command pulls a page from the internet and serves it locally. Decode every flag on the slide, -d detached, -p host colon container, --name so we can talk to it. If 8080 is taken, 8090:80 works fine, only the left side changes.",
          "Core Loop": "Type-along, run each command and watch what changes. ps versus ps -a catches the stopped ones, logs shows everything it printed (refresh the page and look again), rm -f deletes even a running one. These six commands are 90 percent of daily Docker.",
          "Task 2 Inside": "docker exec -it camp bash, and the changed prompt means you are inside the container's own world. Let them edit the page with nano, refresh, and see it change. Plant clearly: remember this edit, the next task destroys it on purpose.",
          "Task 3 Rerun": "The payoff of image versus container: delete and rerun, and the edit is gone because it lived in the dead container's writable layer, and the fresh container is a pristine copy of the untouched image. Contrast with stop plus start, which keeps the edit. Watch for the pennies dropping, this is the aha of the day.",
          "Ephemeral": "Name the mental model they just felt: immutable images, disposable containers, cattle not pets, and anything worth keeping lives outside and gets mounted in. Transition: that outside part is called a volume, next task.",
          "Task 4 Compose": "Motivate it: that run command was getting long, compose just writes it down in a file that lives in git. YAML indentation is the classic stumble, two spaces, roam and unblock. up -d starts everything, down stops and removes it.",
          "Task 5 Volume": "The colon rule, host path on the left, container path on the right, same as ports. The proof moment: down and up again, and the page survives because it lives on the host now. This is how every real deployment keeps its data.",
          "Two Services": "Demo only, do NOT have the room pull mysql on the shared wifi, that is why the slide says watch. Show wordpress finding its database simply by the service name db. This is where compose stops being convenience and starts being the point.",
          "Task 6 Build": "Their first image: FROM nginx:alpine plus one COPY line, that is a complete Dockerfile. Tag it username/iwasat:1.0. Say it twice: the trailing dot on docker build is the build context, forgetting it is the number one error.",
          "Task 7 Push": "The payoff of the whole day: login, push, then run a neighbor's image straight from the Hub. Get usernames shouted across the room and pages running on other people's laptops, let this peak run a few minutes. One warning: the image is public, never bake secrets into one.",
          "Recap": "Sweep the vocabulary list and point out they now own every word on it, two hours ago none of it meant anything. Point at docs.docker.com, hub.docker.com and play-with-docker.com for the days after. Contact details and the PGP fingerprint are on screen, so leave this slide up while people pack down. Thank them and stay around for questions."
        },
        da: {
          "Title": "Byd folk velkommen, mens de sætter sig — laptops frem fra starten. Ingen forkundskaber forventes, det er målgruppen. Nævn, at den allerførste opgave er at installere Docker, så få fat i wifi nu.",
          "About": "Tredive sekunder, ikke tre minutter — de kom for Dockers skyld, ikke for min. Til daglig er det compliance hos FynBus, og derfor betyder containere noget for mig som noget, der kan revideres og gentages, ikke bare noget bekvemt. Open source og homelabbet er der, det praktiske kommer fra; alt i dette oplæg er noget, jeg selv kører. Videre til formen.",
          "Format": "Forklar formen: halvt forklaring, halvt tastatur, otte opgaver, der hver bygger på den forrige. Orange OPGAVE-mærke betyder hænderne på tastaturet. Færdig før tid? Hjælp naboerne — at lære fra sig er at lære det to gange. Ingen laptop betyder par, ét tastatur er rigeligt.",
          "Why": "Åbn med virker-på-min-maskine-historien, alle nikker. Land pointen: en app er aldrig bare kode, den slæber runtime, biblioteker, konfiguration og maskinens særheder med sig. En container pakker appen sammen med alt, den har brug for, i én forseglet enhed.",
          "Container": "Tre egenskaber, én linje hver: isoleret i sit eget filsystem, netværk og procesliste; letvægt fordi den deler din kerne og starter på millisekunder; flytbar fordi det samme image kører identisk overalt. Land afmystificeringen: ikke magi, bare en almindelig proces i en lille forseglet verden.",
          "VMs": "Gå begge stakke igennem side om side. VM'er medbringer hver et helt gæste-OS; containere deler den ene kerne, du allerede kører — derfor er de så lette. Vær fair over for VM'er: et andet OS eller en anden kerne er stadig VM-land.",
          "Image vs Container": "Den skelnen, hele workshoppen hviler på: imaget er den skrivebeskyttede tegning, containeren er en kørende engangskopi med et tyndt skrivbart lag. Så frøet til opgave 3: imaget ændrer sig aldrig, mens containere kører. Ét image, mange containere.",
          "Pipeline": "Følg løkken på slidet: Dockerfile, build, push, Hub, pull, run. Om navngivning: rent nginx er officielt, navn-skråstreg-image er nogens remix — tjek pulls og seneste opdatering, før du stoler på et. I dag starter vi til højre med pull og run og slutter til venstre med at bygge og pushe vores eget.",
          "Task 0 Install": "Den rodede opgave — afsæt 10 til 15 minutter og gå rundt i lokalet. Sig det højt og to gange: efter usermod skal man logge ud og ind igen, ellers afviser docker en. Driller en distro, er get.docker.com-scriptet den hurtigste vej videre. Checkpoint: alle får hello-world eller et versionsnummer, før vi går videre.",
          "Task 1 Run": "Det magiske øjeblik: én kommando henter en side fra internettet og serverer den lokalt. Afkod hvert flag på slidet: -d detached, -p vært kolon container, --name så vi kan tale om den. Er 8080 optaget, virker 8090:80 fint — kun venstre side ændrer sig.",
          "Core Loop": "Tast med — kør hver kommando og se, hvad der ændrer sig. ps mod ps -a fanger de stoppede, logs viser alt, den har skrevet (genindlæs siden og kig igen), rm -f sletter selv en kørende. De seks kommandoer er 90 procent af hverdags-Docker.",
          "Task 2 Inside": "docker exec -it camp bash — den ændrede prompt betyder, at du er inde i containerens egen verden. Lad dem rette siden med nano, genindlæse og se den ændre sig. Plant det tydeligt: husk denne rettelse, næste opgave ødelægger den med vilje.",
          "Task 3 Rerun": "Belønningen for image mod container: slet og kør igen, og rettelsen er væk, fordi den boede i den døde containers skrivbare lag, og den nye container er en fabriksny kopi af det urørte image. Sæt det op mod stop plus start, som bevarer rettelsen. Hold øje med tiøren, der falder — det er dagens aha.",
          "Ephemeral": "Sæt navn på den mentale model, de lige har mærket: uforanderlige images, engangscontainere, kvæg ikke kæledyr, og alt, der er værd at gemme, bor udenfor og monteres ind. Overgang: det udenfor hedder et volume — næste opgave.",
          "Task 4 Compose": "Motivér det: den run-kommando var ved at blive lang, compose skriver den bare ned i en fil, der bor i git. YAML-indrykning er den klassiske fælde — to mellemrum, gå rundt og hjælp. up -d starter det hele, down stopper og fjerner det.",
          "Task 5 Volume": "Kolon-reglen: værtens sti til venstre, containerens sti til højre, præcis som med porte. Bevis-øjeblikket: down og up igen, og siden overlever, fordi den nu bor på værten. Sådan holder enhver rigtig deployment på sine data.",
          "Two Services": "Kun demo — lad IKKE lokalet hente mysql på det delte wifi, derfor står der kig med på slidet. Vis, at wordpress finder sin database bare ved service-navnet db. Her holder compose op med at være bekvemmelighed og bliver selve pointen.",
          "Task 6 Build": "Deres første image: FROM nginx:alpine plus én COPY-linje — det er en komplet Dockerfile. Tag det brugernavn/iwasat:1.0. Sig det to gange: punktummet til sidst i docker build er build-konteksten, og at glemme det er fejl nummer ét.",
          "Task 7 Push": "Hele dagens belønning: login, push, og kør så en nabos image direkte fra Hub. Få brugernavne råbt på tværs af lokalet og sider kørende på andres laptops — lad toppen vare et par minutter. Én advarsel: imaget er offentligt, bag aldrig hemmeligheder ind i et.",
          "Recap": "Gå ordlisten igennem og påpeg, at de nu ejer hvert ord på den — for to timer siden betød ingen af dem noget. Peg på docs.docker.com, hub.docker.com og play-with-docker.com til dagene efter. Kontaktoplysninger og PGP-fingeraftryk står på skærmen, så lad slidet blive stående, mens folk pakker sammen. Sig tak og bliv hængende til spørgsmål."
        }
      }[lang];

      var BTN = 'cursor:pointer;font:700 14px monospace;color:#D0D0C8;' +
                'background:rgba(36,36,36,0.88);border:1px solid rgba(208,208,200,0.3);' +
                'border-radius:999px;padding:8px 16px';

      function build() {
        var bar = document.createElement('div');
        bar.id = 'presenter-bar';
        bar.style.cssText = 'position:fixed;left:16px;bottom:14px;z-index:2147483000;display:flex;gap:8px;font-family:monospace';
        [['rail', UI.rail, 'S'], ['notes', UI.notes, 'N'], ['full', UI.full, 'F'], ['lang', UI.lang, 'L']]
          .forEach(function (b) {
            var el = document.createElement('button');
            el.setAttribute('data-toggle', b[0]);
            el.style.cssText = BTN;
            el.innerHTML = b[1] + ' <span style="opacity:.6">' + b[2] + '</span>';
            bar.appendChild(el);
          });
        bar.addEventListener('click', function (e) {
          var btn = e.target.closest('button'); if (!btn) return;
          var t = btn.getAttribute('data-toggle');
          if (t === 'full') toggleFull();
          else if (t === 'rail') toggleRail();
          else if (t === 'notes') toggleNotes();
          else if (t === 'lang') toggleLang();
        });

        var panel = document.createElement('aside');
        panel.id = 'notes-panel';
        panel.hidden = !notesOpen;
        panel.style.cssText = 'position:fixed;left:0;right:0;bottom:0;z-index:2147482999;max-height:32vh;overflow:auto;box-sizing:border-box;padding:26px 34px 78px;background:rgba(28,28,28,0.95);border-top:3px solid #DE6A41;color:#D0D0C8;font-family:sans-serif';
        panel.innerHTML =
          '<p id="notes-head" style="margin:0 0 10px;font-family:monospace;font-size:13px;font-weight:700;letter-spacing:0.14em;text-transform:uppercase;color:#DE6A41"></p>' +
          '<p id="notes-body" style="margin:0;font-size:20px;line-height:1.55;color:rgba(208,208,200,0.92);max-width:1100px">…</p>';

        document.body.appendChild(bar);
        document.body.appendChild(panel);
      }

      function ensureBar() {
        if (!document.body) return;
        if (!document.getElementById('presenter-bar')) build();
      }

      function renderNotes() {
        var headEl = document.getElementById('notes-head');
        var bodyEl = document.getElementById('notes-body');
        if (!headEl) return;
        var list = slides();
        var s = list[current];
        var label = s ? (s.getAttribute('data-label') || '') : '';
        var note  = s ? (s.getAttribute('data-speaker-notes') || NOTES[label] || '') : '';
        headEl.textContent = UI.head + ' · ' + (current + 1) + ' / ' + list.length +
                             (label ? ' · ' + label : '');
        bodyEl.textContent = note.trim() || UI.none;
      }

      function toggleFull() {
        if (document.fullscreenElement) document.exitFullscreen();
        else if (document.documentElement.requestFullscreen) document.documentElement.requestFullscreen();
      }
      function toggleRail()  { var s = stage(); if (s) s.toggleAttribute('no-rail'); }
      function toggleNotes() {
        notesOpen = !notesOpen;
        var panel = document.getElementById('notes-panel');
        if (panel) panel.hidden = !notesOpen;
        if (notesOpen) renderNotes();
      }
      function toggleLang() {
        if (window.__deckSetLang) window.__deckSetLang(OTHER);
      }

      /* deck-stage posts {slideIndexChanged:N} to this window on every nav. */
      window.addEventListener('message', function (e) {
        var d = e.data;
        if (d && typeof d.slideIndexChanged === 'number') {
          current = d.slideIndexChanged;
          if (notesOpen) renderNotes();
        }
      });

      /* "f" is bound by the deck-extras block. */
      addEventListener('keydown', function (e) {
        if (e.ctrlKey || e.metaKey || e.altKey) return;
        var t = e.composedPath ? e.composedPath()[0] : e.target;
        if (t && (t.tagName === 'INPUT' || t.tagName === 'TEXTAREA'
                  || t.isContentEditable)) return;
        var k = e.key.toLowerCase();
        if (k === 's') { e.preventDefault(); toggleRail(); }
        else if (k === 'n') { e.preventDefault(); toggleNotes(); }
        else if (k === 'l') { e.preventDefault(); toggleLang(); }
      });

      ensureBar();
      /* Re-append after the bundler's documentElement swap at boot. */
      new MutationObserver(ensureBar).observe(document, { childList: true });
      addEventListener('load', ensureBar);
    })();
  </script>
EOF

python3 - "$DECK" "$LANG_BLOCK" "$EXTRAS" "$PRESENTER" <<'PY'
import re, sys
path, lang_block, extras, presenter = sys.argv[1:5]
html = open(path).read()
assert html.rstrip().endswith("</html>"), "unexpected bundle: no closing </html>"

# Strip every block we own (current ids and the pre-rename bornhack-* ids),
# then append them fresh in dependency order just before </body>.
OWNED = ("deck-lang", "deck-extras", "deck-presenter",
         "bornhack-deck-extras", "bornhack-deck-presenter")
for guard in OWNED:
    html, n = re.subn(r'\n?[ \t]*<script id="%s">.*?</script>\n?' % re.escape(guard),
                      "\n", html, count=1, flags=re.S)
idx = html.rindex("</body>")
blocks = "\n".join((lang_block, extras, presenter))
html = html[:idx].rstrip("\n") + "\n" + blocks + "\n" + html[idx:]
open(path, "w").write(html)
print("Patched:", path, "(deck-lang, deck-extras, deck-presenter)")
PY
