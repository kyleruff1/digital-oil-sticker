defmodule DigitalOilStickerWeb.Components.Badges do
  @moduledoc """
  Provenance / support-status / precision badges. Distinguished by text AND
  icon AND border weight — never color alone (accessibility). Manual entries
  are never relabeled as verified (INV-16).
  """
  use Phoenix.Component
  alias DigitalOilStickerWeb.Copy

  attr :mode, :atom, values: [:catalog, :manual], required: true

  def provenance_badge(assigns) do
    ~H"""
    <span
      :if={@mode == :catalog}
      class="inline-flex items-center gap-1 rounded border border-solid px-1.5 py-0.5 text-xs"
      data-provenance="catalog"
    >
      <span aria-hidden="true">▤</span> {Copy.from_catalog()}
    </span>
    <span
      :if={@mode == :manual}
      class="inline-flex items-center gap-1 rounded border-2 border-dashed px-1.5 py-0.5 text-xs"
      data-provenance="manual"
    >
      <span aria-hidden="true">✎</span> {Copy.user_entered()}
    </span>
    """
  end

  attr :status, :atom,
    values: [
      :identity_only,
      :schedule_supported,
      :full_product_supported,
      :not_applicable,
      :unsupported
    ],
    required: true

  def support_badge(assigns) do
    ~H"""
    <span
      class="inline-flex items-center gap-1 rounded border px-1.5 py-0.5 text-xs"
      data-support={@status}
    >
      {support_label(@status)}
    </span>
    """
  end

  defp support_label(:identity_only), do: "Identity only — #{Copy.source_unavailable()}"
  defp support_label(:schedule_supported), do: "Schedule available"
  defp support_label(:full_product_supported), do: "Schedule and products available"
  defp support_label(:not_applicable), do: Copy.not_applicable_ev()
  defp support_label(:unsupported), do: "Unsupported"

  def precision_badge(assigns) do
    ~H"""
    <span
      class="inline-flex items-center gap-1 rounded border px-1.5 py-0.5 text-xs"
      data-precision="unverified"
    >
      {Copy.precision_unverified()}
    </span>
    """
  end

  # The "Factory recommendation" badge. Ready but INERT until DOS-M03-007
  # activation (ADR-0007 lane b) populates an OEM-sourced value on the record
  # this badge annotates. The three non-negotiables from
  # RECOMMENDATION_CLAIMS_POLICY.md §"Factory recommendation label" are
  # enforced here: the badge (a) only ever renders when the CALLER has an
  # OEM-provenance-backed value to certify — no attr signals it, callers gate
  # it with `:if={...}`; (b) renders NO source information — no publisher,
  # no URL, no revision date — that stays in our internal source register;
  # (c) is a badge next to the specific value it certifies, not sentence
  # text. Emerald border-double weight distinguishes it visually from the
  # other badges without color-alone (border style AND text differ); no
  # third-party mark or certification-shape icon is used (the badges
  # @moduledoc rule + FACTUAL_USE_AND_MARKS_POLICY "Never copy" list).
  def factory_recommendation_badge(assigns) do
    ~H"""
    <span
      class="inline-flex items-center gap-1 rounded border-2 border-double border-emerald-700 px-1.5 py-0.5 text-xs"
      data-factory-recommendation="true"
    >
      {Copy.factory_recommendation_label()}
    </span>
    """
  end
end
