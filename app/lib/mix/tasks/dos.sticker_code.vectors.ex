defmodule Mix.Tasks.Dos.StickerCode.Vectors do
  @shortdoc "Emit sticker-code test vectors for the browser port"

  @moduledoc """
  Writes the canonical sticker-code test vectors to
  `conformance/fixtures/sticker-code-vectors.json`.

      mix dos.sticker_code.vectors

  The browser needs its own encoder — the whole point of the feature is that
  the values never leave the device, so the server cannot generate the QR. That
  means two implementations of one wire format, which is exactly the situation
  where the two drift apart and nobody notices until a code stops scanning.

  These vectors are the contract between them. This module is the canonical
  side; the JS port is asserted against this file rather than against a second
  reading of the documentation. A vector set that no longer matches is a
  merge conflict rather than a field report.

  The cases are chosen for the edges that a reimplementation gets wrong:
  absent fields, the boundaries of every fixed-width integer, a multi-byte
  manual grade, and the first and last entry of each frozen table — an
  off-by-one in an index table is silent and produces the wrong oil.
  """
  use Mix.Task

  alias DigitalOilSticker.StickerCode

  @output "conformance/fixtures/sticker-code-vectors.json"

  # A configuration key from the shipped catalog, so the vectors exercise a
  # UUID of the shape the app actually issues.
  @key "000384cf-aee6-5ba8-968a-1fe30158f387"
  # All bits set and all bits clear: the two UUIDs most likely to expose a
  # byte-order or sign mistake in a port.
  @key_min "00000000-0000-0000-0000-000000000000"
  @key_max "ffffffff-ffff-ffff-ffff-ffffffffffff"

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")

    vectors = Enum.map(cases(), &vector/1)

    payload =
      Jason.encode!(
        %{
          "format_version" => StickerCode.format_version(),
          "note" =>
            "Canonical vectors emitted by mix dos.sticker_code.vectors. The browser " <>
              "port must reproduce every `code` from its `sticker`, and recover every " <>
              "`sticker` from its `code`.",
          "grades" => StickerCode.grades(),
          "base_stocks" => StickerCode.base_stocks(),
          "vectors" => vectors
        },
        pretty: true
      )

    path = Path.join(repo_root(), @output)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, payload <> "\n")

    Mix.shell().info("wrote #{length(vectors)} vectors to #{@output}")
  end

  defp cases do
    [
      {"typical",
       %{
         configuration_key: @key,
         changed_on: ~D[2026-03-15],
         odometer_m: 77_570_381,
         grade: "0W-20",
         base_stock: "full_synthetic"
       }},
      {"no service logged", %{configuration_key: @key}},
      {"date only", %{configuration_key: @key, changed_on: ~D[2026-03-15]}},
      {"odometer only", %{configuration_key: @key, odometer_m: 1}},
      {"epoch date", %{configuration_key: @key, changed_on: ~D[2000-01-01]}},
      {"last representable date",
       %{configuration_key: @key, changed_on: Date.add(~D[2000-01-01], 65_534)}},
      {"zero odometer", %{configuration_key: @key, odometer_m: 0}},
      {"largest odometer", %{configuration_key: @key, odometer_m: 4_294_967_294}},
      {"all-zero uuid", %{configuration_key: @key_min, changed_on: ~D[2026-03-15]}},
      {"all-ones uuid", %{configuration_key: @key_max, changed_on: ~D[2026-03-15]}},
      {"first grade", %{configuration_key: @key, grade: List.first(StickerCode.grades())}},
      {"last grade", %{configuration_key: @key, grade: List.last(StickerCode.grades())}},
      {"first base stock",
       %{configuration_key: @key, base_stock: List.first(StickerCode.base_stocks())}},
      {"last base stock",
       %{configuration_key: @key, base_stock: List.last(StickerCode.base_stocks())}},
      {"manual grade", %{configuration_key: @key, grade: "0W-16 racing"}},
      {"manual grade, multi-byte", %{configuration_key: @key, grade: "5W‑30"}},
      {"manual grade at the length limit",
       %{configuration_key: @key, grade: String.duplicate("x", 20)}},
      {"everything at once",
       %{
         configuration_key: @key_max,
         changed_on: Date.add(~D[2000-01-01], 65_534),
         odometer_m: 4_294_967_294,
         grade: "0W-16 racing",
         base_stock: "high_mileage"
       }}
    ]
  end

  defp vector({name, sparse}) do
    # Normalized first: the cases above omit what they do not set, while decode
    # always returns the complete shape. Comparing the two directly would fail
    # on absent keys rather than on anything about the encoding.
    sticker = StickerCode.normalize(sparse)

    {:ok, code} = StickerCode.encode(sticker)
    # Emitted only after proving it round-trips here, so a vector can never
    # enshrine a code this implementation cannot itself read back.
    {:ok, ^sticker} = StickerCode.decode(code)

    %{
      "name" => name,
      "code" => code,
      "sticker" => %{
        "configuration_key" => sticker.configuration_key,
        "changed_on" => date_to_json(sticker.changed_on),
        "odometer_m" => sticker.odometer_m,
        "grade" => sticker.grade,
        "base_stock" => sticker.base_stock
      }
    }
  end

  defp date_to_json(nil), do: nil
  defp date_to_json(%Date{} = date), do: Date.to_iso8601(date)

  # lib/mix/tasks -> lib/mix -> lib -> app -> repo root. Four, not five: five
  # walked out of the repo entirely and wrote the vectors to the home
  # directory, which the task reported as success.
  defp repo_root, do: Path.expand("../../../..", __DIR__)
end
