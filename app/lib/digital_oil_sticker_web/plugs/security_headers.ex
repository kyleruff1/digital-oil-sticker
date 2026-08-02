defmodule DigitalOilStickerWeb.Plugs.SecurityHeaders do
  @moduledoc """
  The ADR-0004 header set, on every response (DOS-M09-007 FR-2, FR-3, FR-4).

  Phoenix's `put_secure_browser_headers` ships a much weaker set — a CSP of
  only `base-uri` and `frame-ancestors`, and `referrer-policy:
  strict-origin-when-cross-origin`. That leaves script, style, image, font,
  connect, form-action and object sources entirely unconstrained, which is the
  part of a CSP that actually stops an injected script from running or
  exfiltrating.

  ## The nonce, and why there is one

  ADR-0004 prohibits `'unsafe-inline'` in every directive, and FR-2 calls a
  blanket relaxation a release blocker. But the root layout carries one inline
  script — the theme bootstrap, which must run before first paint or the page
  flashes the wrong theme. The two are reconciled the way FR-2 requires: a
  per-request nonce, generated here, consumed by that one script tag.

  The nonce is 16 bytes of `crypto.strong_rand_bytes`, fresh per request. It is
  not a secret and not an identifier — it changes every response, so it cannot
  correlate two visits (INV-26).

  ## Why this replaces `put_secure_browser_headers` rather than joining it

  Both set a CSP, so running both served TWO policies — and the one actually
  being ENFORCED was Phoenix's weak default while ours sat in report-only. That
  is worse than either alone: it reads like a policy is in force, and the one
  in force constrains almost nothing. Found by curling the deployment, not by
  reading the code. This plug now owns every header in the set, and it sits at
  the endpoint so the API routes get them too — the router pipeline only covers
  `:browser`.

  ## Report-only first

  FR-3 requires the policy ship in report-only mode, be reviewed, and only then
  enforce. `enforce: true` in config flips it. Both modes send the same policy,
  so what gets reviewed is what gets enforced.
  """
  @behaviour Plug

  import Plug.Conn

  alias DigitalOilStickerWeb.Hosts

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    nonce = generate_nonce()

    conn
    |> assign(:csp_nonce, nonce)
    |> put_resp_header(csp_header_name(), policy(nonce))
    |> put_resp_header("referrer-policy", "no-referrer")
    |> put_resp_header("x-content-type-options", "nosniff")
    |> put_resp_header("permissions-policy", permissions_policy())
    |> put_resp_header("x-frame-options", "DENY")
    # Carried over from Phoenix's put_secure_browser_headers, which this plug
    # replaces: legacy Flash/PDF cross-domain policy files.
    |> put_resp_header("x-permitted-cross-domain-policies", "none")
  end

  @doc """
  The policy. Exposed so a test can assert its shape without issuing a request
  and without restating it — a test that keeps its own copy of the policy
  passes while the served header rots.
  """
  @spec policy(String.t()) :: String.t()
  def policy(nonce) do
    Enum.join(
      [
        "default-src 'self'",
        # The nonce is what lets the theme bootstrap run without opening the
        # door to every injected inline script.
        "script-src 'self' 'nonce-#{nonce}'",
        "style-src 'self'",
        # data: is needed for inline SVG/img data URIs; it cannot be used to
        # reach a third party.
        "img-src 'self' data:",
        "font-src 'self'",
        "connect-src #{Hosts.connect_src()}",
        "frame-ancestors 'none'",
        "base-uri 'self'",
        "form-action 'self'",
        "object-src 'none'"
      ],
      "; "
    )
  end

  @doc "Capabilities denied outright. Widening this is a decision, never a quiet edit."
  @spec permissions_policy() :: String.t()
  def permissions_policy do
    Enum.map_join(
      ~w(geolocation camera microphone payment usb magnetometer gyroscope),
      ", ",
      &"#{&1}=()"
    )
  end

  @doc "True once the policy is enforced rather than merely reported."
  @spec enforcing?() :: boolean()
  def enforcing? do
    Application.get_env(:digital_oil_sticker, __MODULE__, [])
    |> Keyword.get(:enforce, false)
  end

  defp csp_header_name do
    if enforcing?(), do: "content-security-policy", else: "content-security-policy-report-only"
  end

  defp generate_nonce, do: 16 |> :crypto.strong_rand_bytes() |> Base.encode64(padding: false)
end
