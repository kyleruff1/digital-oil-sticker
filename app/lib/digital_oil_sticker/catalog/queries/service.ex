defmodule DigitalOilSticker.Catalog.Queries.Service do
  @moduledoc """
  Schedule and lubricant-requirement reads. In build 1 these tables carry
  zero rows by design (no licensed source), so results are honestly empty —
  the Status module turns that into `identity_only`, never a default.
  """
  import Ecto.Query
  alias DigitalOilSticker.CatalogRepo
  alias DigitalOilSticker.Catalog.Selector

  def schedules(%Selector{configuration_key: key} = sel) do
    base =
      from(s in "maintenance_schedules",
        where: s.configuration_key == type(^key, :string),
        select: %{
          id: s.id,
          condition: s.condition,
          interval_miles: s.interval_miles,
          interval_months: s.interval_months,
          oil_life_monitor: s.oil_life_monitor,
          source_locator: s.source_locator,
          source_page: s.source_page,
          source_effective_date: s.source_effective_date,
          verification_state: s.verification_state,
          source_id: s.source_id
        },
        order_by: [asc: s.condition, asc: s.id]
      )

    case sel.condition do
      nil -> CatalogRepo.all(base)
      condition -> base |> where([s], s.condition == ^Atom.to_string(condition)) |> CatalogRepo.all()
    end
  end

  def requirements(%Selector{configuration_key: key}) do
    from(r in "oil_requirements",
      where: r.configuration_key == type(^key, :string),
      select: %{
        id: r.id,
        required_viscosity: r.required_viscosity,
        acceptable_viscosities: r.acceptable_viscosities,
        api_service_category: r.api_service_category,
        oem_specification: r.oem_specification,
        capacity_value: r.capacity_value,
        capacity_unit: r.capacity_unit,
        capacity_with_filter: r.capacity_with_filter,
        applicability_conditions: r.applicability_conditions,
        source_locator: r.source_locator,
        source_page: r.source_page,
        source_effective_date: r.source_effective_date,
        source_id: r.source_id
      },
      order_by: [asc: r.id]
    )
    |> CatalogRepo.all()
  end
end
