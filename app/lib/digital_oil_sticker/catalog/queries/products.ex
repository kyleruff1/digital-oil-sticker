defmodule DigitalOilSticker.Catalog.Queries.Products do
  @moduledoc """
  Oil product reads. Two distinct surfaces (rev-2 policy):

  * `search_oils` — the RECOMMENDATION path: requires a resolved requirement
    and intersects claims against it. With zero `oil_requirements` rows this
    never lists anything (INV-16: certification/name alone never implies
    compatibility).
  * `brands_page`/`families_page` — the BROWSING path for the log form:
    plain-text identification of products a user may record, carrying no
    compatibility meaning at all.
  """
  import Ecto.Query
  alias DigitalOilSticker.CatalogRepo
  alias DigitalOilSticker.Catalog.{Cursor, Selector}

  def brands_page(%Selector{} = sel) do
    base =
      from(b in "oil_brands",
        select: %{
          id: b.id,
          display_name: b.display_name,
          normalized_name: b.normalized_name,
          source_observed_at: b.source_observed_at,
          source_id: b.source_id
        },
        order_by: [asc: b.normalized_name, asc: b.id]
      )

    paginate(base, sel, fn q, [norm, id] ->
      where(q, [b], fragment("(?, ?) > (?, ?)", b.normalized_name, b.id, ^norm, ^id))
    end, fn row -> [row.normalized_name, row.id] end)
  end

  def families_page(%Selector{oil_brand_id: brand_id} = sel) do
    base =
      from(p in "oil_products",
        where: p.brand_id == type(^brand_id, :string),
        select: %{
          id: p.id,
          product_family: p.product_family,
          product_variant: p.product_variant,
          display_name: p.display_name,
          normalized_name: p.normalized_name,
          product_url: p.product_url,
          source_observed_at: p.source_observed_at,
          verification_status: p.verification_status,
          source_id: p.source_id
        },
        order_by: [asc: p.normalized_name, asc: p.id]
      )

    paginate(base, sel, fn q, [norm, id] ->
      where(q, [p], fragment("(?, ?) > (?, ?)", p.normalized_name, p.id, ^norm, ^id))
    end, fn row -> [row.normalized_name, row.id] end)
  end

  def claims_for_product(product_id) do
    from(c in "oil_product_claims",
      where: c.product_id == type(^product_id, :string),
      select: %{
        id: c.id,
        claim_type: c.claim_type,
        claim_code: c.claim_code,
        claim_source: c.claim_source,
        observed_at: c.observed_at,
        verification_status: c.verification_status,
        source_id: c.source_id
      },
      order_by: [asc: c.claim_type, asc: c.claim_code]
    )
    |> CatalogRepo.all()
  end

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

  defp paginate(base, %Selector{} = sel, apply_after, key_fun) do
    with {:ok, query} <- maybe_after(base, sel, apply_after) do
      rows = query |> limit(^(sel.page_size + 1)) |> CatalogRepo.all()

      if length(rows) > sel.page_size do
        page = Enum.take(rows, sel.page_size)
        {:ok, page, Cursor.encode(key_fun.(List.last(page)), sel)}
      else
        {:ok, rows, nil}
      end
    end
  end

  defp maybe_after(base, %Selector{cursor: nil}, _apply_after), do: {:ok, base}

  defp maybe_after(base, %Selector{cursor: cursor} = sel, apply_after) do
    case Cursor.decode(cursor, sel) do
      {:ok, components} -> {:ok, apply_after.(base, components)}
      {:error, _} = err -> err
    end
  end
end
