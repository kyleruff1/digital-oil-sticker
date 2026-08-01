defmodule DigitalOilSticker.Release do
  @moduledoc """
  What is actually running (DOS-M09-005 FR-8).

  A deployed machine has to be able to answer "which build are you, and which
  data are you serving" without anyone guessing from a version string in
  `mix.exs`. Four independent identities matter, and they move on different
  schedules:

    * the **code** — git commit and app version, baked at image build,
    * the **catalog** — `data_version` and payload hash of the artifact in the
      image, read from the artifact itself at boot rather than from a file that
      could disagree with it,
    * the **client storage contract** — the LocalStore logical schema version,
      because a browser holding newer records than the server must be detected,
    * the **platform** — the Fly release version and image reference, which
      only the running machine knows.

  Everything here is non-personal and safe to expose: it identifies the build,
  never a request, a session, or a user. No path, no secret, no stack trace.
  """

  alias DigitalOilSticker.Catalog.Metadata
  alias DigitalOilSticker.LocalStore.Envelope

  # Baked at image build. `unknown` is honest rather than fatal: a local `mix
  # phx.server` has no build arg, and refusing to boot over that would be
  # theatre. What must never happen is a *deployed* image claiming a commit it
  # is not — hence the build arg, not a runtime `git` call.
  @git_sha System.get_env("GIT_SHA") || "unknown"
  @built_at System.get_env("BUILD_TIMESTAMP") || "unknown"

  @doc """
  The full release identifier. Shape is stable: callers and the release ledger
  depend on these keys existing, so a missing value is the string `"unknown"`
  rather than an absent key.
  """
  @spec identifier() :: map()
  def identifier do
    %{
      app_version: app_version(),
      git_sha: @git_sha,
      built_at: @built_at,
      catalog_data_version: catalog_field(:data_version),
      catalog_schema_version: catalog_field(:schema_version),
      catalog_payload_sha256: catalog_payload_sha256(),
      local_store_schema_version: Envelope.current_schema_version(),
      fly_release_version: env("FLY_MACHINE_VERSION") || env("FLY_RELEASE_VERSION"),
      fly_image_ref: env("FLY_IMAGE_REF"),
      fly_machine_id: env("FLY_MACHINE_ID"),
      fly_region: env("FLY_REGION")
    }
  end

  @doc "True once the identity is specific enough to appear in a release ledger."
  @spec complete?() :: boolean()
  def complete?, do: @git_sha != "unknown" and catalog_field(:data_version) != "unknown"

  def app_version, do: to_string(Application.spec(:digital_oil_sticker, :vsn))
  def git_sha, do: @git_sha

  @doc """
  SHA-256 of the catalog artifact **as it exists on disk right now**, not as a
  manifest claims it was. This is what makes the readiness check meaningful:
  the build verified the artifact against its manifest, and this re-verifies
  that nothing replaced it since.
  """
  @spec catalog_payload_sha256() :: String.t()
  def catalog_payload_sha256 do
    case catalog_path() do
      nil ->
        "unknown"

      path ->
        path
        |> File.stream!(65_536, [])
        |> Enum.reduce(:crypto.hash_init(:sha256), &:crypto.hash_update(&2, &1))
        |> :crypto.hash_final()
        |> Base.encode16(case: :lower)
    end
  rescue
    _ -> "unknown"
  end

  @doc "Absolute path of the catalog artifact this machine has open, or nil."
  @spec catalog_path() :: String.t() | nil
  def catalog_path do
    config = Application.get_env(:digital_oil_sticker, DigitalOilSticker.CatalogRepo, [])

    case Keyword.get(config, :database) do
      path when is_binary(path) -> if File.exists?(path), do: path, else: nil
      _ -> nil
    end
  end

  defp catalog_field(key) do
    Map.get(Metadata.get(), key, "unknown")
  rescue
    # Metadata not yet loaded (boot ordering, or a test without a catalog).
    _ -> "unknown"
  end

  defp env(name) do
    case System.get_env(name) do
      value when is_binary(value) and value != "" -> value
      _ -> nil
    end
  end
end
