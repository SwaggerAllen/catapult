# catapult

## Reference instance

One deployment of this repo runs as the **reference instance** — the
Catapult control plane running against itself, on DigitalOcean App
Platform. It is not a demo: it is the plane that works this repo's own
tickets, so the pipeline's deploy step is checking a real running
system. `GET /health` is the contract everything else reads — the
endpoint from `Catapult.Health`, returning the build's git SHA, an
overall `ok`, and per-component readiness as JSON (200 when every
component is ready, 503 otherwise); ops and agents read those facts.
Deploy detection watches the App Platform app itself instead. A second
path, `/dispatch/*`, serves the agent-dispatch host port's
context-fetch/result-report calls (`systems/generation.md`,
`systems/delivery.md`); both paths sit behind
`Catapult.Foundation.DispatchPlug`'s registry-driven dispatch over
`api_surface/0` (ORC-35). A third path, dashboard's own screens
(`event-log`, `explain-why`) and the storybook, sits behind
`CatapultWeb.Router` — the two mechanisms share `CatapultWeb.Endpoint`,
this instance's one public listener, rather than each opening its own
(`SETUP.md` §2, `systems/foundation.md`). The live app's own
specifics — name, region, public hostname, port, autodeploy, the
migrate PRE_DEPLOY job, the id of the app deploy detection watches —
are in `SETUP.md` §2 and nowhere else.
