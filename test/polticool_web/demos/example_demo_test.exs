defmodule PolticoolWeb.Demos.ExampleDemo do
  use PhxDemo.Case
  use PolticoolWeb, :verified_routes

  demo "tour the home page", %{conn: conn} do
    conn
    |> scene("Welcome")
    |> visit(~p"/")
    |> say("This demo was recorded automatically with phx_demo.")
  end
end
