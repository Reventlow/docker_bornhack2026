#!/usr/bin/env bash
# Post-bundle patch for deck/index.html.
#
# The deck is compiled by the design tool from source/*.dc.html, and the
# bundler emits a generic outer shell (<title>Bundled Page</title>, no
# favicon, no fullscreen handling). This script patches that outer shell
# only — the deck runtime and slide content are untouched.
#
# Re-run after every re-bundle:  ./scripts/patch-deck.sh
#
# Idempotent: refuses to double-apply.
set -euo pipefail
DECK="$(dirname "$0")/../deck/index.html"

if grep -q 'bornhack-deck-extras' "$DECK"; then
  echo "Deck already patched — nothing to do."
  exit 0
fi

TITLE='Docker for the Curious — BornHack 2026'

# Terminal-prompt favicon in the deck palette: ink background (#242424),
# paper "$" (#D0D0C8), orange block cursor (#DE6A41).
FAVICON='<link rel="icon" href="data:image/svg+xml,%3Csvg xmlns=%22http://www.w3.org/2000/svg%22 viewBox=%220 0 64 64%22%3E%3Crect width=%2264%22 height=%2264%22 rx=%2212%22 fill=%22%23242424%22/%3E%3Ctext x=%228%22 y=%2246%22 font-family=%22monospace%22 font-size=%2236%22 font-weight=%22700%22 fill=%22%23D0D0C8%22%3E$%3C/text%3E%3Crect x=%2234%22 y=%2220%22 width=%2214%22 height=%2228%22 fill=%22%23DE6A41%22/%3E%3C/svg%3E">'

read -r -d '' FULLSCREEN <<'EOF' || true
  <script id="bornhack-deck-extras">
    /* Press "f" to toggle fullscreen. Added post-bundle by scripts/patch-deck.sh. */
    addEventListener('keydown', function (e) {
      if ((e.key === 'f' || e.key === 'F') && !e.ctrlKey && !e.metaKey && !e.altKey) {
        if (document.fullscreenElement) { document.exitFullscreen(); }
        else { document.documentElement.requestFullscreen(); }
      }
    });
  </script>
EOF

python3 - "$DECK" "$TITLE" "$FAVICON" "$FULLSCREEN" <<'PY'
import sys
path, title, favicon, fullscreen = sys.argv[1:5]
html = open(path).read()
assert "<title>Bundled Page</title>" in html, "unexpected bundle: title not found"
assert html.rstrip().endswith("</html>"), "unexpected bundle: no closing </html>"
html = html.replace("<title>Bundled Page</title>",
                    f"<title>{title}</title>\n  {favicon}", 1)
idx = html.rindex("</body>")
html = html[:idx] + fullscreen + "\n" + html[idx:]
open(path, "w").write(html)
print("Patched:", path)
PY
