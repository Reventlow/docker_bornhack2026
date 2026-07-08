#!/usr/bin/env python3
"""Retheme the deck to the Milky Matcha palette of the NIS2 talk deck.

Maps the original grey-beige palette to the cream/matcha tokens used by
github.com/Reventlow/nis2_bornhack_2026 (scripts/make-light.py there is
the reference), and adds the same 96px matcha grid to every slide, so
both BornHack 2026 decks share one look.

Applied to BOTH files, since colors appear as literals in each:
  - source/Docker for the Curious.dc.html  (editable source)
  - deck/index.html                        (compiled bundle; the slide
    markup is embedded in it verbatim, so the same string replacements
    keep it in sync without a re-bundle)

Idempotent: replacements are old-palette -> new-palette only.
"""

from pathlib import Path

FILES = [
    Path("source/Docker for the Curious.dc.html"),
    Path("deck/index.html"),
]

# Old grey-beige token -> Milky Matcha token.
COLOR_MAP = {
    # backgrounds
    "#D0D0C8": "#f4f1e8",   # --bg: slide background -> cream
    "#BFBFB5": "#f4f1e8",   # page surround behind the deck
    "#D9D9D2": "#faf8f0",   # --panel: window/card, a touch lighter than bg
    "#C5C5BA": "#eae6d9",   # --panel2: inset/code areas, darker than bg
    "#A9A99B": "#c5c2b0",   # --line: borders
    "#A8A89A": "#b9baae",   # terminal window-chrome dots
    # ink
    "#242424": "#3a4433",   # --ink
    "#383835": "#46503f",   # --soft
    "#6B7360": "#818678",   # --dim
    "#8C8C7D": "#979b8e",   # --faint
    # greens
    "#51573B": "#6b8054",   # --green -> dim matcha
    "#5E6349": "#7a9461",   # lighter olive text -> bright matcha
    # amber/orange accent -> golden milk tea (as in the NIS2 light theme)
    "#DE6A41": "#a8763a",
    "#F05A0F": "#8a5f2e",   # link hover
    # translucent tints
    "rgba(81,87,59,0.07)": "rgba(107,128,84,0.12)",
    "rgba(81,87,59,0.10)": "rgba(107,128,84,0.16)",
    "rgba(222,106,65,0.08)": "rgba(168,118,58,0.12)",
}

# Same faint matcha grid the NIS2 deck draws on every slide.
GRID = (
    "background-color: var(--bg); "
    "background-image: linear-gradient(rgba(122,148,97,0.14) 1px, transparent 1px), "
    "linear-gradient(90deg, rgba(122,148,97,0.14) 1px, transparent 1px); "
    "background-size: 96px 96px;"
)


def main() -> None:
    for path in FILES:
        html = path.read_text()
        for old, new in COLOR_MAP.items():
            html = html.replace(old, new)
        html = html.replace("background: var(--bg);", GRID)
        path.write_text(html)
        print(f"{path} written ({len(html)} bytes)")


if __name__ == "__main__":
    main()
