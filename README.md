# catapult

## Reference instance

One deployment of this repo runs as the **reference instance** — the
Catapult control plane running against itself, on DigitalOcean App
Platform from the spec in `.do/app.yaml` (`main`, built from the
`Dockerfile`, migrations run by the `migrate` PRE_DEPLOY job). It is
not a demo: it is the plane that works this repo's own tickets, so the
pipeline's deploy step is checking a real running system. `GET /health`
is the contract everything else reads — the endpoint from
`Catapult.Health`, served on the app's public port, returning the
build's git SHA, an overall `ok`, and per-component readiness as JSON
(200 when every component is ready, 503 otherwise). Deploy detection
watches the App Platform app named in `pipeline.config.json`'s
`deploy.endpoint`; ops and agents read the same `/health` facts.
