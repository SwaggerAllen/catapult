defmodule CatapultWeb.Layouts do
  @moduledoc """
  The one root layout every screen renders inside (`systems/dashboard.md`).
  No navigation chrome yet — v0 is two screens reached by direct link
  and by `explain-why`'s own node link, not a nav shell; a nav bar is
  v1's, once there is a work loop to navigate between.
  """
  use CatapultWeb, :html

  def root(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="csrf-token" content={Plug.CSRFProtection.get_csrf_token()} />
        <title>Catapult</title>
        <link rel="stylesheet" href="/assets/app.css" />
        <script defer type="text/javascript" src="/assets/app.js">
        </script>
      </head>
      <body>
        {@inner_content}
      </body>
    </html>
    """
  end
end
