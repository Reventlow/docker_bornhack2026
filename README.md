# Docker for the Curious — BornHack 2026

Workshop deck and companion image for the BornHack 2026 workshop
**"Docker for the Curious"** — Friday 17 Jul 2026, 15:00–17:00, Workshop Room.
Host: Gorm Reventlow.

## Run the deck

```sh
docker run -d -p 8080:80 elohite/bornhack-deck
# open http://localhost:8080 — arrow keys / space to navigate, "f" toggles fullscreen
```

The deck is fully self-contained (fonts inlined) and works offline.
Browser print gives one page per slide.

## The companion image attendees pull

```sh
docker run -d -p 8080:80 --name camp elohite/bornhack2026
# shows "I was at BornHack 2026" at http://localhost:8080
```

Debian-based nginx with `bash` and `nano` baked in — the slides walk attendees
through `docker exec -it camp bash`, editing the page with nano, and mounting a
volume over the html directory. Built for `linux/amd64` and `linux/arm64`.

## Repository layout

```
deck/index.html        ← the deck, compiled single-file bundle. Do not hand-edit.
Dockerfile             ← deck image (nginx:alpine serving deck/index.html)
workshop-image/        ← companion image (Debian nginx + nano + landing page)
source/                ← editable design-tool source; kept for provenance only
.github/workflows/     ← CI: build + push both images to Docker Hub
```

Edits to the deck happen in `source/Docker for the Curious.dc.html` and are
re-bundled by the design tool; `deck/index.html` is the build artifact we serve.
After a re-bundle, run `./scripts/patch-deck.sh` to re-apply the tab title,
favicon, and the "f" fullscreen toggle (the bundler's outer shell lacks them).

## CI / publishing

Every push to `main` builds and pushes `elohite/bornhack-deck:latest` and
`elohite/bornhack2026:latest` to Docker Hub. A version tag (`git tag v1.0 &&
git push --tags`) additionally publishes `:1.0`.

Required repository secrets: `DOCKERHUB_USERNAME`, `DOCKERHUB_TOKEN`.
