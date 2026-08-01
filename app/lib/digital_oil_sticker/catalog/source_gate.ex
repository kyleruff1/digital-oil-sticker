defmodule DigitalOilSticker.Catalog.SourceGate do
  @moduledoc """
  Disposition-driven serving gate (rev-2 factual-use policy). A fact domain
  is served only when its catalog feature flag says so; oil-product rows are
  additionally source-gated at compile time (a source with unresolved
  acquisition/redistribution/claim posture contributes zero rows to the
  artifact, so the runtime check is a feature-flag read, not a legal query).
  """
  alias DigitalOilSticker.Catalog.Metadata

  @spec cleared?(atom()) :: boolean()
  def cleared?(:maintenance_schedules), do: Metadata.feature(:schedules) not in ["withheld"]
  def cleared?(:oil_requirements), do: Metadata.feature(:oil_requirements) not in ["withheld"]
  def cleared?(:oil_products), do: Metadata.feature(:oil_products) not in ["withheld", "absent"]
  def cleared?(:filters), do: Metadata.feature(:filters) not in ["withheld"]
end
