defmodule PolticoolWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use PolticoolWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://phoenix.hexdocs.pm/scopes.html)"

  attr :tag, :string,
    default: nil,
    doc: ~s|small label in the top bar, e.g. "Sample" while pages show placeholder data|

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <a
      href="#main"
      class="sr-only focus:not-sr-only focus:fixed focus:left-3 focus:top-3 focus:z-50 focus:rounded-lg focus:bg-ink focus:px-3 focus:py-2 focus:text-sm focus:font-semibold focus:text-paper"
    >
      Skip to content
    </a>

    <header
      id="site-header"
      class="sticky top-0 z-40 border-b border-rule bg-paper"
    >
      <div class="mx-auto flex h-14 w-full max-w-2xl items-center justify-between px-[18px] sm:px-6">
        <.link
          id="site-logo"
          navigate={~p"/"}
          class="group -mx-1 rounded-md px-1 font-serif text-[19px] font-bold tracking-[-0.02em] text-ink"
        >
          Politi<span class="text-accent transition-colors duration-200 group-hover:text-grade-c">cool</span>
        </.link>

        <span
          :if={@tag}
          id="site-tag"
          class="rounded-[3px] border border-rule px-1.5 py-0.5 text-[10px] font-medium uppercase tracking-[0.08em] text-faint"
        >
          {@tag}
        </span>
      </div>
    </header>

    <main
      id="main"
      class="mx-auto w-full max-w-2xl px-[18px] pb-16 pt-6 motion-safe:animate-[page-in_250ms_ease-out] sm:px-6 sm:pt-10"
    >
      {render_slot(@inner_block)}
    </main>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={
          show(".phx-client-error #client-error")
          |> JS.remove_attribute("hidden", to: ".phx-client-error #client-error")
        }
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={
          show(".phx-server-error #server-error")
          |> JS.remove_attribute("hidden", to: ".phx-server-error #server-error")
        }
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end
end
