defmodule DigitalOilSticker.LocalStore.Envelope do
  @moduledoc """
  The `dos_local` payload envelope shared by hydrate, write-back, and export
  (DOS-M09-001 FR-17, DOS-M09-002 FR-2).

  One envelope shape carries `envelope`, `schema_version`, `seq`, `tab_id`,
  `generated_at`, and `data` (the record collections keyed by store name).
  An optional `storage` sibling carries transient session context (quota,
  persistence grant, availability probes); it is held on the decoded struct
  for the session but is never part of any write-back or export payload.

  The payload is untrusted client input: unknown top-level keys are rejected
  by name, and unknown collection names inside `data` are likewise rejected.
  Unknown keys *within* a record are not this module's concern — they are
  preserved by `DigitalOilSticker.LocalStore.Schema.V1` (forward
  compatibility, AC-9).
  """

  @enforce_keys [:schema_version, :seq, :tab_id, :generated_at, :data]
  defstruct [:schema_version, :seq, :tab_id, :generated_at, :data, :storage]

  @type t :: %__MODULE__{
          schema_version: pos_integer(),
          seq: non_neg_integer(),
          tab_id: binary(),
          generated_at: binary(),
          data: map(),
          storage: map() | nil
        }

  @current_schema_version 1

  @envelope_marker "dos_local"

  @required_top_level_keys ~w(envelope schema_version seq tab_id generated_at data)
  @allowed_top_level_keys @required_top_level_keys ++ ["storage"]

  @list_collections ~w(vehicles events readings usage reminders)
  @singleton_collections ~w(meta prefs)
  @collections @singleton_collections ++ @list_collections

  @doc "The logical schema version this deployment writes."
  @spec current_schema_version() :: pos_integer()
  def current_schema_version, do: @current_schema_version

  @doc "The collection names `data` may carry, in canonical order."
  @spec collections() :: [String.t()]
  def collections, do: ~w(meta vehicles events readings usage reminders prefs)

  @doc """
  Decodes an untrusted map into an `%Envelope{}`.

  Returns `{:ok, envelope}` or one of:

    * `{:error, :not_an_envelope}` — not a map, missing the `"envelope" =>
      "dos_local"` marker, or a required field is missing or of the wrong type
    * `{:error, {:unknown_top_level_key, key}}` — any top-level key outside
      the envelope shape, or an unknown collection name inside `data`
    * `{:error, :bad_version}` — `schema_version` is not a positive integer
  """
  @spec decode(term()) ::
          {:ok, t()}
          | {:error, :not_an_envelope | {:unknown_top_level_key, String.t()} | :bad_version}
  def decode(map) when is_map(map) do
    with :ok <- check_marker(map),
         :ok <- check_top_level_keys(map),
         {:ok, schema_version} <- check_version(map),
         :ok <- check_required_present(map),
         {:ok, seq} <- check_seq(map),
         {:ok, tab_id} <- check_binary(map, "tab_id"),
         {:ok, generated_at} <- check_binary(map, "generated_at"),
         {:ok, data} <- check_data(map),
         {:ok, storage} <- check_storage(map) do
      {:ok,
       %__MODULE__{
         schema_version: schema_version,
         seq: seq,
         tab_id: tab_id,
         generated_at: generated_at,
         data: data,
         storage: storage
       }}
    end
  end

  def decode(_other), do: {:error, :not_an_envelope}

  @doc """
  Builds a `local_store:put` instruction payload (DOS-M09-002 FR-12).

  `upserts` is a list of `{store, record}` pairs and `deletes` a list of
  `{store, key}` pairs. The `storage` session context is deliberately not
  representable here: write-back carries records and keys only.
  """
  @spec build_put(binary(), non_neg_integer(), [{String.t(), map()}], [{String.t(), binary()}]) ::
          map()
  def build_put(mutation_id, seq, upserts, deletes)
      when is_binary(mutation_id) and is_integer(seq) and seq >= 0 and
             is_list(upserts) and is_list(deletes) do
    %{
      "mutation_id" => mutation_id,
      "seq" => seq,
      "upserts" =>
        Enum.map(upserts, fn {store, record} when is_binary(store) ->
          %{"store" => store, "record" => record}
        end),
      "deletes" =>
        Enum.map(deletes, fn {store, key} when is_binary(store) ->
          %{"store" => store, "key" => key}
        end)
    }
  end

  ## Decode steps

  defp check_marker(%{"envelope" => @envelope_marker}), do: :ok
  defp check_marker(_map), do: {:error, :not_an_envelope}

  defp check_top_level_keys(map) do
    case Enum.find(Map.keys(map), &(&1 not in @allowed_top_level_keys)) do
      nil -> :ok
      key -> {:error, {:unknown_top_level_key, key}}
    end
  end

  defp check_required_present(map) do
    if Enum.all?(@required_top_level_keys, &Map.has_key?(map, &1)) do
      :ok
    else
      {:error, :not_an_envelope}
    end
  end

  defp check_version(%{"schema_version" => v}) when is_integer(v) and v > 0, do: {:ok, v}
  defp check_version(_map), do: {:error, :bad_version}

  defp check_seq(%{"seq" => seq}) when is_integer(seq) and seq >= 0, do: {:ok, seq}
  defp check_seq(_map), do: {:error, :not_an_envelope}

  defp check_binary(map, key) do
    case Map.fetch(map, key) do
      {:ok, value} when is_binary(value) -> {:ok, value}
      _ -> {:error, :not_an_envelope}
    end
  end

  defp check_data(%{"data" => data}) when is_map(data) do
    with :ok <- check_collection_names(data),
         :ok <- check_collection_shapes(data) do
      {:ok, normalize_data(data)}
    end
  end

  defp check_data(_map), do: {:error, :not_an_envelope}

  defp check_collection_names(data) do
    case Enum.find(Map.keys(data), &(&1 not in @collections)) do
      nil -> :ok
      key -> {:error, {:unknown_top_level_key, key}}
    end
  end

  defp check_collection_shapes(data) do
    bad_list? =
      Enum.any?(@list_collections, fn name ->
        case Map.fetch(data, name) do
          {:ok, value} -> not is_list(value)
          :error -> false
        end
      end)

    if bad_list?, do: {:error, :not_an_envelope}, else: :ok
  end

  # Missing list collections default to []; missing singletons default to nil.
  # Record contents pass through untouched — per-record validation and
  # quarantine belong to Validation/Schema.V1, never to decode.
  defp normalize_data(data) do
    lists = Map.new(@list_collections, fn name -> {name, Map.get(data, name, [])} end)
    singletons = Map.new(@singleton_collections, fn name -> {name, Map.get(data, name)} end)
    Map.merge(lists, singletons)
  end

  defp check_storage(map) do
    case Map.fetch(map, "storage") do
      :error -> {:ok, nil}
      {:ok, storage} when is_map(storage) -> {:ok, storage}
      {:ok, _other} -> {:error, :not_an_envelope}
    end
  end
end
