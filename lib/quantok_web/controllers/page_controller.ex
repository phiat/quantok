defmodule QuantokWeb.PageController do
  use QuantokWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
