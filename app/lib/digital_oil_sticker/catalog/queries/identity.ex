defmodule DigitalOilSticker.Catalog.Queries.Identity do
  @moduledoc """
  Schemaless identity queries (years/makes/models/configurations) with total
  ordering and keyset pagination. Explicit selects; bound parameters only —
  string interpolation into SQL is impossible by construction.
  """
  import Ecto.Query
  alias DigitalOilSticker.CatalogRepo
  alias DigitalOilSticker.Catalog.{Cursor, Selector}

  def years do
    from(c in "vehicle_configurations",
      select: c.model_year,
      distinct: true,
      order_by: [asc: c.model_year]
    )
    |> CatalogRepo.all()
  end

  def makes_page(%Selector{year: year} = sel) do
    base =
      from(c in "vehicle_configurations",
        join: m in "makes",
        on: m.id == c.make_id,
        where: c.model_year == type(^year, :integer),
        select: %{
          id: m.id,
          display_name: m.display_name,
          normalized_name: m.normalized_name,
          support_status: m.support_status
        },
        distinct: true,
        order_by: [asc: m.normalized_name, asc: m.id]
      )

    paginate(
      base,
      sel,
      fn q, [norm, id] ->
        where(q, [c, m], fragment("(?, ?) > (?, ?)", m.normalized_name, m.id, ^norm, ^id))
      end,
      fn row -> [row.normalized_name, row.id] end
    )
  end

  def models_page(%Selector{year: year, make_id: make_id} = sel) do
    base =
      from(c in "vehicle_configurations",
        join: mo in "models",
        on: mo.id == c.model_id,
        where: c.model_year == type(^year, :integer) and c.make_id == type(^make_id, :string),
        select: %{
          id: mo.id,
          display_name: mo.display_name,
          normalized_name: mo.normalized_name
        },
        distinct: true,
        order_by: [asc: mo.normalized_name, asc: mo.id]
      )

    paginate(
      base,
      sel,
      fn q, [norm, id] ->
        where(q, [c, mo], fragment("(?, ?) > (?, ?)", mo.normalized_name, mo.id, ^norm, ^id))
      end,
      fn row -> [row.normalized_name, row.id] end
    )
  end

  def configurations_page(%Selector{year: year, make_id: make_id, model_id: model_id} = sel) do
    base =
      from(c in "vehicle_configurations",
        where:
          c.model_year == type(^year, :integer) and c.make_id == type(^make_id, :string) and
            c.model_id == type(^model_id, :string),
        select: %{
          configuration_key: c.configuration_key,
          model_year: c.model_year,
          trim: c.trim,
          series: c.series,
          body_class: c.body_class,
          drive_type: c.drive_type,
          fuel_primary: c.fuel_primary,
          fuel_secondary: c.fuel_secondary,
          electrification_level: c.electrification_level,
          engine_cylinders: c.engine_cylinders,
          displacement_l: c.displacement_l,
          engine_descriptor: c.engine_descriptor,
          transmission: c.transmission,
          completeness_code: c.completeness_code,
          support_status: c.support_status,
          engine_oil_service: c.engine_oil_service,
          engine_class_code: c.engine_class_code,
          source_id: c.source_id
        },
        order_by: [asc: c.configuration_key]
      )

    paginate(
      base,
      sel,
      fn q, [key] ->
        where(q, [c], c.configuration_key > ^key)
      end,
      fn row -> [row.configuration_key] end
    )
  end

  def get_configuration(key) do
    from(c in "vehicle_configurations",
      where: c.configuration_key == type(^key, :string),
      select: %{
        configuration_key: c.configuration_key,
        model_year: c.model_year,
        make_id: c.make_id,
        model_id: c.model_id,
        trim: c.trim,
        series: c.series,
        body_class: c.body_class,
        drive_type: c.drive_type,
        fuel_primary: c.fuel_primary,
        fuel_secondary: c.fuel_secondary,
        electrification_level: c.electrification_level,
        engine_cylinders: c.engine_cylinders,
        displacement_l: c.displacement_l,
        engine_descriptor: c.engine_descriptor,
        transmission: c.transmission,
        completeness_code: c.completeness_code,
        support_status: c.support_status,
        engine_oil_service: c.engine_oil_service,
        engine_class_code: c.engine_class_code,
        source_id: c.source_id
      }
    )
    |> CatalogRepo.one()
  end

  def count_distinct_makes(year) do
    from(c in "vehicle_configurations",
      where: c.model_year == type(^year, :integer),
      select: count(c.make_id, :distinct)
    )
    |> CatalogRepo.one()
  end

  def count_distinct_models(year, make_id) do
    from(c in "vehicle_configurations",
      where: c.model_year == type(^year, :integer) and c.make_id == type(^make_id, :string),
      select: count(c.model_id, :distinct)
    )
    |> CatalogRepo.one()
  end

  # Keyset pagination: fetch page_size + 1; the extra row's presence yields the
  # next cursor and is discarded.
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
