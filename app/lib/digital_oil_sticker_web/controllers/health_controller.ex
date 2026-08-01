defmodule DigitalOilStickerWeb.HealthController do
  @moduledoc """
  Liveness, readiness, and release identity (DOS-M09-005 FR-6, FR-8, FR-13).

  These are three different questions, and the generator's single `/health`
  conflated the first two — which is how a machine serving a missing or
  writable catalog stays in rotation while cheerfully answering `{"status":"ok"}`.

    * `GET /health` — **liveness**. Is the BEAM up and answering? Nothing else.
      A liveness check that consults dependencies causes restart storms: one
      bad artifact takes down every machine instead of removing them from
      rotation.
    * `GET /ready` — **readiness**. Should this machine receive traffic? Every
      precondition for serving honest answers is checked, and any failure
      returns 503 so the platform rotates the machine out instead of letting it
      serve. Fails **closed**: an unexpected error is not-ready, never ready.
    * `GET /version` — the release identifier. Non-personal build metadata.

  None of the three takes a parameter, reads a session, or emits anything
  derived from the request (INV-4, INV-26), and all three are excluded from
  indexing.
  """
  use DigitalOilStickerWeb, :controller

  alias DigitalOilSticker.Catalog.Metadata
  alias DigitalOilSticker.Release

  @doc "Liveness: the process answered. Deliberately checks nothing else."
  def health(conn, _params) do
    conn
    |> noindex()
    |> json(%{status: "ok"})
  end

  @doc """
  Readiness. Reports every check by name, so a 503 says which precondition
  failed — a bare "not ready" is not actionable at 3am.
  """
  def ready(conn, _params) do
    checks = run_checks()
    ready? = Enum.all?(checks, fn {_name, result} -> result.ok end)

    conn
    |> noindex()
    |> put_status(if(ready?, do: :ok, else: :service_unavailable))
    |> json(%{
      status: if(ready?, do: "ready", else: "not_ready"),
      checks: Map.new(checks, fn {name, r} -> {name, Map.take(r, [:ok, :detail])} end)
    })
  end

  @doc "Release identity. Stable field set; no paths, no secrets, no traces."
  def version(conn, _params) do
    conn
    |> noindex()
    |> json(Release.identifier())
  end

  # -- checks ------------------------------------------------------------------

  @doc false
  def run_checks do
    [
      {:catalog_present, check(&catalog_present/0)},
      {:catalog_payload_matches_boot, check(&catalog_payload_matches_boot/0)},
      {:catalog_read_only, check(&catalog_read_only/0)},
      {:catalog_schema_supported, check(&catalog_schema_supported/0)},
      {:catalog_queryable, check(&catalog_queryable/0)},
      {:release_identified, check(&release_identified/0)}
    ]
  end

  # Fail closed. A check that raises is a check that did not pass; treating an
  # exception as "probably fine" is how a broken machine stays in rotation.
  defp check(fun) do
    fun.()
  rescue
    e -> %{ok: false, detail: "check raised #{inspect(e.__struct__)}"}
  catch
    kind, _ -> %{ok: false, detail: "check exited (#{kind})"}
  end

  defp catalog_present do
    case Release.catalog_path() do
      nil -> %{ok: false, detail: "catalog artifact is absent from this machine"}
      _path -> %{ok: true, detail: nil}
    end
  end

  # The artifact was verified against its manifest at image build. This proves
  # nothing has replaced it since — an in-place swap of a read-only file would
  # otherwise stay invisible until someone noticed wrong answers.
  defp catalog_payload_matches_boot do
    expected = boot_payload_sha256()
    actual = Release.catalog_payload_sha256()

    cond do
      expected in [nil, "unknown"] -> %{ok: false, detail: "no boot payload hash was recorded"}
      actual == "unknown" -> %{ok: false, detail: "catalog payload could not be hashed"}
      actual != expected -> %{ok: false, detail: "catalog payload changed since boot"}
      true -> %{ok: true, detail: nil}
    end
  end

  # Asserts the layer that CANNOT be turned off, not the one that can.
  #
  # `PRAGMA query_only` is per-connection and a session can flip it, so reading
  # it proves less than it appears to — a checked-out connection that a test flipped
  # it would report unsafe while the file is still perfectly protected by
  # `mode: :readonly` and 0444 beneath it. What actually matters is that a
  # write is rejected, so that is what is tested. The pragma is reported
  # alongside as diagnostic detail.
  defp catalog_read_only do
    write_rejected? =
      case Ecto.Adapters.SQL.query(
             DigitalOilSticker.CatalogRepo,
             "CREATE TABLE IF NOT EXISTS __readiness_probe__ (x)",
             []
           ) do
        {:error, _} -> true
        {:ok, _} -> false
      end

    pragma =
      case Ecto.Adapters.SQL.query(DigitalOilSticker.CatalogRepo, "PRAGMA query_only", []) do
        {:ok, %{rows: [[value]]}} -> value
        _ -> "unreadable"
      end

    if write_rejected? do
      %{ok: true, detail: nil}
    else
      %{
        ok: false,
        detail: "the catalog accepted a write (PRAGMA query_only = #{inspect(pragma)})"
      }
    end
  end

  defp catalog_schema_supported do
    version = Metadata.schema_version()

    if version in Metadata.supported_schema_versions() do
      %{ok: true, detail: nil}
    else
      %{ok: false, detail: "catalog schema_version #{version} is outside the supported window"}
    end
  end

  # A metadata read proves the file opens; it does not prove the data is
  # usable. One real query against a real table does.
  defp catalog_queryable do
    %{rows: [[count]]} =
      Ecto.Adapters.SQL.query!(
        DigitalOilSticker.CatalogRepo,
        "SELECT count(*) FROM vehicle_configurations",
        []
      )

    if is_integer(count) and count > 0 do
      %{ok: true, detail: nil}
    else
      %{ok: false, detail: "catalog holds no vehicle configurations"}
    end
  end

  defp release_identified do
    id = Release.identifier()

    cond do
      id.catalog_data_version in [nil, "", "unknown"] ->
        %{ok: false, detail: "catalog data_version is unknown"}

      # A deployed machine must know its own commit. Locally it will not, and
      # that is fine — the clause only bites where FLY_MACHINE_ID exists.
      System.get_env("FLY_MACHINE_ID") not in [nil, ""] and id.git_sha in [nil, "", "unknown"] ->
        %{ok: false, detail: "deployed image carries no git sha"}

      true ->
        %{ok: true, detail: nil}
    end
  end

  # Recorded once at boot, so the later comparison has something trustworthy to
  # compare against.
  defp boot_payload_sha256 do
    :persistent_term.get({__MODULE__, :boot_payload_sha256}, nil)
  end

  @doc false
  def record_boot_payload_sha256 do
    :persistent_term.put({__MODULE__, :boot_payload_sha256}, Release.catalog_payload_sha256())
  end

  defp noindex(conn) do
    conn
    |> put_resp_header("x-robots-tag", "noindex, nofollow")
    |> put_resp_header("cache-control", "no-store")
  end
end
