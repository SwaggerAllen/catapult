# catapult

## Reference instance

One deployment of this repo runs as the **reference instance** — the
Catapult control plane running against itself, on DigitalOcean App
Platform. It is not a demo: it is the plane that works this repo's own
tickets, so the pipeline's deploy step is checking a real running
system. `GET /health` is the contract everything else reads — the
endpoint from `Catapult.Health`, the only served path, returning the
build's git SHA, an overall `ok`, and per-component readiness as JSON
(200 when every component is ready, 503 otherwise); ops and agents
read those facts. Deploy detection watches the App Platform app
itself instead. The live app's own specifics — name, region, public
hostname, port, autodeploy, the migrate PRE_DEPLOY job, the id of the
app deploy detection watches — are in `SETUP.md` §2 and nowhere else.
