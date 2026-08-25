defmodule CatapultWeb.Storybook do
  @moduledoc """
  `phoenix_storybook`'s backend module (`systems/dashboard.md`'s
  placement decision): points at `storybook/`, where every screen's
  `component.ex`/`component.story.exs` pair lives, design-owned and
  committed beside the screen doc that maps it.
  """
  use PhoenixStorybook,
    otp_app: :catapult,
    content_path: Path.expand("../../storybook", __DIR__),
    title: "Catapult"
end
