defmodule DigitalOilStickerWeb.Plugs.ClientIP do
  @moduledoc """
  Resolve the client IP behind Fly's proxy, for rate limiting only
  (DOS-M09-007 FR-8, INV-26).

  Every request arrives from Fly's proxy, so `conn.remote_ip` is the proxy, not
  the caller — rate limiting on it would throttle the whole internet as one
  client. Fly sets `fly-client-ip` to the real peer.

  ## Why this trusts a header, and when that is safe

  A forwarded header is caller-controlled and normally worthless. It is
  trustworthy here for one specific reason: this app is only reachable through
  Fly's proxy, which **overwrites** `fly-client-ip` on every request rather
  than appending to it. A client that sends its own is ignored.

  That reasoning stops being true the moment the app is reachable directly, so
  the header is only trusted when `FLY_APP_NAME` is present — running outside
  Fly falls back to `remote_ip` rather than believing a header nobody is
  overwriting.

  ## What is done with the address

  It is hashed with a boot-time salt before it is used as a bucket key, and the
  hash never leaves memory. The full address is never stored, never logged, and
  never put in a response (FR-8, FR-11). The salt is regenerated per boot, so
  the same client is not correlatable across deploys.
  """
  @behaviour Plug

  import Plug.Conn

  @salt_key {__MODULE__, :salt}

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    assign(conn, :client_key, client_key(conn))
  end

  @doc """
  A stable-within-this-boot key for one client. Not reversible to an address,
  and not stable across deploys — enough to rate limit, not enough to track.
  """
  @spec client_key(Plug.Conn.t()) :: binary()
  def client_key(conn) do
    :sha256
    |> :crypto.hash([salt(), raw_address(conn)])
    |> Base.encode16(case: :lower)
    |> binary_part(0, 32)
  end

  # Exposed for the test that proves the header is ignored off-Fly.
  @doc false
  def raw_address(conn) do
    if behind_fly_proxy?() do
      case get_req_header(conn, "fly-client-ip") do
        [ip | _] when is_binary(ip) and ip != "" -> ip
        _ -> remote_ip_string(conn)
      end
    else
      remote_ip_string(conn)
    end
  end

  defp behind_fly_proxy?, do: System.get_env("FLY_APP_NAME") not in [nil, ""]

  defp remote_ip_string(%{remote_ip: ip}) when is_tuple(ip), do: ip |> :inet.ntoa() |> to_string()
  defp remote_ip_string(_), do: "unknown"

  # Boot-time salt: without it the hash is a rainbow-table lookup away from the
  # address, and stable across deploys, which would make it a tracking key.
  defp salt do
    case :persistent_term.get(@salt_key, nil) do
      nil ->
        salt = :crypto.strong_rand_bytes(32)
        :persistent_term.put(@salt_key, salt)
        salt

      salt ->
        salt
    end
  end
end
