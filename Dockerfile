# The reference instance's OTP release (SETUP.md §2, v5 §8's App
# Platform decision). Two stages: build on hexpm's Elixir image,
# run on slim Debian.
#
# The base pins 27.3.4.16 — the closest published hexpm image to
# .tool-versions' 27.3.4 (same patch line; CI's setup-beam and this
# image drift only at the patch-of-patch level).
FROM hexpm/elixir:1.17.3-erlang-27.3.4.16-debian-bookworm-20260803-slim AS build

RUN apt-get update -y && \
    apt-get install -y --no-install-recommends build-essential git && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app
ENV MIX_ENV=prod
RUN mix local.hex --force && mix local.rebar --force

# Whole-context copy, deliberately: the substrate is a path dep, so a
# selective-COPY cache dance buys little and breaks whenever the
# component list grows. The repo is small; simplicity wins.
COPY . .

RUN mix deps.get --only prod

# GIT_SHA: /health reports it, and deploy detection runs SHA-ancestry
# against it (v5 §2.13) — a build without it deploys but is invisible
# to the pipeline's deploy check. Sources, in order: the GIT_SHA build
# arg, the .git directory if the build context carries one, else "dev"
# (the runbook's verify step catches that).
ARG GIT_SHA=""
RUN sha="$GIT_SHA"; \
    if [ -z "$sha" ] && [ -d .git ]; then sha="$(git rev-parse HEAD 2>/dev/null || true)"; fi; \
    echo "${sha:-dev}" > /app/GIT_SHA

RUN mix compile && mix release --overwrite

FROM debian:bookworm-slim

RUN apt-get update -y && \
    apt-get install -y --no-install-recommends libstdc++6 openssl libncurses6 ca-certificates && \
    rm -rf /var/lib/apt/lists/*

ENV LANG=C.UTF-8 MIX_ENV=prod
WORKDIR /app
COPY --from=build /app/_build/prod/rel/catapult ./
COPY --from=build /app/GIT_SHA /app/GIT_SHA

# GIT_SHA is exported at start rather than baked as ENV so the migrate
# job (which runs `eval`, not `start`) shares the image unchanged.
CMD ["/bin/sh", "-c", "GIT_SHA=$(cat /app/GIT_SHA) exec /app/bin/catapult start"]
