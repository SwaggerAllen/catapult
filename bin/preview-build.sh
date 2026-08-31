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
# `phx.gen.storybook`) — but per `systems/dashboard.md`'s ORC-113 decision
# the export never boots the app to get one. Stories are stateless function
# components by this system's own placement rule, so each variation's
# attributes are called straight into its story's component function and
# the rendered markup is written to dist/ directly — `Catapult.Application`
# is never entered, so no endpoint, no supervision tree, no database is
# needed on the runner. What is traded away is phoenix_storybook's own
# navigation chrome; the generated index below stands in for it.

STORIES="$(find storybook/screens -name 'component.story.exs' 2>/dev/null)"
[ -n "$STORIES" ] ||
  fall_back "no storybook/screens/*/component.story.exs yet — nothing to export"

mix compile >/dev/null || fall_back "mix compile failed"

# Builds priv/static/assets/app.css from assets/css/app.css and the
# vendored daisyUI plugins (`systems/dashboard.md`'s ORC-183 entry).
# Nothing downstream reads that file before the export script below
# copies it, so this has to fail the same way every other step here
# does: fall back to the placeholder rather than let the export run and
# silently publish pages that link a stylesheet that was never built.
mix assets.build >/dev/null || fall_back "mix assets.build failed"

EXPORT_SCRIPT="$TOOLS/storybook_export.exs"
cat >"$EXPORT_SCRIPT" <<'ELIXIR'
out_dir = System.fetch_env!("PREVIEW_OUT")
File.mkdir_p!(out_dir)

# Relative, not root-absolute — this export ships to a Cloudflare Pages
# hash subdomain with no fixed base path to hardcode against, the same
# reasoning the rest of this export already carries
# (`systems/dashboard.md`'s ORC-183 entry). `File.cp!/2` raises if
# `mix assets.build` above did not actually produce this file, which is
# what turns a silently-missing stylesheet into the same `fall_back` this
# whole script already gives every other failure.
assets_dir = Path.join(out_dir, "assets")
File.mkdir_p!(assets_dir)
File.cp!(Path.join(["priv", "static", "assets", "app.css"]), Path.join(assets_dir, "app.css"))

story_files =
  "storybook/screens/*/component.story.exs"
  |> Path.wildcard()
  |> Enum.sort()

if story_files == [] do
  IO.puts(:stderr, "preview export: no story files found")
  System.halt(1)
end

screens =
  Enum.map(story_files, fn path ->
    slug = path |> Path.dirname() |> Path.basename()

    [{module, _binary}] = Code.compile_file(path)

    function = module.function()
    variations = module.variations()

    pages =
      Enum.map(variations, fn variation ->
        # A plain attributes map has no `__changed__`, which `Phoenix.Component.assign/3`
        # requires of anything that isn't a real `Socket` — board's and ticket's own function
        # bodies call it directly. `Phoenix.LiveViewTest.__render_component__/4` hits the same
        # gap calling a function component straight, and closes it exactly this way.
        assigns =
          variation.attributes
          |> Map.new()
          |> Map.put_new(:__changed__, %{})

        rendered = function.(assigns)
        html = Phoenix.LiveViewTest.rendered_to_string(rendered)

        page = """
        <!doctype html>
        <html lang="en">
          <head>
            <meta charset="utf-8" />
            <title>#{slug} — #{variation.id}</title>
            <link rel="stylesheet" href="../assets/app.css" />
          </head>
          <body>
            #{html}
          </body>
        </html>
        """

        screen_dir = Path.join(out_dir, slug)
        File.mkdir_p!(screen_dir)
        file_name = "#{variation.id}.html"
        File.write!(Path.join(screen_dir, file_name), page)

        %{id: variation.id, description: Map.get(variation, :description), file: "#{slug}/#{file_name}"}
      end)

    %{slug: slug, pages: pages}
  end)

index_items =
  Enum.map_join(screens, "\n", fn screen ->
    links =
      Enum.map_join(screen.pages, "\n", fn page ->
        suffix = if page.description, do: " — #{page.description}", else: ""
        ~s(<li><a href="#{page.file}">#{page.id}</a>#{suffix}</li>)
      end)

    """
    <section>
      <h2>#{screen.slug}</h2>
      <ul>
    #{links}
      </ul>
    </section>
    """
  end)

index = """
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <title>Catapult — storybook export</title>
    <link rel="stylesheet" href="assets/app.css" />
  </head>
  <body>
    <h1>Catapult — storybook export</h1>
    #{index_items}
  </body>
</html>
"""

File.write!(Path.join(out_dir, "index.html"), index)

IO.puts("preview: exported #{length(screens)} screens")
ELIXIR

mkdir -p "$OUT"
PREVIEW_OUT="$ROOT/$OUT" mix run --no-start --no-compile "$EXPORT_SCRIPT" ||
  fall_back "the storybook export script failed"

[ -f "$OUT/index.html" ] || fall_back "the export ran but produced no $OUT/index.html"

echo "preview: storybook export written to $OUT"
