defmodule QuantokWeb.Layouts do
  @moduledoc """
  Holds layout templates. We only ship a root layout — the actual UI is
  rendered by `QuantokWeb.WorldLive` directly inside it.
  """
  use QuantokWeb, :html

  embed_templates "layouts/*"
end
