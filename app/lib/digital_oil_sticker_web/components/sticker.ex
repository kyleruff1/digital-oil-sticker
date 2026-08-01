defmodule DigitalOilStickerWeb.Components.Sticker do
  @moduledoc """
  The digital sticker: the brand SVG as the bottom layer of an
  aspect-ratio 1320/640 component with accessible HTML viewports overlaid at
  the brand README's exact percentages. Transparency contract: NO background
  color on the img or its wrapper — the page (a car-window scene later) must
  remain visible through the 72%-opacity cling body. Below 320 CSS px the
  full lockup is replaced by the compact mark + a text list.
  """
  use Phoenix.Component
  alias DigitalOilStickerWeb.Copy

  attr :date_value, :string, default: nil
  attr :mileage_value, :string, default: nil
  attr :grade_value, :string, default: nil
  attr :skeleton, :boolean, default: false, doc: "pre-hydration: pulsing viewports, no claims"

  def sticker(assigns) do
    ~H"""
    <div class="dos-sticker-frame">
      <%!-- Full lockup ≥ 320 CSS px (brand minimum). --%>
      <div class="dos-sticker relative w-full" style="aspect-ratio: 1320 / 640;">
        <img
          src="/images/dos-logo.svg"
          alt=""
          aria-hidden="true"
          class="absolute inset-0 h-full w-full select-none"
          draggable="false"
        />
        <.viewport
          label="Date"
          value={@date_value}
          skeleton={@skeleton}
          style="left:14.24%; top:50.5%; width:30.15%; height:12%;"
          test_id="sticker-date"
        />
        <span
          class="absolute font-bold text-[2.2cqw] tracking-wide"
          style="left:46.5%; top:53%; color:#101820;"
          aria-hidden="true"
        >
          OR
        </span>
        <.viewport
          label="Mileage"
          value={@mileage_value}
          skeleton={@skeleton}
          style="left:55.61%; top:50.5%; width:30.15%; height:12%;"
          test_id="sticker-mileage"
        />
        <.viewport
          label="Grade"
          value={@grade_value}
          skeleton={@skeleton}
          style="left:38.03%; top:72.0%; width:23.94%; height:8%;"
          test_id="sticker-grade"
        />
      </div>

      <%!-- Compact fallback below 320 px, per the brand README. --%>
      <div class="dos-sticker-compact hidden">
        <div class="flex items-center gap-3">
          <img src="/images/dos-mark.svg" alt="" width="48" height="48" />
          <dl class="text-sm">
            <div>
              <dt class="inline font-semibold">Date:</dt>

              <dd class="inline" data-test="sticker-date-compact">{@date_value || "—"}</dd>
            </div>
            <div>
              <dt class="inline font-semibold">Mileage:</dt>

              <dd class="inline">{@mileage_value || "—"}</dd>
            </div>
            <div>
              <dt class="inline font-semibold">Grade:</dt>

              <dd class="inline">{@grade_value || "—"}</dd>
            </div>
          </dl>
        </div>
      </div>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :value, :string, default: nil
  attr :skeleton, :boolean, default: false
  attr :style, :string, required: true
  attr :test_id, :string, required: true

  defp viewport(assigns) do
    ~H"""
    <div
      class="absolute flex flex-col items-center justify-center"
      style={@style}
      data-test={@test_id}
    >
      <span class="text-[1.6cqw] font-bold uppercase tracking-widest" style="color:#101820;">
        {@label}
      </span>
      <span
        :if={not @skeleton}
        class="w-full truncate text-center text-[2.6cqw] font-semibold leading-tight"
        style="color:#101820;"
      >
        {@value || "—"}
      </span>
      <span
        :if={@skeleton}
        class="dos-skeleton h-[2.6cqw] w-3/4 animate-pulse rounded"
        style="background:#10182022;"
        aria-hidden="true"
      ></span>
      <span :if={@skeleton} class="sr-only">{Copy.sr_checking()}</span>
    </div>
    """
  end
end
