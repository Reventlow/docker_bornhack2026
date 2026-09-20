#!/usr/bin/env python3
"""Rebuild deck/index.html from source/ without the design tool.

How the bundle works: the design tool's bundler stores the ENTIRE source
document (fonts inlined, asset URLs swapped for UUIDs) as one JSON string in
    <script type="__bundler/template">…</script>
and a bootloader parses it at DOMContentLoaded and replaces the live document
with it. That means we can re-bundle ourselves: decode the string, splice in
the current slide markup from source/, encode it again. The fonts, the
deck-stage runtime and the asset manifest are left exactly as the bundler
emitted them.

What this script syncs into the bundle:
  * the <x-import> body (all <section> slides) from the English source
  * the helmet <style> block (palette / type scale) from the English source
  * the Danish slides, embedded as a second script
        <script type="__bundler/template-da">…</script>
    holding just the <x-import> body. The `deck-lang` block injected by
    scripts/patch-deck.sh swaps it into the template before the bootloader
    runs when the viewer has chosen Danish, so the runtime renders the
    Danish deck natively (rail thumbnails, labels, print — everything).

Both sources must have the same slides in the same order: the build refuses
to continue if the data-label sequence differs, because the speaker notes
in patch-deck.sh are keyed by data-label and the language toggle keeps the
slide index across the switch.

Usage:  ./scripts/build-deck.py          (then patch-deck.sh runs automatically)
"""
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DECK = ROOT / "deck" / "index.html"
SRC_EN = ROOT / "source" / "Docker for the Curious.dc.html"
SRC_DA = ROOT / "source" / "Docker for the Curious.da.dc.html"
TITLE = "Docker for the Curious"

TEMPLATE_RE = re.compile(r'(<script type="__bundler/template">)(.*?)(</script>)', re.S)
TEMPLATE_DA_RE = re.compile(r'\n?<script type="__bundler/template-da">.*?</script>', re.S)
XIMPORT_RE = re.compile(r'(<x-import\b[^>]*>)(.*?)(</x-import>)', re.S)
STYLE_RE = re.compile(r'<style>\s*html, body \{.*?</style>', re.S)
LABEL_RE = re.compile(r'<section\b[^>]*\bdata-label="([^"]*)"')


def ximport_body(html: str, name: str) -> str:
    m = XIMPORT_RE.search(html)
    if not m:
        sys.exit(f"{name}: no <x-import>…</x-import> block found")
    return m.group(2)


def to_script_json(value: str) -> str:
    """JSON-encode for an inline <script>: '</' must not appear literally or
    the HTML parser would end the script element early. '\\/' is valid JSON."""
    return json.dumps(value, ensure_ascii=False).replace("</", "<\\/")


def main() -> None:
    bundle = DECK.read_text(encoding="utf-8")
    src_en = SRC_EN.read_text(encoding="utf-8")
    src_da = SRC_DA.read_text(encoding="utf-8")

    labels_en = LABEL_RE.findall(src_en)
    labels_da = LABEL_RE.findall(src_da)
    if labels_en != labels_da:
        sys.exit("EN and DA sources disagree on slides (data-label sequence):\n"
                 f"  EN: {labels_en}\n  DA: {labels_da}")
    if not labels_en:
        sys.exit("no <section data-label=…> slides found in the English source")

    m = TEMPLATE_RE.search(bundle)
    if not m:
        sys.exit(f"{DECK}: no __bundler/template script — not a bundle we know")
    template = json.loads(m.group(2))

    # Slides: keep the bundler's own <x-import …> opening tag (its `from`
    # points at a manifest UUID, not ./deck-stage.js) and swap the body.
    body_en = ximport_body(src_en, "EN source")
    body_da = ximport_body(src_da, "DA source")
    template, n = XIMPORT_RE.subn(lambda mm: mm.group(1) + body_en + mm.group(3), template, count=1)
    if n != 1:
        sys.exit("bundle template has no <x-import> block to replace")

    # Palette / type-scale <style> from the source helmet, if both sides have it.
    style_src = STYLE_RE.search(src_en)
    if style_src and STYLE_RE.search(template):
        template = STYLE_RE.sub(lambda _: style_src.group(0), template, count=1)
    else:
        print("note: helmet <style> block not synced (pattern not found on both sides)")

    new_template_tag = m.group(1) + to_script_json(template) + m.group(3)
    da_tag = '\n<script type="__bundler/template-da">' + to_script_json(body_da) + "</script>"

    bundle = TEMPLATE_DA_RE.sub("", bundle)              # drop a stale DA block
    bundle = bundle[:m.start()] + new_template_tag + da_tag + bundle[m.end():]
    bundle = re.sub(r"<title>.*?</title>", f"<title>{TITLE}</title>", bundle, count=1)

    DECK.write_text(bundle, encoding="utf-8")
    print(f"Rebuilt {DECK.relative_to(ROOT)}: {len(labels_en)} slides × 2 languages, "
          f"{len(bundle) // 1024} KiB", flush=True)

    # The presenter bar, notes, favicon and the language toggle live in
    # window-level scripts that the bundler's document swap would discard
    # if they were static markup — patch-deck.sh (re)injects them.
    subprocess.run([str(ROOT / "scripts" / "patch-deck.sh")], check=True)


if __name__ == "__main__":
    main()
