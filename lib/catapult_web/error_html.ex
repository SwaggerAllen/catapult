defmodule CatapultWeb.ErrorHTML do
  @moduledoc """
  The endpoint's `render_errors` target (Phoenix.Endpoint's own
  requirement). No custom error pages in v0 — a plain status message is
  the whole of it; this is a debugging surface, not the working one.
  """
  use CatapultWeb, :html

  def render(template, _assigns) do
    Phoenix.Controller.status_message_from_template(template)
  end
end
