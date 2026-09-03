// The standard LiveView client (ORC-220, `systems/dashboard.md`): a
// socket to `/live` (`CatapultWeb.Endpoint`), so `handle_event/3` on
// `document-review`, `board` and `ticket` becomes reachable. The
// storybook mounts its own client independently and is unaffected.
import "phoenix_html"
import { Socket } from "phoenix"
import { LiveSocket } from "phoenix_live_view"

let csrfToken = document
  .querySelector("meta[name='csrf-token']")
  .getAttribute("content")

let liveSocket = new LiveSocket("/live", Socket, {
  params: { _csrf_token: csrfToken }
})

liveSocket.connect()

window.liveSocket = liveSocket
