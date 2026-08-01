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
    values: [:identity_only, :schedule_supported, :full_product_supported, :not_applicable, :unsupported],
    required: true

  def support_badge(assigns) do
    ~H"""
    <span class="inline-flex items-center gap-1 rounded border px-1.5 py-0.5 text-xs" data-support={@status}>
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
    <span class="inline-flex items-center gap-1 rounded border px-1.5 py-0.5 text-xs" data-precision="unverified">
      {Copy.precision_unverified()}
    </span>
    """
  end
end
