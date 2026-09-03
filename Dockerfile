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

# The digested stylesheet (ORC-183, `systems/dashboard.md`): compiles
# and minifies `assets/css/app.css` through the standalone Tailwind CLI,
# then `phx.digest` fingerprints it into `priv/static`, before the
# release assembles so the CSS ships inside the image rather than being
# generated (or missing) at deploy time.
RUN mix assets.deploy

RUN mix compile && mix release --overwrite

FROM debian:bookworm-slim

RUN apt-get update -y && \
    apt-get install -y --no-install-recommends libstdc++6 openssl libncurses6 ca-certificates && \
    rm -rf /var/lib/apt/lists/*

ENV LANG=C.UTF-8 MIX_ENV=prod
WORKDIR /app
COPY --from=build /app/_build/prod/rel/catapult ./
COPY --from=build /app/GIT_SHA /app/GIT_SHA
# The DSL bundle is content the release reads at runtime, not code the
# release compiles in: every `Catapult.Dsl.load/1` in the plane — the
# engine projector, both sweepers, the commit path, the dispatch
# worker, and four screens — resolves `catapult.yaml` and `bundles/`
# against `bundles_root`, which defaults to `.` and is this WORKDIR.
# Without these two lines the reference instance booted green and then
# failed every one of those loads with "./catapult.yaml does not
# exist": the sweeper skipped every tick and the screens answered 500,
# while /health stayed green because it loads nothing.
COPY --from=build /app/catapult.yaml /app/catapult.yaml
COPY --from=build /app/bundles /app/bundles

# The migrator runs here, in the container's own start command, ahead
# of `start` — not as an App Platform PRE_DEPLOY job. A job is a second
# component with its own environment: every required variable
# duplicated by hand and silently stale the day one is added. And on
# the reference instance no job was ever configured, so every
# migration dated 2026-09-01 or later went unapplied while each deploy
# reported green — `delivery_projects` did not exist, provisioning
# answered 500 for four live-suite runs, and nothing on the deploy
# said so. Here the migrator boots from the same environment the
# service does, by construction, and the failure semantics are the
# ones a PRE_DEPLOY job promised: `eval` exits non-zero on a raise,
# `&&` stops the container before `start`, the health check never
# answers, and App Platform fails the deploy with the previous
# deployment still serving. (Expected from App Platform's documented
# behaviour; not yet observed on a failing migration.) Sequential, not
# concurrent: the migrator's own connections (`Catapult.Release`'s
# `@migrator_pool_size`) close before the service opens its pool, so
# SETUP.md §2's cutover arithmetic holds unchanged, and two instances
# of one rolling deploy migrating at once are serialized by Ecto's
# migration lock on `schema_migrations`.
#
# The component's Run Command stays blank in the dashboard: a value
# there replaces this CMD, migrator included, and the deploy goes
# back to reporting green over an unmigrated database.
#
# GIT_SHA is exported at start rather than baked as ENV: /health is
# its only reader, and the file is the build's one stamping site.
CMD ["/bin/sh", "-c", "/app/bin/catapult eval Catapult.Release.migrate && GIT_SHA=$(cat /app/GIT_SHA) exec /app/bin/catapult start"]
