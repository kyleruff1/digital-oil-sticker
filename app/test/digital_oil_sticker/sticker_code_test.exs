defmodule DigitalOilSticker.StickerCodeTest do
  @moduledoc """
  The sticker-code wire format (QR feature).

  This format is the one thing here that is genuinely expensive to get wrong.
  Codes end up printed on stickers in windshields, so a change in what the bytes
  mean does not break a build — it silently misreads every code already in the
  world. The properties below are therefore about *every* input rather than the
  handful anyone thinks to write down.

  Two claims carry the whole feature:

    * it round-trips, because a hash would give uniqueness and nothing else and
      you cannot autofill a form from a digest, and
    * it is deterministic, because that is what makes storage unnecessary.
  """
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias DigitalOilSticker.StickerCode

  # A UUID as the catalog actually issues them.
  defp uuid_generator do
    gen all(bytes <- binary(length: 16)) do
      {:ok, uuid} = Ecto.UUID.load(bytes)
      uuid
    end
  end

  defp date_generator do
    gen all(days <- integer(0..65_534)) do
      Date.add(~D[2000-01-01], days)
    end
  end

  defp sticker_generator do
    gen all(
          key <- uuid_generator(),
          date <- one_of([constant(nil), date_generator()]),
          odometer <- one_of([constant(nil), integer(0..4_294_967_294)]),
          grade <- one_of([constant(nil), member_of(StickerCode.grades())]),
          stock <- one_of([constant(nil), member_of(StickerCode.base_stocks())])
        ) do
      %{
        configuration_key: key,
        changed_on: date,
        odometer_m: odometer,
        grade: grade,
        base_stock: stock
      }
    end
  end

  describe "the two claims the feature rests on" do
    property "every sticker round-trips exactly" do
      check all(sticker <- sticker_generator(), max_runs: 500) do
        assert {:ok, code} = StickerCode.encode(sticker)
        assert {:ok, decoded} = StickerCode.decode(code)

        assert decoded == sticker,
               "the code did not survive a round trip, so scanning it would autofill the wrong values"
      end
    end

    property "the same values always produce the same code" do
      check all(sticker <- sticker_generator(), max_runs: 200) do
        assert {:ok, first} = StickerCode.encode(sticker)
        assert {:ok, second} = StickerCode.encode(sticker)

        # This is why nothing has to be stored. If encoding were not a pure
        # function of the values, a code would have to be recorded somewhere to
        # stay meaningful — and that somewhere would be a server-side record of
        # a user's garage.
        assert first == second
      end
    end

    property "different stickers produce different codes" do
      check all(a <- sticker_generator(), b <- sticker_generator(), a != b, max_runs: 300) do
        {:ok, code_a} = StickerCode.encode(a)
        {:ok, code_b} = StickerCode.encode(b)

        # Not "mostly unique" — a bijection, so a collision is impossible rather
        # than improbable.
        refute code_a == code_b
      end
    end
  end

  describe "shape" do
    property "a fully populated code is 40 characters" do
      check all(key <- uuid_generator(), date <- date_generator(), max_runs: 50) do
        {:ok, code} =
          StickerCode.encode(%{
            configuration_key: key,
            changed_on: date,
            odometer_m: 77_570_381,
            grade: "0W-20",
            base_stock: "full_synthetic"
          })

        # Fixed width matters: a QR encoder picks its version from the payload
        # length, so a stable length means a stable module count and a sticker
        # design that does not reflow.
        assert String.length(code) == 40
      end
    end

    property "codes contain only base32 characters, so no URL escaping is needed" do
      check all(sticker <- sticker_generator(), max_runs: 200) do
        {:ok, code} = StickerCode.encode(sticker)

        assert String.match?(code, ~r/^[A-Z2-7]+$/),
               "#{code} is not plain base32, so it would need escaping in a URL fragment"
      end
    end

    property "case does not matter, because a code may be retyped or read aloud" do
      check all(sticker <- sticker_generator(), max_runs: 100) do
        {:ok, code} = StickerCode.encode(sticker)

        assert StickerCode.decode(String.downcase(code)) == {:ok, sticker}
      end
    end
  end

  describe "a grade the user typed themselves" do
    test "survives the round trip verbatim" do
      sticker = %{
        configuration_key: "000384cf-aee6-5ba8-968a-1fe30158f387",
        changed_on: ~D[2026-03-15],
        odometer_m: 1_000,
        grade: "0W-16 racing",
        base_stock: "full_synthetic"
      }

      {:ok, code} = StickerCode.encode(sticker)

      assert {:ok, ^sticker} = StickerCode.decode(code)
    end

    test "is refused rather than silently truncated when it is too long" do
      sticker = %{
        configuration_key: "000384cf-aee6-5ba8-968a-1fe30158f387",
        grade: String.duplicate("x", 40)
      }

      # Truncating would put a grade on the sticker that the user never chose.
      assert {:error, :manual_grade_too_long} = StickerCode.encode(sticker)
    end

    test "handles multi-byte characters by bytes, not by characters" do
      sticker = %{
        configuration_key: "000384cf-aee6-5ba8-968a-1fe30158f387",
        grade: "5W‑30"
      }

      # That hyphen is U+2011, three bytes. A length field counted in
      # characters would slice a code point in half on decode.
      assert {:ok, code} = StickerCode.encode(sticker)
      assert {:ok, %{grade: "5W‑30"}} = StickerCode.decode(code)
    end
  end

  describe "refusing what it cannot read" do
    test "a code from a future format version is refused, not guessed at" do
      {:ok, code} =
        StickerCode.encode(%{configuration_key: "000384cf-aee6-5ba8-968a-1fe30158f387"})

      <<_version::8, rest::binary>> = Base.decode32!(code, padding: false)
      future = Base.encode32(<<99::8>> <> rest, padding: false)

      assert {:error, :unsupported_format_version} = StickerCode.decode(future)
    end

    test "a truncated code is refused" do
      {:ok, code} =
        StickerCode.encode(%{configuration_key: "000384cf-aee6-5ba8-968a-1fe30158f387"})

      assert {:error, _} = StickerCode.decode(String.slice(code, 0..20))
    end

    test "a grade index this version does not know is refused, not approximated" do
      {:ok, code} =
        StickerCode.encode(%{
          configuration_key: "000384cf-aee6-5ba8-968a-1fe30158f387",
          grade: "0W-20"
        })

      <<head::binary-size(23), _grade::8, stock::8>> = Base.decode32!(code, padding: false)
      unknown = Base.encode32(<<head::binary, 200::8, stock::8>>, padding: false)

      # Naming the wrong oil is worse than admitting the code is unreadable.
      assert {:error, :unknown_grade_index} = StickerCode.decode(unknown)
    end

    test "text that is not a code at all is refused" do
      assert {:error, :not_base32} = StickerCode.decode("this is not a sticker code")
      assert {:error, :not_a_string} = StickerCode.decode(nil)
    end

    test "a sticker without a configuration key cannot be encoded" do
      assert {:error, :missing_configuration_key} =
               StickerCode.encode(%{changed_on: ~D[2026-01-01]})
    end

    test "an out-of-range date is refused rather than wrapping" do
      sticker = %{
        configuration_key: "000384cf-aee6-5ba8-968a-1fe30158f387",
        changed_on: ~D[1999-12-31]
      }

      assert {:error, :date_out_of_range} = StickerCode.encode(sticker)
    end
  end

  describe "the frozen vocabularies" do
    test "still cover everything the catalog ships" do
      catalog_grades = Enum.map(DigitalOilSticker.Catalog.OilModel.grades(), & &1.code)
      catalog_stocks = Enum.map(DigitalOilSticker.Catalog.OilModel.base_stocks(), & &1.code)

      # The format's tables are frozen literals, not reads from the catalog,
      # precisely so reordering a table cannot change what existing codes mean.
      # The cost of that is drift, so it is checked here rather than left to be
      # discovered by a user whose grade stopped encoding.
      assert MapSet.subset?(MapSet.new(catalog_grades), MapSet.new(StickerCode.grades())),
             "the catalog ships grades the code format cannot encode: " <>
               inspect(catalog_grades -- StickerCode.grades()) <>
               ". Append them to @grades — never reorder, never reuse a retired index."

      assert MapSet.subset?(MapSet.new(catalog_stocks), MapSet.new(StickerCode.base_stocks())),
             "the catalog ships base stocks the code format cannot encode: " <>
               inspect(catalog_stocks -- StickerCode.base_stocks())
    end

    test "every catalog grade actually encodes" do
      for grade <- Enum.map(DigitalOilSticker.Catalog.OilModel.grades(), & &1.code) do
        sticker = %{configuration_key: "000384cf-aee6-5ba8-968a-1fe30158f387", grade: grade}

        assert {:ok, code} = StickerCode.encode(sticker)

        # A grade falling into the manual tail would still work, but silently
        # cost 20 bytes and stop being a known value.
        assert String.length(code) == 40, "#{grade} fell through to the manual-grade tail"
        assert {:ok, %{grade: ^grade}} = StickerCode.decode(code)
      end
    end
  end

  describe "the vectors the browser port is held to" do
    @vectors_path Path.expand(
                    "../../../conformance/fixtures/sticker-code-vectors.json",
                    __DIR__
                  )

    test "still match this implementation" do
      # The browser has to encode too — the values never leave the device, so
      # the server cannot make the QR. Two implementations of one wire format
      # drift, and this file is the contract that makes the drift loud rather
      # than a field report about a code that stopped scanning.
      #
      # If this fails after a deliberate format change: regenerate with
      # `mix dos.sticker_code.vectors`, and note that every code already
      # printed on a windshield was produced by the OLD vectors.
      assert File.exists?(@vectors_path),
             "the vector file is missing; run mix dos.sticker_code.vectors"

      %{"vectors" => vectors, "format_version" => version} =
        @vectors_path |> File.read!() |> Jason.decode!()

      assert version == StickerCode.format_version()
      assert length(vectors) > 10, "the vector set is too thin to hold a port honest"

      for %{"name" => name, "code" => code, "sticker" => raw} <- vectors do
        sticker = %{
          configuration_key: raw["configuration_key"],
          changed_on: raw["changed_on"] && Date.from_iso8601!(raw["changed_on"]),
          odometer_m: raw["odometer_m"],
          grade: raw["grade"],
          base_stock: raw["base_stock"]
        }

        assert StickerCode.encode(sticker) == {:ok, code},
               "vector #{inspect(name)} no longer encodes to its recorded code — every " <>
                 "sticker already printed carries the old one"

        assert StickerCode.decode(code) == {:ok, sticker},
               "vector #{inspect(name)} no longer decodes to its recorded values"
      end
    end
  end
end
