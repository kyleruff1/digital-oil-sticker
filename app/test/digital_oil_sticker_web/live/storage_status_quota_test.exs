defmodule DigitalOilStickerWeb.StorageStatusQuotaTest do
  @moduledoc """
  The "Space" line on /settings/storage renders in plain units (MB) when the
  browser gave a StorageManager.estimate, and admits an honest absence when it
  did not. INV-25 forbids inventing a bar or a "restore from cloud" cue for the
  no-estimate case; the wording lives in `StorageStatusLive.quota_line/1` and
  this test pins both branches so a well-meaning UI change cannot silently
  replace the no-estimate copy with a fabricated percentage.
  """
  use DigitalOilStickerWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  defp hydrate(view, overrides) do
    render_hook(
      view,
      "local_store:hydrate",
      Map.merge(
        %{
          "envelope" => "dos_local",
          "schema_version" => 1,
          "seq" => 0,
          "tab_id" => "t",
          "generated_at" => "2026-08-01T00:00:00Z",
          "data" => %{
            "meta" => nil,
            "vehicles" => [],
            "events" => [],
            "readings" => [],
            "usage" => [],
            "reminders" => [],
            "prefs" => nil
          },
          "storage" => %{"mode" => "idb", "boot_hint" => "never"}
        },
        overrides
      )
    )
  end

  describe "the Space line" do
    test "renders usage and quota in MB with a percent when the browser reports an estimate",
         %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/settings/storage")

      html =
        hydrate(view, %{
          "storage" => %{
            "mode" => "idb",
            "boot_hint" => "never",
            "estimate" => %{"usage" => 500_000, "quota" => 5_000_000}
          }
        })

      # `mb/1` divides by 1_048_576 (a true MB, not 1_000_000), so 500_000
      # bytes rounds to 0.5 MB and 5_000_000 bytes rounds to 4.8 MB. Pinning
      # the exact string keeps the units honest: swapping to decimal MB or
      # dropping the trailing period would show up here.
      assert html =~ "0.5 MB of 4.8 MB used (10.0%)."
    end

    test "admits the browser gave no estimate instead of faking a number", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/settings/storage")

      # `estimate` omitted entirely — Session.quota/1 returns nil, and the
      # quota_line/1 nil clause is what renders. Overriding "storage"
      # wholesale is fine here (Map.merge/2 is shallow) because we supply the
      # mode and boot_hint the rest of the page needs.
      html = hydrate(view, %{"storage" => %{"mode" => "idb", "boot_hint" => "never"}})

      assert html =~ "This browser does not report a storage estimate."
      # The refutations are the point: no MB figure and no percentage should
      # appear anywhere the Space line renders. `mb/1` is the only source of
      # " MB" on this page, and `pct` the only source of "%).", so their
      # absence is proof that quota_line did not fall through to the numeric
      # clause with a made-up denominator.
      refute html =~ " MB"
      refute html =~ "%)."
    end
  end
end
