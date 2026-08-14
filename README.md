# catapult

## Reference instance

One deployment of this repo runs as the **reference instance** — the
Catapult control plane running against itself, on DigitalOcean App
Platform (app `catapult`, region `sfo`, autodeployed from `main`,
built from the `Dockerfile`, migrations run by the `migrate`
PRE_DEPLOY job). There is deliberately no committed app spec: the live
app is the authority on its own configuration, and `SETUP.md` §2
records the facts a future session needs. It is not a demo: it is the
plane that works this repo's own tickets, so the pipeline's deploy
step is checking a real running system. `GET /health` is the contract
everything else reads — the endpoint from `Catapult.Health`, the only
served path on `https://catapult-ezten.ondigitalocean.app` (public
port 8080, fixed by App Platform), returning the build's git SHA, an
overall `ok`, and per-component readiness as JSON (200 when every
component is ready, 503 otherwise). Deploy detection watches the App
Platform app whose id is in `pipeline.config.json`'s
`deploy.endpoint`; ops and agents read the same `/health` facts.
