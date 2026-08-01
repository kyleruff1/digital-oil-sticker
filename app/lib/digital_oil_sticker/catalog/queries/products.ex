defmodule DigitalOilSticker.Catalog.Queries.Products do
  @moduledoc """
  Reads for the RECOMMENDATION path and for filters.

  `search_oils` requires a resolved manufacturer requirement before it will
  name anything (INV-16: a certification or product name alone never implies
  compatibility). With zero `oil_requirements` rows it lists nothing.

  There is no oil-brand browsing here any more. Brands were dropped: many
  products share the same additive chemistry, so a brand list added
  redundancy without adding a fact the app could stand behind. What the user
  picks now is a viscosity grade and a base stock, both from
  `DigitalOilSticker.Catalog.OilModel`.
  """
  import Ecto.Query
  alias DigitalOilSticker.CatalogRepo

  def requirement_exists?(requirement_id) do
    from(r in "oil_requirements", where: r.id == type(^requirement_id, :string), select: r.id)
    |> CatalogRepo.one()
    |> is_binary()
  end

  def fitments_for_configuration(configuration_key) do
    from(f in "filter_fitments",
      join: p in "filter_products",
      on: p.id == f.filter_product_id,
      join: b in "filter_brands",
      on: b.id == p.brand_id,
      where: f.configuration_key == type(^configuration_key, :string),
      select: %{
        id: f.id,
        brand: b.display_name,
        part_number: p.part_number,
        position: f.position,
        qualifiers: f.qualifiers,
        source_id: f.source_id
      },
      order_by: [asc: b.display_name, asc: p.part_number]
    )
    |> CatalogRepo.all()
  end
end
