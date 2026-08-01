defmodule DigitalOilSticker.Catalog.Result do
  @moduledoc """
  The uniform result envelope every catalog function returns (DOS-M09-004):
  an INV-11 status, typed data, provenance, qualifiers, catalog versions,
  pagination cursor, and an honest total (`total_known?: false` means the
  count is unknown — never guessed).
  """
  alias DigitalOilSticker.Catalog.Metadata

  @enforce_keys [:status, :data]
  defstruct [
    :status,
    :data,
    provenance: [],
    qualifiers: [],
    data_version: nil,
    schema_version: nil,
    cursor: nil,
    total_known?: false,
    total: nil
  ]

  @typedoc """
  INV-11 statuses describe how well SOURCED data covers a vehicle.
  `:our_model` is separate on purpose: it means the answer came from our own
  oil model, which is not a manufacturer claim and never upgrades a vehicle's
  support status.
  """
  @type status ::
          :identity_only
          | :schedule_supported
          | :full_product_supported
          | :not_applicable
          | :unsupported
          | :our_model
  @type t :: %__MODULE__{}

  def new(status, data, opts \\ []) do
    %__MODULE__{
      status: status,
      data: data,
      provenance: Keyword.get(opts, :provenance, []),
      qualifiers: Keyword.get(opts, :qualifiers, []),
      data_version: Metadata.data_version(),
      schema_version: Metadata.schema_version(),
      cursor: Keyword.get(opts, :cursor),
      total_known?: Keyword.get(opts, :total_known?, false),
      total: Keyword.get(opts, :total)
    }
  end
end
