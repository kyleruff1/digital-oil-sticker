defmodule DigitalOilStickerWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use DigitalOilStickerWeb, :html

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

  attr :unsaved_writes, :list,
    default: [],
    doc: "writes this browser refused; rendered persistently and never auto-dismissed"

  attr :read_only, :boolean,
    default: false,
    doc: "this browser holds records from a newer app version; mutations are off"

  attr :conflict_notice, :boolean,
    default: false,
    doc: "another tab wrote newer data; hydration re-ran and the user must be told"

  attr :storage_mode, :atom,
    default: nil,
    doc: "browser storage mode; :session_only surfaces a persistent non-persistence banner"

  attr :skin, :string,
    default: nil,
    doc: "the sticker skin slug (Skins.slugs/0); scopes the skin CSS tokens and page accents"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <%!-- display:contents — layout-neutral; the element exists only to carry
         the skin scope. Custom properties inherit through it, so one
         attribute themes the sticker AND re-tints the page accents. The
         SkinChrome hook mirrors the accent into the theme-color meta, which
         lives in the static root layout out of LiveView's reach. --%>
    <div
      data-skin={@skin}
      data-theme-color={@skin && DigitalOilStickerWeb.Skins.accent(@skin)}
      phx-hook="SkinChrome"
      id="skin-chrome"
      class="contents"
    >
      <%!-- The LocalStore hook element lives in the layout: it renders inside
         each LiveView's own container, so navigation re-mounts it and
         hydration is per-mount by construction (INV-24 / ADR-0004). --%>
      <div id="local-store" phx-hook="LocalStore" aria-hidden="true"></div>

      <%!-- This browser holds data written by a newer version of the app, so
         mutations are disabled to avoid overwriting fields this build does not
         understand. Without this banner the user just finds the save buttons
         inert with no explanation and no way out (INV-24.2, INV-25). --%>
      <div
        :if={@read_only}
        id="read-only-notice"
        role="alert"
        data-test="read-only"
        class="border-b-2 border-sky-500 bg-sky-50 px-4 py-3 text-sm text-sky-900"
      >
        <p>{DigitalOilStickerWeb.Copy.read_only_banner()}</p>
        <.link navigate={~p"/settings/storage"} class="btn btn-sm mt-2">Export a file</.link>
      </div>

      <%!-- A write the browser refused. Deliberately not dismissible and not on a
         timer: the entry is on screen but is not stored, and the user has to be
         able to see that for as long as it is true (INV-24.5). --%>
      <div
        :if={@unsaved_writes != []}
        id="unsaved-writes"
        role="alert"
        data-test="unsaved-writes"
        class="border-b-2 border-amber-500 bg-amber-50 px-4 py-3 text-sm text-amber-900"
      >
        <p class="font-semibold">{DigitalOilStickerWeb.Copy.unsaved_record()}</p>

        <p class="mt-1">{unsaved_body(@unsaved_writes)}</p>
        <.link navigate={~p"/settings/storage"} class="btn btn-sm mt-2">Export a file</.link>
      </div>

      <%!-- Another tab wrote newer data. Session.handle_conflict/2 sets this
         assign and pushes local_store:rehydrate; without a rendered notice the
         user just watches the page snap to newer content with no explanation
         of where it came from. INV-24.7 requires the conflict to be surfaced,
         not only handled behind the scenes. --%>
      <div
        :if={@conflict_notice}
        id="conflict-notice"
        role="status"
        aria-live="polite"
        data-test="conflict-notice"
        class="border-b-2 border-sky-500 bg-sky-50 px-4 py-3 text-sm text-sky-900"
      >
        <p>{DigitalOilStickerWeb.Copy.conflict_notice()}</p>
      </div>

      <%!-- Session-only storage: nothing the user types is being persisted. A
         put_flash is dismissible and time-bounded; the truth here is that
         until the browser's storage setting changes, EVERY entry is transient
         — so the notice has to stay visible for as long as it is true, in the
         same never-dismissible pattern as unsaved-writes. role="alert" flags
         it as a warning about non-persistence rather than a passive status.
         The export link routes to the one page that can turn the tab's data
         into a file before it is lost (INV-24 / INV-25). --%>
      <div
        :if={@storage_mode == :session_only}
        id="session-only-notice"
        role="alert"
        data-test="session-only-banner"
        class="border-b-2 border-amber-500 bg-amber-50 px-4 py-3 text-sm text-amber-900"
      >
        <p>{DigitalOilStickerWeb.Copy.session_only_banner()}</p>
        <.link navigate={~p"/settings/storage"} class="btn btn-sm mt-2">Export a file</.link>
      </div>

      <%!-- Wraps rather than scrolling: at 320px a single-row navbar overflowed
         the viewport, which is the WCAG 1.4.10 reflow failure. --%>
      <header class="navbar flex-wrap gap-y-1 px-4 sm:px-6 lg:px-8">
        <div class="flex-1">
          <.link navigate={~p"/"} class="flex w-fit items-center gap-2">
            <img src={~p"/images/dos-mark.svg"} width="36" alt="" />
            <span class="text-sm font-semibold">Digital Oil Sticker</span>
          </.link>
        </div>

        <%!-- Full width on narrow viewports so the list has a boundary to wrap
           against; `flex-none` alone sizes the nav to its content, which is how
           it kept overflowing at 320px. --%>
        <nav class="w-full sm:w-auto sm:flex-none" aria-label="Main menu">
          <ul class="flex flex-wrap items-center gap-x-2 gap-y-1 px-1">
            <li><.link navigate={~p"/vehicle"} class="btn btn-ghost btn-sm">Vehicle</.link></li>

            <li>
              <.link navigate={~p"/service/new"} class="btn btn-ghost btn-sm">Log oil change</.link>
            </li>

            <li><.link navigate={~p"/history"} class="btn btn-ghost btn-sm">History</.link></li>

            <li>
              <.link navigate={~p"/settings/storage"} class="btn btn-ghost btn-sm">Storage</.link>
            </li>

            <li><.theme_toggle /></li>
          </ul>
        </nav>
      </header>

      <main class="px-4 py-10 sm:px-6 lg:px-8">
        <div class="mx-auto max-w-3xl space-y-4">
          {render_slot(@inner_block)}
        </div>
      </main>
      <.flash_group flash={@flash} />
    </div>
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
      <.flash kind={:info} flash={@flash} /> <.flash kind={:error} flash={@flash} />
      <.flash
        id="client-error"
        kind={:error}
        title="We can't find the internet"
        phx-disconnected={
          show(".phx-client-error #client-error")
          |> JS.remove_attribute("hidden", to: ".phx-client-error #client-error")
        }
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        Attempting to reconnect
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title="Something went wrong!"
        phx-disconnected={
          show(".phx-server-error #server-error")
          |> JS.remove_attribute("hidden", to: ".phx-server-error #server-error")
        }
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        Attempting to reconnect
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  # Quota gets its own sentence because "your browser is full" and "the write
  # failed" call for different actions from the user.
  defp unsaved_body(unsaved) do
    if Enum.any?(unsaved, &(&1.reason in ["quota", "quota_exceeded", "QuotaExceededError"])) do
      DigitalOilStickerWeb.Copy.quota_full()
    else
      DigitalOilStickerWeb.Copy.not_saved_body()
    end
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 [[data-theme-source=system]_&]:!left-0 transition-[left]" />
      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
        aria-label="Follow the system theme"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
        aria-label="Use the light theme"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
        aria-label="Use the dark theme"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
