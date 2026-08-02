#!/usr/bin/env bash
# Post-bundle patch for deck/index.html.
#
# The deck is compiled by the design tool from source/*.dc.html. The bundler
# emits a generic outer shell (<title>Bundled Page</title>, no favicon, no
# fullscreen handling) and — crucially — REPLACES the whole document element
# at boot, so anything injected into the static <head> does not survive into
# the live page. Only window/document-level listeners persist.
#
# This script therefore injects window-level <script> blocks:
#
#   bornhack-deck-extras
#     * re-asserts the tab title + favicon after the bundler's document swap
#     * toggles fullscreen on "f"
#     * mirrors fullscreen state into the deck runtime's presenting mode
#       (__omelette_presenting postMessage), which hides the thumbnail rail,
#       suppresses the nav footer, and refits the stage to the full viewport
#
#   bornhack-deck-presenter
#     * presenter bar (Slides "s" / Notes "n" / Fullscreen "f" buttons) and a
#       speaker-notes panel, built entirely from JS so they can be re-appended
#       after the bundler's document swap (static markup would be discarded)
#
# Re-run after every re-bundle:  ./scripts/patch-deck.sh
# Idempotent: each block is guarded by its id and only injected if missing.
set -euo pipefail
DECK="$(dirname "$0")/../deck/index.html"

read -r -d '' EXTRAS <<'EOF' || true
  <script id="bornhack-deck-extras">
    /* Added post-bundle by scripts/patch-deck.sh — see that file for why.
       Everything here hangs off window/document, which survive the
       bundler's documentElement swap at boot. */
    (function () {
      var TITLE = 'Docker for the Curious — BornHack 2026';
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
  <script id="bornhack-deck-presenter">
    /* Presenter bar + speaker-notes panel, added post-bundle by
       scripts/patch-deck.sh. The bar/panel are BUILT FROM JS and re-appended
       via a MutationObserver because the bundler discards the static <body>
       at boot. Palette: ink #242424, paper #D0D0C8, orange #DE6A41. */
    (function () {
      var current = 0;
      var notesOpen = false;

      function stage()  { return document.querySelector('deck-stage'); }
      function slides() { var s = stage(); return s ? s.querySelectorAll('section') : []; }

      /* Speaker notes, keyed by each slide's data-label. They live here
         rather than as data-speaker-notes attributes because the slide
         markup sits inside the design tool's compiled bundle, which we
         cannot hand-edit; the patch script is the layer we own. */
      var NOTES = {
        "Title": "Welcome people as they settle, laptops out from the start. Zero prior experience expected, that is the audience. Mention that the very first task is installing Docker, so get on the camp wifi now.",
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
        "Two Services": "Demo only, do NOT have the room pull mysql on camp wifi, that is why the slide says watch. Show wordpress finding its database simply by the service name db. This is where compose stops being convenience and starts being the point.",
        "Task 6 Build": "Their first image: FROM nginx:alpine plus one COPY line, that is a complete Dockerfile. Tag it username/iwasat:1.0. Say it twice: the trailing dot on docker build is the build context, forgetting it is the number one error.",
        "Task 7 Push": "The payoff of the whole day: login, push, then run a neighbor's image straight from the Hub. Get usernames shouted across the room and pages running on other people's laptops, let this peak run a few minutes. One warning: the image is public, never bake secrets into one.",
        "Recap": "Sweep the vocabulary list and point out they now own every word on it, two hours ago none of it meant anything. Point at docs.docker.com, hub.docker.com and play-with-docker.com for the days after camp. Thank them and stay around for questions.",
      };

      var BTN = 'cursor:pointer;font:700 14px monospace;color:#D0D0C8;' +
                'background:rgba(36,36,36,0.88);border:1px solid rgba(208,208,200,0.3);' +
                'border-radius:999px;padding:8px 16px';

      function build() {
        var bar = document.createElement('div');
        bar.id = 'presenter-bar';
        bar.style.cssText = 'position:fixed;left:16px;bottom:14px;z-index:2147483000;display:flex;gap:8px;font-family:monospace';
        [['rail', 'Slides', 'S'], ['notes', 'Notes', 'N'], ['full', 'Fullscreen', 'F']]
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
        });

        var panel = document.createElement('aside');
        panel.id = 'notes-panel';
        panel.hidden = !notesOpen;
        panel.style.cssText = 'position:fixed;left:0;right:0;bottom:0;z-index:2147482999;max-height:32vh;overflow:auto;box-sizing:border-box;padding:26px 34px 78px;background:rgba(28,28,28,0.95);border-top:3px solid #DE6A41;color:#D0D0C8;font-family:sans-serif';
        panel.innerHTML =
          '<p id="notes-head" style="margin:0 0 10px;font-family:monospace;font-size:13px;font-weight:700;letter-spacing:0.14em;text-transform:uppercase;color:#DE6A41">Speaker notes</p>' +
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
        headEl.textContent = 'Speaker notes · ' + (current + 1) + ' / ' + list.length +
                             (label ? ' · ' + label : '');
        bodyEl.textContent = note.trim() || 'No notes for this slide.';
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

      /* deck-stage posts {slideIndexChanged:N} to this window on every nav. */
      window.addEventListener('message', function (e) {
        var d = e.data;
        if (d && typeof d.slideIndexChanged === 'number') {
          current = d.slideIndexChanged;
          if (notesOpen) renderNotes();
        }
      });

      /* "f" is bound by the bornhack-deck-extras block. */
      addEventListener('keydown', function (e) {
        if (e.ctrlKey || e.metaKey || e.altKey) return;
        var t = e.composedPath ? e.composedPath()[0] : e.target;
        if (t && (t.tagName === 'INPUT' || t.tagName === 'TEXTAREA'
                  || t.isContentEditable)) return;
        var k = e.key.toLowerCase();
        if (k === 's') { e.preventDefault(); toggleRail(); }
        else if (k === 'n') { e.preventDefault(); toggleNotes(); }
      });

      ensureBar();
      /* Re-append after the bundler's documentElement swap at boot. */
      new MutationObserver(ensureBar).observe(document, { childList: true });
      addEventListener('load', ensureBar);
    })();
  </script>
EOF

python3 - "$DECK" "$EXTRAS" "$PRESENTER" <<'PY'
import sys
path, extras, presenter = sys.argv[1:4]
html = open(path).read()
assert html.rstrip().endswith("</html>"), "unexpected bundle: no closing </html>"
# Static head fix covers the pre-boot moment; the injected script re-asserts
# both after the bundler's document swap.
html = html.replace(
    "<title>Bundled Page</title>",
    "<title>Docker for the Curious — BornHack 2026</title>", 1)
added = []
for guard, block in (("bornhack-deck-extras", extras),
                     ("bornhack-deck-presenter", presenter)):
    if guard in html:
        continue
    idx = html.rindex("</body>")
    html = html[:idx] + block + "\n" + html[idx:]
    added.append(guard)
if added:
    open(path, "w").write(html)
    print("Patched:", path, "(+ " + ", ".join(added) + ")")
else:
    print("Deck already fully patched — nothing to do.")
PY
