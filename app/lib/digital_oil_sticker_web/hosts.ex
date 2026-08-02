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

  ## The custom domain is not here yet

  `digitaloilsticker.com` and `.net` are owned but not yet pointed at this app;
  DNS and certificates are DOS-M09-006 (#84). They are listed in
  `planned/0` rather than `production/0` so this file records the intent
  without asserting a host that does not resolve — adding them is a one-line
  move once #84 lands, and the tests here will hold them to the same rules.
  """

  @fly_host "digital-oil-sticker.fly.dev"

  # Owned, decided, not yet serving. Deliberately NOT trusted until #84 points
  # DNS and issues certificates: trusting a host we do not yet control the
  # resolution of is the one mistake this list exists to prevent.
  @planned ["digitaloilsticker.com", "www.digitaloilsticker.com", "digitaloilsticker.net"]

  @doc "Hosts that may serve the application and open a socket, in production."
  @spec production() :: [String.t()]
  def production, do: [@fly_host]

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
