defmodule DigitalOilStickerWeb.Vehicles do
  @moduledoc """
  Small helpers about a vehicle record, in one place.

  Both the sticker page and the log form need a plain-language description
  of the active vehicle ("2015 BMW 328i · Trim"). It previously lived
  duplicated in both LiveViews with a comment claiming they were "kept in
  sync so a future change in one place doesn't silently drift" — a
  contradiction: duplication makes drift easier, not harder. Two calls to
  the same function is the mechanism.
  """
  alias DigitalOilStickerWeb.Copy

  @doc """
  A description of a vehicle in the format a human writes it: nickname if
  set, otherwise `"YEAR MAKE MODEL"` plus `" · BUILD"` when the build is a
  real trim string rather than the `"YEAR — Not specified"` placeholder.

  Returns `""` for nil, so a caller can safely interpolate.
  """
  @spec description(map() | nil) :: String.t()
  def description(nil), do: ""

  def description(vehicle) do
    case vehicle["nickname"] do
      name when is_binary(name) and name != "" ->
        name

      _ ->
        snap = vehicle["display_snapshot"] || %{}
        build = snap["build"]

        head =
          [snap["year"], snap["make"], snap["model"]]
          |> Enum.reject(&is_nil/1)
          |> Enum.join(" ")

        if is_binary(build) and build != "" and not String.contains?(build, Copy.not_specified()) do
          "#{head} · #{build}"
        else
          head
        end
    end
  end
end
