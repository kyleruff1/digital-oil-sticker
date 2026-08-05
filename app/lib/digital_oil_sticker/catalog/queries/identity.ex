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

  @doc """
  Human-readable labels for a configuration_key — year, make display name,
  model display name, trim. Joins across `makes` and `models` so the caller
  gets one row of strings rather than a pair of UUIDs it then has to resolve.

  Returns `nil` if the configuration_key does not match a row in the current
  catalog. That includes both mistyped keys and keys from a code emitted by
  an OLDER catalog whose configuration_key has since been retired — the
  caller distinguishes these by presence, not by exception.

  Used by ScanLive to render "2020 Ford F-150 · Lariat" above the sticker
  when a QR code is scanned. Not routed through the facade because it
  produces a display-only projection — no INV-11 status, no cursors, no
  provenance — and adding a facade function for a display helper would
  spread the vocabulary for no gain.
  """
  @spec get_configuration_labels(String.t()) ::
          %{
            year: integer(),
            make: String.t(),
            model: String.t(),
            trim: String.t() | nil
          }
          | nil
  def get_configuration_labels(key) when is_binary(key) do
    from(c in "vehicle_configurations",
      join: mk in "makes",
      on: mk.id == c.make_id,
      join: mo in "models",
      on: mo.id == c.model_id,
      where: c.configuration_key == type(^key, :string),
      select: %{
        year: c.model_year,
        make: mk.display_name,
        model: mo.display_name,
        trim: c.trim
      }
    )
    |> CatalogRepo.one()
  end

  def get_configuration_labels(_), do: nil

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

  @doc """
  AC-4 parent-existence check: does the `(year, make_id)` pair appear in any
  configuration row? Used by the facade to reject a fabricated `make_id` with
  `:unsupported` instead of letting the join silently answer with `[]`. Uses
  `LIMIT 1` so it stays constant-time regardless of matching row count.
  """
  def make_exists?(year, make_id) do
    from(c in "vehicle_configurations",
      where: c.model_year == type(^year, :integer) and c.make_id == type(^make_id, :string),
      select: 1,
      limit: 1
    )
    |> CatalogRepo.one()
    |> case do
      nil -> false
      1 -> true
    end
  end

  @doc """
  AC-4 parent-existence check for the model level: does the
  `(year, make_id, model_id)` triple appear in any configuration row? Same
  contract as `make_exists?/2`, applied one cascade level deeper.
  """
  def model_exists?(year, make_id, model_id) do
    from(c in "vehicle_configurations",
      where:
        c.model_year == type(^year, :integer) and c.make_id == type(^make_id, :string) and
          c.model_id == type(^model_id, :string),
      select: 1,
      limit: 1
    )
    |> CatalogRepo.one()
    |> case do
      nil -> false
      1 -> true
    end
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
