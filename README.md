# Docker for the Curious

Workshop deck and companion image for the two-hour hands-on workshop
**"Docker for the Curious"** — containers from absolute zero.
Host: Gorm Reventlow. The deck is bilingual: English and Danish, switchable
live with a button (or the `l` key) without losing your place.

## Run the deck (also your fallback if the hosted deck is down)

Every push to `main` publishes the deck to Docker Hub, so wherever the
hosted copy lives, you can always pull the slides and run them locally:

```sh
docker pull elohite/docker-workshop-deck:latest
docker run -d -p 8080:80 elohite/docker-workshop-deck
# open http://localhost:8080 — arrow keys / space to navigate; "f" fullscreen,
# "s" slide rail, "n" speaker notes, "l" language (also buttons bottom-left)
```

The deck is fully self-contained (fonts inlined) and works offline.
Browser print gives one page per slide. Pin a version tag
(e.g. `elohite/docker-workshop-deck:2.0`) if you want the exact deck as presented.

### Language

`http://localhost:8080/?lang=da` opens the Danish deck, `?lang=en` the
English one; the choice is remembered in the browser, so a bare URL
reopens in the language last used. The `DA`/`EN` button (or `l`) switches
in place and stays on the current slide. Speaker notes and the presenter
bar follow the language.

## The companion image attendees pull

```sh
docker run -d -p 8080:80 --name camp elohite/docker-workshop
# shows "I was at the Docker workshop" at http://localhost:8080
```

Debian-based nginx with `bash` and `nano` baked in — the slides walk attendees
through `docker exec -it camp bash`, editing the page with nano, and mounting a
volume over the html directory. Built for `linux/amd64` and `linux/arm64`.

## Repository layout

```
deck/index.html        ← the deck, compiled single-file bundle. Do not hand-edit.
Dockerfile             ← deck image (nginx:alpine serving deck/index.html)
workshop-image/        ← companion image (Debian nginx + nano + landing page)
source/                ← editable slide sources: *.dc.html (EN) and *.da.dc.html (DA)
source/assets/         ← images the slides reference as ./assets/<file>
scripts/build-deck.py  ← rebuilds deck/index.html from source/ (then runs patch-deck.sh)
scripts/patch-deck.sh  ← injects language toggle, presenter bar, speaker notes, favicon
.github/workflows/     ← CI: build + push both images to Docker Hub
```

## Editing the slides

1. Edit `source/Docker for the Curious.dc.html` (English) and
   `source/Docker for the Curious.da.dc.html` (Danish). Keep the two files
   structurally identical — same slides, same order, same `data-label`
   attributes (those are the keys for the speaker notes). Only the visible
   text and `data-screen-label` differ.
Images go in `source/assets/` and are referenced as
`src="./assets/<file>"`, which keeps the sources viewable in a plain
browser; the build ships each file once as a data URI and resolves the
paths at load, so the deck stays a single offline file.

2. Run `./scripts/build-deck.py`. It splices both slide sets into the
   bundle (the bundler stores the whole document as a JSON string that its
   bootloader parses at load — no design tool needed), refuses to build if
   the two sources disagree on slides, and then runs `patch-deck.sh`.
3. Speaker notes (both languages) live in `scripts/patch-deck.sh` as a
   per-`data-label` map; edit them there and re-run the build.

`deck/index.html` is the build artifact we serve; never hand-edit it.

## CI / publishing

Every push to `main` builds and pushes `elohite/docker-workshop-deck:latest` and
`elohite/docker-workshop:latest` to Docker Hub. A version tag (`git tag v2.0 &&
git push --tags`) additionally publishes `:2.0`.

Required repository secrets: `DOCKERHUB_USERNAME`, `DOCKERHUB_TOKEN`.
