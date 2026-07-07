# The image attendees pull in the workshop.
# MUST stay Debian-based (slides use `docker exec -it camp bash`)
# and MUST include nano (slide 11: "we baked nano into this image").
FROM nginx
RUN apt-get update && apt-get install -y --no-install-recommends nano && rm -rf /var/lib/apt/lists/*
COPY index.html /usr/share/nginx/html/index.html
