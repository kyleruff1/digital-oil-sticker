defmodule DigitalOilSticker.StickerCode do
  @moduledoc """
  The sticker code: a compact, deterministic, reversible encoding of everything
  a sticker shows.

  The point is that there is nothing to store. The same values always produce
  the same code, and the code carries the values — so a QR is generated from
  the record itself rather than from a row in a table somewhere. No server-side
  garage, no identifier to correlate, nothing to leak (INV-23, INV-26).

  ## Encoding, not hashing

  This is a bijection, not a digest. A hash would give uniqueness and nothing
  else: you cannot autofill a form from a hash, because a hash is one-way. The
  scanning half of this feature is the reason the code has to be reversible.

  A consequence worth stating: **the code is not a secret.** Anyone who can read
  it can read the values. That is correct for this data — a paper oil sticker
  in a windshield already shows the date, the mileage and the grade to anyone
  who walks past — but it is why the payload may never grow to include notes,
  a VIN, or anything a person would not tape to their own window.

  ## Layout, version 1 — 25 bytes, plus an optional tail

      byte  0      format version, always 1
      bytes 1-16   configuration_key, the catalog's UUID for this exact build
      bytes 17-18  service date, days since 2000-01-01, big-endian u16
      bytes 19-22  odometer in metres, big-endian u32
      byte  23     viscosity grade (frozen index, or a marker)
      byte  24     oil base stock (frozen index, or absent)
      tail         present only when the grade byte says `manual`:
                   one length byte, then that many UTF-8 bytes

  Rendered with unpadded RFC 4648 base32, which is 40 characters for the common
  case. Base32 over base64url for three reasons: it survives being read aloud or
  typed with the wrong case, it needs no URL escaping, and its alphabet lets a
  QR encoder use alphanumeric mode instead of byte mode.

  ## The frozen tables, and why they are frozen here

  Grades and base stocks are closed vocabularies in our own oil model, so an
  index is the compact way to carry them. But an index into a *database table*
  is only stable while nobody reorders the table — and a reordered table would
  silently change what every existing code in the world means.

  So the mapping lives here, as a literal, versioned with the format. Adding a
  grade appends to the list. Removing one **retires its index permanently**
  rather than reusing it. A test asserts this list still covers what the
  catalog ships, so the two can drift apart loudly rather than quietly.

  ## Where this runs

  The canonical implementation is here, in Elixir, because that is where the
  property tests can be exhaustive. The browser needs its own copy to generate
  a QR without sending the values anywhere, and that port is held to the vectors
  this module emits (`DigitalOilSticker.StickerCode.Vectors`) rather than to a
  second reading of this documentation.
  """

  @format_version 1

  # Days are counted from this date so a two-byte field covers every plausible
  # service date. Moving this epoch would reinterpret every existing code.
  @epoch ~D[2000-01-01]
  @max_days 65_534
  @absent_date 65_535
  @absent_odometer 4_294_967_295
  @absent_byte 255
  @manual_grade_byte 254
  @max_manual_grade_bytes 20

  # FROZEN. Append only; never reorder, never reuse a retired index.
  @grades ~w(0W-8 0W-16 0W-20 0W-30 0W-40 5W-20 5W-30 5W-40 5W-50 10W-30 10W-40 10W-60 15W-40 20W-50)

  # FROZEN, on the same terms. Ordered as first shipped, not alphabetically —
  # alphabetical order is a rendering choice and must not decide a wire format.
  @base_stocks ~w(conventional synthetic_blend full_synthetic high_mileage)

  @grade_index @grades |> Enum.with_index() |> Map.new()
  @grade_by_index @grades |> Enum.with_index() |> Map.new(fn {code, i} -> {i, code} end)
  @stock_index @base_stocks |> Enum.with_index() |> Map.new()
  @stock_by_index @base_stocks |> Enum.with_index() |> Map.new(fn {code, i} -> {i, code} end)

  @type sticker :: %{
          configuration_key: String.t(),
          changed_on: Date.t() | nil,
          odometer_m: non_neg_integer() | nil,
          grade: String.t() | nil,
          base_stock: String.t() | nil
        }

  @doc "The format version these functions read and write."
  @spec format_version() :: pos_integer()
  def format_version, do: @format_version

  @doc "The frozen grade list, for the drift test and the JS port's vectors."
  @spec grades() :: [String.t()]
  def grades, do: @grades

  @doc "The frozen base-stock list, on the same terms."
  @spec base_stocks() :: [String.t()]
  def base_stocks, do: @base_stocks

  @doc """
  Fill in the fields a sparse sticker leaves out.

  `encode/1` accepts a map that simply omits what it does not have, because
  that is how callers naturally build one. `decode/1` always returns the
  complete shape. So round-trip identity holds for a NORMALIZED sticker, not
  for any map that happens to encode — `normalize/1` is what makes the two
  comparable, and skipping it is how a caller ends up comparing
  `%{configuration_key: k}` against a decoded map with four explicit nils and
  concluding the codec is broken.
  """
  @spec normalize(map()) :: sticker()
  def normalize(sticker) when is_map(sticker) do
    %{
      configuration_key: Map.get(sticker, :configuration_key),
      changed_on: Map.get(sticker, :changed_on),
      odometer_m: Map.get(sticker, :odometer_m),
      grade: Map.get(sticker, :grade),
      base_stock: Map.get(sticker, :base_stock)
    }
  end

  @doc """
  Encode a sticker to its code.

  Every field except the configuration key is optional: a vehicle set up but
  never serviced still has a sticker, and it still has a code.
  """
  @spec encode(sticker()) :: {:ok, String.t()} | {:error, atom()}
  def encode(%{configuration_key: key} = sticker) do
    with {:ok, uuid} <- uuid_bytes(key),
         {:ok, days} <- encode_date(Map.get(sticker, :changed_on)),
         {:ok, metres} <- encode_odometer(Map.get(sticker, :odometer_m)),
         {:ok, grade_byte, tail} <- encode_grade(Map.get(sticker, :grade)),
         {:ok, stock_byte} <- encode_stock(Map.get(sticker, :base_stock)) do
      binary =
        <<@format_version::8, uuid::binary-size(16), days::16, metres::32, grade_byte::8,
          stock_byte::8>> <> tail

      {:ok, Base.encode32(binary, padding: false)}
    end
  end

  def encode(_), do: {:error, :missing_configuration_key}

  @doc """
  Decode a code back to its values.

  Strict on purpose. There is no checksum byte — a QR carries its own error
  correction, which is the right layer for transcription damage — so this
  refuses anything whose structure or ranges are wrong rather than returning a
  plausible-looking record built from noise.
  """
  @spec decode(String.t()) :: {:ok, sticker()} | {:error, atom()}
  def decode(code) when is_binary(code) do
    with {:ok, binary} <- decode32(code),
         {:ok, parts} <- split(binary),
         {:ok, sticker} <- build(parts) do
      {:ok, sticker}
    end
  end

  def decode(_), do: {:error, :not_a_string}

  # -- encoding helpers --------------------------------------------------------

  defp uuid_bytes(key) when is_binary(key) do
    case Ecto.UUID.dump(key) do
      {:ok, raw} -> {:ok, raw}
      :error -> {:error, :invalid_configuration_key}
    end
  end

  defp uuid_bytes(_), do: {:error, :invalid_configuration_key}

  defp encode_date(nil), do: {:ok, @absent_date}

  defp encode_date(%Date{} = date) do
    case Date.diff(date, @epoch) do
      days when days >= 0 and days <= @max_days -> {:ok, days}
      _ -> {:error, :date_out_of_range}
    end
  end

  defp encode_date(_), do: {:error, :invalid_date}

  defp encode_odometer(nil), do: {:ok, @absent_odometer}

  defp encode_odometer(metres)
       when is_integer(metres) and metres >= 0 and metres < @absent_odometer,
       do: {:ok, metres}

  defp encode_odometer(_), do: {:error, :odometer_out_of_range}

  defp encode_grade(nil), do: {:ok, @absent_byte, <<>>}

  defp encode_grade(grade) when is_binary(grade) do
    case Map.fetch(@grade_index, grade) do
      {:ok, index} ->
        {:ok, index, <<>>}

      :error ->
        # A grade the user typed themselves. Carried verbatim in the tail so
        # scanning still autofills what they actually put in.
        bytes = :erlang.byte_size(grade)

        if bytes > 0 and bytes <= @max_manual_grade_bytes do
          {:ok, @manual_grade_byte, <<bytes::8, grade::binary>>}
        else
          {:error, :manual_grade_too_long}
        end
    end
  end

  defp encode_grade(_), do: {:error, :invalid_grade}

  defp encode_stock(nil), do: {:ok, @absent_byte}

  defp encode_stock(stock) when is_binary(stock) do
    case Map.fetch(@stock_index, stock) do
      {:ok, index} -> {:ok, index}
      # Unlike grade there is no free-text base stock: it is a radio group over
      # a closed list, so an unknown value is a bug rather than user input.
      :error -> {:error, :unknown_base_stock}
    end
  end

  defp encode_stock(_), do: {:error, :invalid_base_stock}

  # -- decoding helpers --------------------------------------------------------

  defp decode32(code) do
    # Uppercased first: base32 is case-insensitive in practice, and a code read
    # off a windshield or retyped should not fail on case alone.
    case Base.decode32(String.upcase(code), padding: false) do
      {:ok, binary} -> {:ok, binary}
      :error -> {:error, :not_base32}
    end
  end

  defp split(
         <<@format_version::8, uuid::binary-size(16), days::16, metres::32, grade_byte::8,
           stock_byte::8, tail::binary>>
       ) do
    {:ok,
     %{
       uuid: uuid,
       days: days,
       metres: metres,
       grade_byte: grade_byte,
       stock_byte: stock_byte,
       tail: tail
     }}
  end

  defp split(<<version::8, _::binary>>) when version != @format_version,
    do: {:error, :unsupported_format_version}

  defp split(_), do: {:error, :malformed}

  defp build(parts) do
    with {:ok, key} <- load_uuid(parts.uuid),
         {:ok, date} <- decode_date(parts.days),
         {:ok, odometer} <- decode_odometer(parts.metres),
         {:ok, grade} <- decode_grade(parts.grade_byte, parts.tail),
         {:ok, stock} <- decode_stock(parts.stock_byte) do
      {:ok,
       %{
         configuration_key: key,
         changed_on: date,
         odometer_m: odometer,
         grade: grade,
         base_stock: stock
       }}
    end
  end

  defp load_uuid(raw) do
    case Ecto.UUID.load(raw) do
      {:ok, key} -> {:ok, key}
      :error -> {:error, :invalid_configuration_key}
    end
  end

  defp decode_date(@absent_date), do: {:ok, nil}
  defp decode_date(days), do: {:ok, Date.add(@epoch, days)}

  defp decode_odometer(@absent_odometer), do: {:ok, nil}
  defp decode_odometer(metres), do: {:ok, metres}

  defp decode_grade(@absent_byte, <<>>), do: {:ok, nil}

  defp decode_grade(@manual_grade_byte, <<length::8, grade::binary-size(length)>>)
       when length > 0 and length <= @max_manual_grade_bytes do
    if String.valid?(grade), do: {:ok, grade}, else: {:error, :invalid_manual_grade}
  end

  defp decode_grade(@manual_grade_byte, _), do: {:error, :malformed_manual_grade}

  defp decode_grade(index, <<>>) do
    case Map.fetch(@grade_by_index, index) do
      {:ok, code} -> {:ok, code}
      # A retired or not-yet-known index. Refused rather than guessed: naming
      # the wrong oil is worse than saying we cannot read the code.
      :error -> {:error, :unknown_grade_index}
    end
  end

  defp decode_grade(_index, _tail), do: {:error, :unexpected_tail}

  defp decode_stock(@absent_byte), do: {:ok, nil}

  defp decode_stock(index) do
    case Map.fetch(@stock_by_index, index) do
      {:ok, code} -> {:ok, code}
      :error -> {:error, :unknown_base_stock_index}
    end
  end
end
