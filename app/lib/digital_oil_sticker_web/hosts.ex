defmodule DigitalOilStickerWeb.Hosts do
  @moduledoc """
  The production host list, in one place (DOS-M09-007 FR-5, FR-2).

  Three things have to agree about which hosts are ours, and they drift apart
  the moment each keeps its own copy:

    * `check_origin` — which origins may open a LiveView socket,
    * the CSP `connect-src` — which origins the page may connect back to,
    * `PHX_HOST` — the host the app builds its own URLs from.

  A disagreement is not a loud failure. It is a socket that refuses to connect
  for one host, or a CSP that blocks the app's own websocket, discovered by a
  user. So the list lives here and the others read it.

  ## `check_origin` is a list, never a boolean

  FR-5 prohibits both `true` and `false`. `false` disables the check outright.
  `true` compares against the endpoint's configured `:url`, which is derived
  from `PHX_HOST` — correct today by coincidence, and silently wrong the moment
  a second hostname is served. Naming the hosts makes the decision reviewable.

  ## The custom domain landed 2026-08-04

  `digitaloilsticker.com` (apex) and `www.digitaloilsticker.com` now resolve
  to this app's Fly IPs (A 66.241.125.208, AAAA 2a09:8280:1::15c:3e81:0),
  their Fly certificates are issued, and both are trusted here so LiveView
  sockets from the custom origin are accepted. The `.net` domain points at
  the separate Netlify static support site (INV-27) and is deliberately NOT
  a production host of the app — it stays in `@planned` as documentation.
  """

  @fly_host "digital-oil-sticker.fly.dev"

  # Owned but not served by this app. `.net` is the Netlify static
  # support site's home; a LiveView socket connect from `.net` would be
  # a misconfiguration and is correctly refused (INV-27).
  @planned ["digitaloilsticker.net"]

  @doc "Hosts that may serve the application and open a socket, in production."
  @spec production() :: [String.t()]
  def production, do: [
    "digitaloilsticker.com",
    "www.digitaloilsticker.com",
    @fly_host
  ]

  @doc "Owned hosts that are not yet served. Documentation, not trust."
  @spec planned() :: [String.t()]
  def planned, do: @planned

  @doc """
  Origins for `check_origin`. Scheme-qualified https only: an http origin on a
  force_ssl app is either a misconfiguration or someone probing.
  """
  @spec allowed_origins() :: [String.t()]
  def allowed_origins, do: Enum.map(production(), &"https://#{&1}")

  @doc """
  `connect-src` for the CSP. `'self'` covers same-origin HTTP, but a websocket
  is a different scheme and is not covered by it — without the explicit
  `wss://` entry the LiveView socket is blocked by our own policy.
  """
  @spec connect_src() :: String.t()
  def connect_src,
    do: Enum.map_join(["'self'" | Enum.map(production(), &"wss://#{&1}")], " ", & &1)

  @doc "The canonical host this deployment serves. Read from the environment so a review can see it moved."
  @spec canonical() :: String.t()
  def canonical, do: System.get_env("PHX_HOST") || @fly_host
end
