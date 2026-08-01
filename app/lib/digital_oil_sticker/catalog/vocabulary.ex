defmodule DigitalOilSticker.Catalog.Vocabulary do
  @moduledoc """
  The closed selector vocabulary (DOS-M09-004 FR-2/INV-26), expressed as data.
  Every field a catalog query can accept is declared here; every LiveView
  event's payload-key allowlist is declared here; nothing else may cross the
  boundary. Unknown keys are REJECTED, never stripped. The year range comes
  from catalog_metadata at boot — never hardcoded.
  """

  @type spec ::
          {:integer, Range.t() | :window_years}
          | {:catalog_id, atom()}
          | {:enum, [atom()]}
          | {:cursor}

  @field_specs %{
    year: {:integer, :window_years},
    make_id: {:catalog_id, :make},
    model_id: {:catalog_id, :model},
    configuration_key: {:catalog_id, :vehicle_configuration},
    requirement_id: {:catalog_id, :oil_requirement},
    filter_product_id: {:catalog_id, :filter_product},
    condition: {:enum, [:normal, :severe, :flexible]},
    # Our own oil model. These are closed sets held in the catalog artifact,
    # so validation is a membership test against the loaded model rather than
    # a shape test — an unknown code is rejected, never passed through.
    engine_class_code: {:catalog_code, :engine_class},
    base_stock_code: {:catalog_code, :oil_base_stock},
    grade_code: {:catalog_code, :oil_grade},
    service_condition: {:catalog_code, :service_condition},
    entity_type:
      {:enum, [:configuration, :schedule, :requirement, :oil_product, :filter_fitment]},
    entity_key: {:catalog_id, :any},
    cursor: {:cursor},
    page_size: {:integer, 1..200}
  }

  @key_atoms Map.new(@field_specs, fn {k, _} -> {Atom.to_string(k), k} end)

  @function_specs %{
    list_years: %{required: [], optional: []},
    list_makes: %{required: [:year], optional: [:cursor, :page_size]},
    list_models: %{required: [:year, :make_id], optional: [:cursor, :page_size]},
    list_configurations: %{
      required: [:year, :make_id, :model_id],
      optional: [:cursor, :page_size]
    },
    get_configuration: %{required: [:configuration_key], optional: []},
    get_schedules: %{required: [:configuration_key], optional: [:condition]},
    get_lubricant_requirements: %{required: [:configuration_key], optional: []},
    search_oils: %{required: [:requirement_id], optional: [:cursor, :page_size]},
    list_oil_grades: %{required: [], optional: [:engine_class_code]},
    list_oil_base_stocks: %{required: [], optional: []},
    get_oil_interval: %{
      required: [:base_stock_code],
      optional: [:engine_class_code, :service_condition]
    },
    list_compatible_filters: %{required: [:configuration_key], optional: [:cursor, :page_size]},
    get_provenance: %{required: [:entity_type, :entity_key], optional: []}
  }

  # LiveView event name -> allowed payload keys (strings, as they arrive on the
  # wire). Asserted by test; the source-scan gate checks templates against it.
  @event_allowlist %{
    "catalog:select_year" => ["year"],
    "catalog:select_make" => ["year", "make_id"],
    "catalog:select_model" => ["year", "make_id", "model_id"],
    "catalog:select_configuration" => ["configuration_key"],
    "catalog:resolve_requirements" => ["configuration_key"],
    "catalog:resolve_products" => ["requirement_id", "cursor", "page_size"],
    "catalog:resolve_filters" => ["configuration_key", "cursor", "page_size"],
    "catalog:page" => ["cursor", "page_size"],
    "catalog:list_oil_grades" => ["engine_class_code"],
    "catalog:select_base_stock" => ["base_stock_code", "engine_class_code", "service_condition"],
    "catalog:select_service_condition" => [
      "service_condition",
      "base_stock_code",
      "engine_class_code"
    ]
  }

  def field_specs, do: @field_specs
  def function_specs, do: @function_specs
  def event_allowlist, do: @event_allowlist
  def all_fields, do: Map.keys(@field_specs)

  @doc "String key -> vocabulary atom, via a compile-time map. Never String.to_atom/1."
  def key_atom(string_key), do: Map.fetch(@key_atoms, string_key)
end
