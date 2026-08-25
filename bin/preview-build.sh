#!/usr/bin/env bash
#
# Builds the branch preview that `pipeline.config.json` -> `preview` names
# and orchestration's `agent-design`/`agent-dev` actions publish to
# Cloudflare Pages. Those actions `eval` this from `pipeline.config.json`'s
# `buildCommand` and then deploy `outputDir`.
#
# It installs its own toolchain, and that is the whole reason it exists as
# a script rather than a one-liner. The agent actions install Go only
# (`setup-pipeline`) — they are language-agnostic by design, so no `mix`
# exists on that runner — while `erlef/setup-beam`, which ci.yml uses, is a
# composite Action and cannot be reached from a shell string. So the
# toolchain is fetched the same way setup-beam fetches it: precompiled OTP
# from builds.hex.pm and a precompiled Elixir from the elixir-lang release,
# both at the versions `.tool-versions` pins. The pin is read, never
# duplicated here — CLAUDE.md's "the pinned toolchain is the only supported
# one" would stop being true the moment this file carried a second copy of
# the numbers.
#
# **This script never exits non-zero.** The action wraps it in `set -euo
# pipefail`, so a failure here fails the whole agent job — a broken preview
# would stop tickets dispatching, which is far worse than a missing one.
# Every step that can fail degrades to the placeholder instead and says why
# on stdout, where the job log keeps it.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

OUT="dist"
PLACEHOLDER="preview/index.html"

# Publish the placeholder and stop, with a reason the job log records.
# Called for every non-fatal failure below, so the preview slot is always
# filled with something honest rather than left empty or stale.
fall_back() {
  echo "preview: $1"
  echo "preview: publishing the placeholder instead"
  mkdir -p "$OUT"
  cp "$PLACEHOLDER" "$OUT/index.html"
  exit 0
}

# ---------------------------------------------------------------- toolchain

ERLANG_VERSION="$(awk '$1 == "erlang" { print $2 }' .tool-versions)"
# `.tool-versions` spells Elixir as `1.17.3-otp-27`; the release asset is
# `elixir-otp-27.zip` under tag `v1.17.3`, so both halves are needed.
ELIXIR_RAW="$(awk '$1 == "elixir" { print $2 }' .tool-versions)"
ELIXIR_VERSION="${ELIXIR_RAW%%-otp-*}"
ELIXIR_OTP_MAJOR="${ELIXIR_RAW##*-otp-}"

[ -n "$ERLANG_VERSION" ] && [ -n "$ELIXIR_VERSION" ] ||
  fall_back "could not read the toolchain pin out of .tool-versions"

# builds.hex.pm keys OTP builds by distribution, so the runner image's own
# release id picks the build rather than a hardcoded guess that silently
# rots when GitHub moves ubuntu-latest forward.
UBUNTU="$(. /etc/os-release && echo "${VERSION_ID:-}")"
[ -n "$UBUNTU" ] || fall_back "could not read the ubuntu release from /etc/os-release"

TOOLS="$(mktemp -d)"
OTP_URL="https://builds.hex.pm/builds/otp/ubuntu-${UBUNTU}/OTP-${ERLANG_VERSION}.tar.gz"
ELIXIR_URL="https://github.com/elixir-lang/elixir/releases/download/v${ELIXIR_VERSION}/elixir-otp-${ELIXIR_OTP_MAJOR}.zip"

echo "preview: installing OTP ${ERLANG_VERSION} and Elixir ${ELIXIR_RAW}"

curl -fsSL --retry 3 "$OTP_URL" | tar -xz -C "$TOOLS" ||
  fall_back "could not fetch precompiled OTP from ${OTP_URL}"

OTP_DIR="$(find "$TOOLS" -maxdepth 1 -name 'OTP-*' -type d | head -1)"
[ -n "$OTP_DIR" ] || fall_back "the OTP tarball did not contain an OTP-* directory"
# Precompiled OTP hardcodes its build-time prefix; ./Install rewrites the
# scripts for wherever it actually landed. Without it every `erl` fails.
(cd "$OTP_DIR" && ./Install -minimal "$OTP_DIR") >/dev/null ||
  fall_back "OTP's own ./Install failed"
export PATH="$OTP_DIR/bin:$PATH"

curl -fsSL --retry 3 -o "$TOOLS/elixir.zip" "$ELIXIR_URL" ||
  fall_back "could not fetch precompiled Elixir from ${ELIXIR_URL}"
unzip -q "$TOOLS/elixir.zip" -d "$TOOLS/elixir" ||
  fall_back "could not unpack the Elixir release"
export PATH="$TOOLS/elixir/bin:$PATH"

command -v mix >/dev/null || fall_back "mix is still not on PATH after installing the toolchain"

# Measured, not precautionary: a first run of this script warned that the
# VM was using latin1 name encoding, which Elixir itself reports "may cause
# Elixir to malfunction as it expects utf8". setup-beam's own environment
# gets this from the runner's locale; a hand-installed OTP does not
# inherit it reliably, so it is set here rather than hoped for.
export ELIXIR_ERL_OPTIONS="+fnu"

export MIX_ENV=prod
export MIX_HOME="$TOOLS/.mix"
export HEX_HOME="$TOOLS/.hex"

mix local.hex --force --if-missing >/dev/null 2>&1
mix local.rebar --force --if-missing >/dev/null 2>&1
mix deps.get >/dev/null || fall_back "mix deps.get failed"

# ------------------------------------------------------------------ export
#
# The storybook is served at runtime by a Phoenix route — phoenix_storybook
# ships no static export (its only mix tasks are `dev.storybook` and
# `phx.gen.storybook`), so a static Pages deploy means booting the app and
# snapshotting what it serves. None of that exists until the dashboard's
# endpoint lands (`systems/dashboard.md`'s own file map, ORC-35's dev pass),
# so until then this is a placeholder by fact rather than by choice, and it
# says which.

[ -d "lib/catapult_web" ] ||
  fall_back "no lib/catapult_web yet — the storybook has no endpoint to serve it"

fall_back "lib/catapult_web exists, but the boot-and-snapshot step is not written yet"
