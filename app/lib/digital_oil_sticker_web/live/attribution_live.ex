defmodule DigitalOilStickerWeb.AttributionLive do
  @moduledoc """
  DOS-M09-010 AC-10 — the factual-use attribution surface. Lists every
  `data_sources` row the catalog was compiled from, so the six-axis
  disposition (`copyright_basis` / `acquisition_basis` / `redistribution_basis`
  / `trademark_posture` / `claim_posture` / `review_status`) for each source
  is public, alongside the provider's own required attribution string and
  the canonical URL of the dataset.

  The page leads with `Copy.no_affiliation()` verbatim — that string is the
  policy-mandated statement in `FACTUAL_USE_AND_MARKS_POLICY.md`
  ("No-affiliation statement") and this is the second surface (after
  `/settings/storage`) that renders it.
  """
  use DigitalOilStickerWeb, :live_view

  alias DigitalOilSticker.Catalog.Queries.Provenance
  alias DigitalOilStickerWeb.Copy
  alias DigitalOilStickerWeb.Layouts

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Attribution")
     |> assign(:sources, Provenance.all_sources())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      unsaved_writes={@unsaved_writes}
      read_only={@read_only}
      conflict_notice={@conflict_notice}
      storage_mode={@storage_mode}
    >
      <div class="mx-auto max-w-3xl">
        <h1 class="text-2xl font-bold">Attribution</h1>

        <p class="mt-4 text-sm leading-relaxed text-base-content/80" data-test="no-affiliation">
          {Copy.no_affiliation()}
        </p>

        <ul class="mt-8 space-y-4" data-test="sources-list">
          <li
            :for={s <- @sources}
            class="rounded border p-4"
            data-test="source-card"
            data-source-id={s.id}
          >
            <h2 class="font-semibold" data-test="source-provider">{s.provider}</h2>
            <p class="text-sm text-base-content/80" data-test="source-dataset">{s.dataset_name}</p>

            <p class="mt-2 text-sm leading-relaxed" data-test="source-attribution">
              {attribution_text(s)}
            </p>

            <p
              :if={present?(s.retrieved_at)}
              class="mt-2 text-xs text-base-content/70"
              data-test="source-retrieved-at"
            >
              {Copy.as_of(s.retrieved_at)}
            </p>

            <p class="mt-1 text-xs">
              <a
                href={s.canonical_url}
                class="link link-primary break-all"
                rel="noopener noreferrer"
                data-test="source-url"
              >
                {s.canonical_url}
              </a>
            </p>

            <dl
              class="mt-3 grid grid-cols-1 gap-x-4 gap-y-1 text-xs text-base-content/80 sm:grid-cols-2"
              data-test="source-dispositions"
            >
              <div>
                <dt class="inline font-semibold">Copyright basis:</dt>
                <dd class="inline">{s.copyright_basis}</dd>
              </div>
              <div>
                <dt class="inline font-semibold">Acquisition basis:</dt>
                <dd class="inline">{s.acquisition_basis}</dd>
              </div>
              <div>
                <dt class="inline font-semibold">Redistribution basis:</dt>
                <dd class="inline">{s.redistribution_basis}</dd>
              </div>
              <div>
                <dt class="inline font-semibold">Trademark posture:</dt>
                <dd class="inline">{s.trademark_posture}</dd>
              </div>
              <div>
                <dt class="inline font-semibold">Claim posture:</dt>
                <dd class="inline">{s.claim_posture}</dd>
              </div>
              <div>
                <dt class="inline font-semibold">Review status:</dt>
                <dd class="inline">{s.review_status}</dd>
              </div>
            </dl>
          </li>
        </ul>
      </div>
    </Layouts.app>
    """
  end

  # Prefer the provider's web-attribution string when they gave one; otherwise
  # the long-form attribution_text. Both columns are populated per
  # tools/catalog/src/compile/production.mjs `sourceRow/1`; attribution_text is
  # NOT NULL, web_attribution_text is nullable.
  defp attribution_text(%{web_attribution_text: t}) when is_binary(t) and t != "", do: t
  defp attribution_text(%{attribution_text: t}), do: t

  defp present?(nil), do: false
  defp present?(""), do: false
  defp present?(_), do: true
end
