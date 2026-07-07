#!/usr/bin/env bash
# Post-bundle patch for deck/index.html.
#
# The deck is compiled by the design tool from source/*.dc.html. The bundler
# emits a generic outer shell (<title>Bundled Page</title>, no favicon, no
# fullscreen handling) and — crucially — REPLACES the whole document element
# at boot, so anything injected into the static <head> does not survive into
# the live page. Only window/document-level listeners persist.
#
# This script therefore injects a single window-level <script> that:
#   * re-asserts the tab title + favicon after the bundler's document swap
#   * toggles fullscreen on "f"
#   * mirrors fullscreen state into the deck runtime's presenting mode
#     (__omelette_presenting postMessage), which hides the thumbnail rail,
#     suppresses the nav footer, and refits the stage to the full viewport
#
# Re-run after every re-bundle:  ./scripts/patch-deck.sh
# Idempotent: refuses to double-apply.
set -euo pipefail
DECK="$(dirname "$0")/../deck/index.html"

if grep -q 'bornhack-deck-extras' "$DECK"; then
  echo "Deck already patched — nothing to do."
  exit 0
fi

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

python3 - "$DECK" "$EXTRAS" <<'PY'
import sys
path, extras = sys.argv[1:3]
html = open(path).read()
assert html.rstrip().endswith("</html>"), "unexpected bundle: no closing </html>"
# Static head fix covers the pre-boot moment; the injected script re-asserts
# both after the bundler's document swap.
html = html.replace(
    "<title>Bundled Page</title>",
    "<title>Docker for the Curious — BornHack 2026</title>", 1)
idx = html.rindex("</body>")
html = html[:idx] + extras + "\n" + html[idx:]
open(path, "w").write(html)
print("Patched:", path)
PY
