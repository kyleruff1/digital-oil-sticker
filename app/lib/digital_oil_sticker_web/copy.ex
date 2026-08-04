defmodule DigitalOilStickerWeb.Copy do
  @moduledoc """
  THE copy catalog: every user-facing string on the storage/picker/logging
  surfaces lives here, as the single scan surface for the copy-lint gate.
  Mandated strings (constitution INV-20/21/24/25, M02/M05/M09 specs, and the
  rev-2 claims policy) are reproduced verbatim — do not paraphrase them.

  Framing rules enforced by the copy-lint test: the required framing is
  "stored in this browser"; the prohibited storage and claim phrases are
  listed in docs/product/RECOMMENDATION_CLAIMS_POLICY.md and in the lint
  test itself (they are deliberately not spelled here — the lint scans this
  file).
  """

  # --- Mandated, verbatim -----------------------------------------------------
  def not_specified, do: "Not specified"
  def precision_unverified, do: "Exact configuration not verified"
  def source_unavailable, do: "Source unavailable"
  def your_interval, do: "Your interval"
  def meets_requirements, do: "Meets the recorded requirements"
  def estimated_due_date, do: "Estimated due date"
  def unsaved_record, do: "Not saved to this browser"
  def conflict_notice, do: "Reloaded from this browser's newer data"
  def quarantine_notice, do: "Could not read some records"
  def not_applicable_ev, do: "Engine oil service not applicable"

  # --- Hydration / storage states --------------------------------------------
  def sr_checking, do: "Checking this browser for your records…"

  def empty_heading, do: "Set up your first vehicle"

  def empty_body do
    "Your records are stored in this browser, on this device. There is no account " <>
      "and no copy on our server. Clearing your site data, browser storage eviction, " <>
      "private browsing, resetting or uninstalling your browser, or switching devices " <>
      "will lose them. Exporting a file is the only way to keep or move them."
  end

  def data_missing_heading, do: "This browser's stored records are gone"

  def data_missing_body do
    "Records were stored in this browser before, and they are no longer here. " <>
      "Your browser's site data was most likely cleared or evicted. There is no copy " <>
      "on our server, and there never was. If you have an export file, importing it " <>
      "is the only way to bring the records back."
  end

  def hydration_refused_heading, do: "This browser holds more than we will load at once"

  def hydration_refused_body(cap) do
    "We stopped loading because #{cap_phrase(cap)}. Nothing was changed or " <>
      "removed — your records are still in this browser exactly as they were. " <>
      "Exporting a file still works, and is the safest next step."
  end

  defp cap_phrase(:payload_bytes),
    do: "the records in this browser are larger than we load in one go"

  defp cap_phrase(:vehicles), do: "this browser holds more vehicles than we load in one go"
  defp cap_phrase(:events), do: "this browser holds more oil changes than we load in one go"

  defp cap_phrase(:readings),
    do: "this browser holds more odometer readings than we load in one go"

  defp cap_phrase(_), do: "this browser holds more records than we load in one go"

  def storage_unavailable_heading, do: "This browser's storage could not be used"

  def storage_unavailable_body do
    "We could not read or write storage in this browser, so we cannot tell whether " <>
      "any records are stored here. You can still look up a vehicle. Anything you " <>
      "enter now will not be stored in this browser."
  end

  def session_only_banner do
    "Nothing is being stored in this browser. This browser is not letting the app " <>
      "store data — a private window or a storage setting is the usual cause. " <>
      "Anything you enter will be gone when you close this tab. Export a file to keep it."
  end

  def read_only_banner do
    "This browser holds data from a newer version of the app. Changes are turned " <>
      "off so nothing here is overwritten. You can export a file."
  end

  def quarantine_body(count, total) do
    "Could not read some records — #{count} of #{total}. Everything else loaded. " <>
      "You can export the raw contents of this browser's storage to look at what could not be read."
  end

  def saving, do: "Saving to this browser…"

  def not_saved_body do
    "Not saved to this browser. This entry is on screen but was not stored. " <>
      "It will be gone when you close this tab. Export a file to keep it."
  end

  def quota_full do
    "This browser's storage is full, so the entry was not stored. " <>
      "Nothing already stored was changed or removed."
  end

  # DOS-M09-003 FR-13 / AC-11 — the 80%-of-quota pressure surface. Not a
  # blocker and not a distinct :local_state: writes still go through, nothing
  # is deleted on the user's behalf, and the copy names the two things the
  # user can do about it (export outside this browser, remove records they no
  # longer need). Deliberately free of "backup" / "sync" language — an
  # exported file is a file the user keeps, not a service we run.
  def quota_pressure_heading, do: "This browser is running low on storage"

  def quota_pressure_body do
    "This browser's storage for the app is above 80% of what it will hold. " <>
      "Writes are still going through and nothing has been removed. " <>
      "Exporting a file keeps a copy outside this browser, and removing " <>
      "vehicles or oil changes you no longer need frees space in this browser."
  end

  def does_not_notify, do: "This app does not notify you when it is closed."

  # --- The scannable code ------------------------------------------------------
  # Deliberately does not say the scan moves anything. It does not: the code
  # carries the values printed on the sticker and nothing else, so scanning it
  # elsewhere shows those values and leaves this browser's records where they
  # are. Any wording suggesting the records themselves travel would be a
  # prohibited storage claim wearing a different word.
  def qr_alt, do: "QR code for this oil change record"

  def qr_note do
    "Scanning shows these same values on another device. It does not move " <>
      "what is stored in this browser."
  end

  # --- The oil step at vehicle intake -----------------------------------------
  # Heading is a noun phrase, not a question: under the defaults-then-track-
  # touch flow the app has already filled in an oil before the user reads
  # this, and posing it as a question the user must answer misattributes the
  # calculated number below to a choice they did not make.
  def intake_oil_heading, do: "Oil type for the estimate"

  def intake_oil_why do
    "The type of oil sets how far the interval can stretch. We've started with " <>
      "full synthetic because that gives the longest interval we model for this " <>
      "engine — change it below if that's not what goes in."
  end

  # Rendered above the log form's oil section when the vehicle's intake was
  # never answered (planned_oil == "defaulted"). Names the state honestly —
  # nobody has told the app what this vehicle uses — and points to the fix.
  def log_form_needs_oil do
    "No oil type was recorded at intake for this vehicle. Pick one below so " <>
      "the record and the sticker match what actually went in."
  end

  # Same shape, different truth: at intake the user answered "I don't know
  # yet" — which is an answer, not an absence — and the log form is where
  # they finally record what actually went in. Copy that says "no oil was
  # recorded" would lie about intake; this variant says what is on file.
  def log_form_intake_was_unknown do
    "You said you didn't know the oil type at intake. Record what actually " <>
      "went in below so the sticker reflects it."
  end

  def intake_oil_unknown, do: "I don't know yet"

  def intake_oil_unknown_note do
    "You will get the shortest interval we model for this engine until an oil " <>
      "change records what actually went in."
  end

  def recommendation_line(miles, months) do
    "About #{miles} miles or #{months} months after each oil change, whichever comes first."
  end

  # Rendered on the sticker qualifier and next to the intake recommendation
  # when the oil is app-chosen (defaulted), never user-touched. Says WHOSE
  # answer produced the number honestly — the app's assumption, not the
  # user's choice — and points to where they change it.
  def assumed_oil_note do
    "Our estimate, assuming full synthetic — change it at intake if that's not what goes in."
  end

  def unknown_oil_qualifier do
    "The shortest interval we model for this engine — record what oil goes in " <>
      "to extend it."
  end

  # --- The vehicle switcher ----------------------------------------------------
  def prefs_unreadable do
    "Could not read this browser's stored settings, so the choice was not changed. " <>
      "Exporting a file keeps everything, including what could not be read."
  end

  def other_vehicles, do: "Other vehicles"
  def add_vehicle, do: "Add a vehicle"
  def delete_vehicle_heading, do: "Remove this vehicle?"

  def delete_vehicle_body(vehicle_desc, event_count) do
    "This removes #{vehicle_desc} and its #{event_count} recorded " <>
      "#{if event_count == 1, do: "oil change", else: "oil changes"} from this browser. " <>
      "There is no copy anywhere else, so this cannot be recovered."
  end

  # --- Import and erase ---------------------------------------------------------
  # Vocabulary discipline matters doubly here: this surface is exactly where
  # "restore" and "backup" want to be written, and exactly where they would
  # promise a service that does not exist. The file is a file the user kept.
  def import_heading, do: "Import a file"

  def import_body do
    "Load an export file into this browser. The file is read on this device " <>
      "and is not uploaded anywhere."
  end

  def import_choose_label, do: "Choose the export file"

  def import_warning do
    "Importing replaces everything stored in this browser with the file's " <>
      "contents. Anything here that is not in the file will be gone."
  end

  def import_confirm_label, do: "Replace with the file's contents"

  def import_invalid, do: "This is not a Digital Oil Sticker export file."

  def import_damaged do
    "This file does not match its own integrity hash — it was changed or " <>
      "damaged after it was exported."
  end

  def import_newer do
    "This file was made by a newer version of the app than this browser is " <>
      "running. Load the app fresh and try again."
  end

  def import_storage_failed do
    "This browser refused the write, so nothing was changed."
  end

  def erase_heading, do: "Erase everything stored in this browser"

  def erase_body do
    "Removes every vehicle, oil change, reading, reminder, and setting this " <>
      "app has stored in this browser. Unless you exported a file, there is " <>
      "no other copy anywhere."
  end

  def erase_confirm_label, do: "Erase everything"

  # --- The calendar reminder ---------------------------------------------------
  def reminder_heading, do: "Reminder"

  def reminder_body do
    "Your calendar can remind you before the estimated due date. The event " <>
      "carries the date and the estimate only — your records stay in this browser."
  end

  def reminder_lead_label, do: "Remind me"
  def reminder_download, do: "Add to my calendar"

  def reminder_needs_change do
    "Log an oil change first — the reminder is measured from it."
  end

  # --- Cascade / catalog states ----------------------------------------------
  def choose_upstream(level), do: "Choose a #{level} first."
  def loading, do: "Loading…"

  def narrowed_empty(level, upstream),
    do: "No #{level} options are listed for the #{upstream} you chose."

  def no_catalog_match, do: "No catalog match for these choices."
  def catalog_unreadable, do: "The vehicle catalog could not be read."
  def rate_limited, do: "Too many requests — wait a moment and try again."
  def results_count(n) when n == 1, do: "1 result"
  def results_count(n), do: "#{n} results"
  def count_unknown, do: "Result count unknown"
  def vehicle_not_listed, do: "My vehicle is not listed"

  def connection_problem,
    do: "Connection problem — this is not a statement about your vehicle's data."

  # --- Products / provenance ---------------------------------------------------
  def from_catalog, do: "From catalog"
  def user_entered, do: "User entered"
  def as_of(date), do: "As of #{date}"
  def not_listed_enter_myself, do: "Not listed — enter it myself"
  def no_longer_listed, do: "No longer listed in the catalog."

  # The "Factory recommendation" badge (RECOMMENDATION_CLAIMS_POLICY.md
  # §"Factory recommendation label"). Ready but INERT: the label only ever
  # appears when a value was populated from OEM-sourced data with per-row
  # provenance in our internal source register (DOS-M03-007 lane b / ADR-0007
  # lane b). Until that card activates, every consumer's null-guard suppresses
  # it — the string exists here so the copy-lint has one canonical source and
  # so a future prohibited-vocabulary sweep can enforce the label wording.
  def factory_recommendation_label, do: "Factory recommendation"
  def manufacturer_viscosity_heading, do: "Manufacturer viscosity"

  # --- Our own oil model -------------------------------------------------------
  # These strings exist so an interval can never render without saying whose
  # model produced it. Nothing here may be phrased as manufacturer guidance.
  def our_model_label, do: "Our estimate"

  def our_model_basis do
    "This interval comes from our own model, not from your vehicle's maker. " <>
      "We build it from standard viscosity grades, published oil-life ranges " <>
      "for each type of oil, and an engine class we work out ourselves. If we " <>
      "ever hold your maker's own schedule, it replaces this, and whichever " <>
      "interval is shorter is the one we show."
  end

  def lowest_published_used do
    "We have no specific rule for this combination, so we use the lowest " <>
      "published interval for this type of oil rather than estimating upward."
  end

  def grade_suggested_for(class_name), do: "Commonly used on #{class_name} engines"
  def grade_show_all, do: "Show every grade we list"
  def grade_not_listed, do: "Not listed — enter the grade myself"
  def engine_class_line(class_name), do: "We classify this vehicle as: #{class_name}"

  def interval_summary(miles, months) do
    "#{format_int(miles)} miles or #{months} months, whichever comes first."
  end

  def miles_range(low, high), do: "#{format_int(low)}–#{format_int(high)} miles typical"

  def severe_service_prompt, do: "Does any of this describe how the vehicle is driven?"

  def severe_service_effect do
    "Answering yes shortens the interval — published severe-service guidance " <>
      "roughly halves it."
  end

  def interval_overridden, do: "You set this interval yourself, so we use yours."
  def override_interval_label, do: "Set my own interval instead"

  # --- Oil change form ---------------------------------------------------------
  def date_incomplete, do: "Choose a month, a day, and a year."
  def date_future, do: "A service date in the future can't be recorded."

  def date_before_model_year,
    do: "That date is before this vehicle's model year. Check the date before saving."

  def day_cleared(month_name, year, days),
    do: "Day cleared — #{month_name} #{year} has #{days} days."

  def repeat_prefill_hint,
    do: "Enter today's date and the odometer reading — these are never carried over."

  def duplicate_warning(date, odo, unit),
    do: "You already recorded an oil change on #{date} at #{odo} #{unit}."

  def odometer_lower(date, value, unit),
    do: "This reading is lower than the reading on #{date} (#{value} #{unit})."

  # --- No-affiliation (rev-2 policy, verbatim) --------------------------------
  def no_affiliation do
    "Vehicle, lubricant, and filter names are used only to identify applicable " <>
      "vehicles and products. Digital Oil Sticker is independent and is not " <>
      "sponsored, approved, or endorsed by vehicle manufacturers, lubricant " <>
      "manufacturers, filter manufacturers, NHTSA, EPA, DOE, SAE International, " <>
      "or the American Petroleum Institute."
  end

  # Thousands separators without pulling in a formatting dependency.
  defp format_int(n) when is_integer(n) do
    n
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/(\d{3})(?=\d)/, "\\1,")
    |> String.reverse()
  end
end
