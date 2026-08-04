defmodule DigitalOilSticker.Catalog.Queries.Provenance do
  @moduledoc "Source rows for provenance display (attribution, retrieved/verified dates)."
  import Ecto.Query
  alias DigitalOilSticker.CatalogRepo

  def source(source_id) do
    from(s in "data_sources",
      where: s.id == type(^source_id, :string),
      select: %{
        id: s.id,
        provider: s.provider,
        dataset_name: s.dataset_name,
        canonical_url: s.canonical_url,
        source_version: s.source_version,
        retrieved_at: s.retrieved_at,
        verified_at: s.verified_at,
        attribution_text: s.attribution_text,
        web_attribution_text: s.web_attribution_text,
        copyright_basis: s.copyright_basis,
        acquisition_basis: s.acquisition_basis,
        redistribution_basis: s.redistribution_basis,
        review_status: s.review_status
      }
    )
    |> CatalogRepo.one()
  end

  def sources(source_ids) when is_list(source_ids) do
    source_ids |> Enum.uniq() |> Enum.map(&source/1) |> Enum.reject(&is_nil/1)
  end

  def all_sources do
    from(s in "data_sources",
      select: %{
        id: s.id,
        provider: s.provider,
        dataset_name: s.dataset_name,
        canonical_url: s.canonical_url,
        retrieved_at: s.retrieved_at,
        attribution_text: s.attribution_text,
        web_attribution_text: s.web_attribution_text,
        copyright_basis: s.copyright_basis,
        acquisition_basis: s.acquisition_basis,
        redistribution_basis: s.redistribution_basis,
        trademark_posture: s.trademark_posture,
        claim_posture: s.claim_posture,
        review_status: s.review_status
      },
      order_by: [asc: s.provider, asc: s.id]
    )
    |> CatalogRepo.all()
  end
end
