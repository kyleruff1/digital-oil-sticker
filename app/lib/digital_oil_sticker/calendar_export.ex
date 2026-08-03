defmodule DigitalOilSticker.CalendarExport do
  @moduledoc """
  Builds an iCalendar (RFC 5545) reminder for a vehicle's next oil change.

  ## Why a calendar file and not a notification

  A browser cannot notify anyone while it is closed, and closed is the state a
  car maintenance app spends almost all its life in. The honest ways out are
  Web Push — which needs a server-side subscription record per device, the first
  personal thing this project would keep on a server — or handing the reminder
  to something that is already running. The operating system's calendar is
  already running.

  So the lead time the user picks becomes a `VALARM`, and the reminding is done
  by software that does not need to know anything about us.

  ## All-day, deliberately

  `DTSTART;VALUE=DATE` rather than a timestamp. A service due date is a calendar
  date, not an instant: a user in UTC-8 whose oil is due on the 15th should not
  see it land on the 14th because we picked midnight UTC. The same reasoning
  governs `DigitalOilSticker.StickerCode`, and for the same reason — a date that
  quietly shifts by one is the kind of defect nobody reports.

  ## The UID is stable, so re-exporting updates rather than duplicates

  Keyed to the vehicle, not to the due date. Logging a new oil change moves the
  due date; if the UID moved with it, every oil change would leave a stale
  event behind and the user would accumulate a calendar full of dates that
  already passed. A stable UID plus an advancing `SEQUENCE` means the second
  import replaces the first.
  """

  @product_id "-//Digital Oil Sticker//Oil change reminder//EN"

  # RFC 5545 3.1: content lines are folded at 75 OCTETS, not characters.
  @fold_octets 75

  @typedoc "Everything the reminder needs. `due_on` is required; the rest decorate it."
  @type reminder :: %{
          required(:vehicle_id) => String.t(),
          required(:due_on) => Date.t(),
          optional(:vehicle_label) => String.t() | nil,
          optional(:due_mileage) => String.t() | nil,
          optional(:lead_days) => non_neg_integer(),
          optional(:changed_on) => Date.t() | nil,
          optional(:sequence_at) => DateTime.t() | nil,
          optional(:now) => DateTime.t()
        }

  @doc """
  Builds the `.ics` text, or refuses.

  Refuses rather than emitting a calendar entry it cannot stand behind — an
  event on the wrong day is worse than no event, because the user stops
  checking once they believe something else is watching.
  """
  @spec build(reminder()) :: {:ok, String.t()} | {:error, atom()}
  def build(%{vehicle_id: vehicle_id, due_on: %Date{} = due_on} = reminder)
      when is_binary(vehicle_id) do
    lead_days = Map.get(reminder, :lead_days, 7)

    cond do
      vehicle_id == "" ->
        {:error, :missing_vehicle_id}

      not (is_integer(lead_days) and lead_days >= 0 and lead_days <= 365) ->
        {:error, :lead_days_out_of_range}

      true ->
        {:ok, render(reminder, due_on, lead_days)}
    end
  end

  def build(_), do: {:error, :invalid_reminder}

  @doc "The lead times offered in the UI, as `{label, days}`."
  @spec lead_time_options() :: [{String.t(), non_neg_integer()}]
  def lead_time_options do
    [
      {"On the day", 0},
      {"3 days before", 3},
      {"1 week before", 7},
      {"2 weeks before", 14},
      {"1 month before", 30}
    ]
  end

  @doc "A suggested filename. Carries no personal value — filenames end up in shared folders."
  @spec filename() :: String.t()
  def filename, do: "oil-change-reminder.ics"

  # -- rendering ---------------------------------------------------------------

  defp render(reminder, due_on, lead_days) do
    now = Map.get(reminder, :now) || DigitalOilSticker.Clock.now()
    label = reminder |> Map.get(:vehicle_label) |> presence()

    [
      "BEGIN:VCALENDAR",
      "VERSION:2.0",
      "PRODID:#{@product_id}",
      "CALSCALE:GREGORIAN",
      "METHOD:PUBLISH",
      "BEGIN:VEVENT",
      "UID:#{uid(reminder.vehicle_id)}",
      "DTSTAMP:#{timestamp(now)}",
      "SEQUENCE:#{sequence(reminder)}",
      # An all-day event's DTEND is the day AFTER the last day it covers.
      # Omitting it makes the event one day long by default, which is what we
      # want, but stating it removes a difference between calendar clients.
      "DTSTART;VALUE=DATE:#{date(due_on)}",
      "DTEND;VALUE=DATE:#{date(Date.add(due_on, 1))}",
      "SUMMARY:#{escape(summary(label))}",
      "DESCRIPTION:#{escape(description(reminder, label))}",
      "TRANSP:TRANSPARENT",
      "BEGIN:VALARM",
      "ACTION:DISPLAY",
      "DESCRIPTION:#{escape(summary(label))}",
      "TRIGGER:#{trigger(lead_days)}",
      "END:VALARM",
      "END:VEVENT",
      "END:VCALENDAR"
    ]
    |> Enum.map_join("\r\n", &fold/1)
    |> Kernel.<>("\r\n")
  end

  defp summary(nil), do: "Oil change due"
  defp summary(label), do: "Oil change due — #{label}"

  defp description(reminder, label) do
    [
      label && "Vehicle: #{label}",
      changed_line(Map.get(reminder, :changed_on)),
      mileage_line(reminder |> Map.get(:due_mileage) |> presence()),
      "Estimated from the interval recorded in Digital Oil Sticker. Not manufacturer guidance.",
      "Your records stay in the browser you entered them in; this event is a copy of the date only."
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n")
  end

  defp changed_line(%Date{} = changed_on), do: "Last changed: #{Date.to_iso8601(changed_on)}"
  defp changed_line(_), do: nil

  defp mileage_line(nil), do: nil

  # Stated as "or", matching the sticker: whichever comes first. A calendar can
  # only alarm on the date, so the mileage has to be visible in the event or the
  # user is reminded of half the rule.
  defp mileage_line(due_mileage), do: "Or at #{due_mileage}, whichever comes first."

  # Stable per vehicle. See the moduledoc: a UID that moved with the due date
  # would leave a stale event behind after every oil change.
  defp uid(vehicle_id), do: "oil-#{vehicle_id}@digitaloilsticker.com"

  # Has to advance for a client to accept the replacement — same UID with the
  # same SEQUENCE is ignored by sequence-honoring clients, so every change a
  # user expects to see replaced must bump it.
  #
  # `sequence_at` is the instant of the last action that changed the event's
  # content (the lead choice's updated_at, the logged change's created_at,
  # whichever is newer), in seconds since 2000. It dwarfs the day-count
  # fallback below by orders of magnitude, so mixing the two forms across
  # downloads still only ever moves the number up.
  defp sequence(%{sequence_at: %DateTime{} = at}),
    do: max(0, DateTime.diff(at, ~U[2000-01-01 00:00:00Z], :second))

  defp sequence(%{changed_on: %Date{} = changed_on}),
    do: Date.diff(changed_on, ~D[2000-01-01])

  defp sequence(_), do: 0

  # An all-day event's relative trigger counts from local MIDNIGHT, so a plain
  # -P7D fires at 00:00 — technically on time and practically useless as a
  # notification. Anchored to nine in the morning instead: "N days before"
  # means 09:00 local, N days before the due date. (The reminders schema keeps
  # a preferred_time field for making the hour a choice later.)
  defp trigger(0), do: "PT9H"
  defp trigger(days), do: "-PT#{days * 24 - 9}H"

  defp date(%Date{} = d), do: Calendar.strftime(d, "%Y%m%d")

  defp timestamp(%DateTime{} = dt),
    do: dt |> DateTime.truncate(:second) |> Calendar.strftime("%Y%m%dT%H%M%SZ")

  # RFC 5545 3.3.11: backslash, semicolon, comma, and newline are special in a
  # TEXT value. Backslash first — escaping it after the others would double-
  # escape the backslashes those others just introduced.
  defp escape(value) do
    value
    |> String.replace("\\", "\\\\")
    |> String.replace(";", "\\;")
    |> String.replace(",", "\\,")
    |> String.replace("\r\n", "\\n")
    # A LONE carriage return, after the CRLF pairs are gone. Left alone it
    # reaches the output as a raw control byte in a content line, which is an
    # illegal file rather than an ugly one.
    |> String.replace("\r", "\\n")
    |> String.replace("\n", "\\n")
  end

  # RFC 5545 3.1. Folded at 75 octets with CRLF + a single space, and never in
  # the middle of a UTF-8 sequence — a split code point is not merely ugly, it
  # makes the file invalid and some clients reject the whole calendar.
  defp fold(line) when byte_size(line) <= @fold_octets, do: line

  defp fold(line) do
    {head, rest} = split_at_octets(line, @fold_octets)
    [head | fold_rest(rest)] |> Enum.join("\r\n ")
  end

  defp fold_rest(""), do: []

  # One octet narrower for continuation lines: the leading space is itself part
  # of the folded line's octet count.
  defp fold_rest(rest) do
    {head, tail} = split_at_octets(rest, @fold_octets - 1)
    [head | fold_rest(tail)]
  end

  defp split_at_octets(binary, limit) when byte_size(binary) <= limit, do: {binary, ""}

  defp split_at_octets(binary, limit) do
    # Walk back to a code-point boundary. UTF-8 continuation bytes match
    # 0b10xxxxxx, so a prefix ending on one is mid-character.
    limit = back_off_to_boundary(binary, limit)
    <<head::binary-size(^limit), tail::binary>> = binary
    {head, tail}
  end

  defp back_off_to_boundary(_binary, 0), do: 0

  defp back_off_to_boundary(binary, limit) do
    case binary do
      <<_::binary-size(^limit), next, _::binary>> when Bitwise.band(next, 0xC0) == 0x80 ->
        back_off_to_boundary(binary, limit - 1)

      _ ->
        limit
    end
  end

  defp presence(nil), do: nil
  defp presence(""), do: nil
  defp presence(value) when is_binary(value), do: String.trim(value) |> nil_if_empty()

  defp nil_if_empty(""), do: nil
  defp nil_if_empty(value), do: value
end
