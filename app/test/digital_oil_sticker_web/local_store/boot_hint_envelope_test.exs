defmodule DigitalOilStickerWeb.LocalStore.BootHintEnvelopeTest do
  @moduledoc """
  DOS-M09-003 AC-4 / INV-23: the `dos_boot_state` key in `localStorage` is a
  one-bit flag whose value envelope is exactly two string literals — `"never"`
  and `"has_data"`. Any other value would convert the one localStorage key
  this app writes for its own purposes (the boot-state hint that
  distinguishes an evicted store from a first visit) into a channel for
  personal data: identifiers, timestamps, VINs, garage contents.

  This is the source-scan companion to the broader G4 code-path scan (which
  proves no records path writes to localStorage at all). Here the assertion
  is stricter and narrower: for the ONE key we do write, the ONLY values
  emitted at any call site are the two literals the design allows — a bare
  quoted string, no interpolation, no variable reference, no function call.

  A regex over the source is the right tool for AC-4: the concern is what
  appears in the source a reviewer reads, not what a JS interpreter would
  evaluate at runtime. A future edit that introduces
  `localStorage.setItem(KEY, vehicle.id)` — or the sneakier
  `localStorage.setItem(KEY, `has_data:${uid}`)` whose runtime value still
  starts with "has_data" — must fail this test on the way in, regardless of
  whether some downstream check would catch the leak later.
  """
  use ExUnit.Case, async: true

  # Test file lives at app/test/digital_oil_sticker_web/local_store/, so
  # ../../../assets lands on app/assets/. Kept as an anchored constant so a
  # future move of the test file surfaces here rather than silently walking
  # the wrong tree.
  @assets Path.expand("../../../assets", __DIR__)

  # The one and only allowed pair of literals that may ride in a setItem
  # call targeting dos_boot_state. Both quoting styles are enumerated so
  # equality against the captured argument text is direct regardless of
  # whether the source used single- or double-quoted strings; a project
  # style change or a Prettier config flip must not silently degrade the
  # envelope check into a false pass.
  @allowed_values ~w("never" "has_data" 'never' 'has_data')

  # Matches an `<any-receiver>.setItem(<arg1>, <arg2>)` call. The receiver
  # was originally anchored to `localStorage`, but a refactor to
  # `store.setItem(...)` where `store` is an aliased import (or any other
  # local wrapper around localStorage) would then slip past this scan
  # entirely — the writer would look benign while still writing to the
  # real localStorage at runtime. Relaxed to any dotted receiver so the
  # value-envelope check follows the CALL, not the receiver identifier.
  # The refactor-proof key-location assertion below covers the companion
  # concern that no OTHER file may mention `dos_boot_state` at all.
  #
  # `[^,()]+?` for arg1 rejects commas and parens — enough for a bare
  # string literal or an identifier, which is all the first argument may
  # ever be here (a first arg with an inner comma or paren would be a
  # dynamic expression and is already outside the envelope).
  # `[^)]+?` for arg2 tolerates identifiers, template literals, and
  # concatenations so the scanner can flag them — while still failing to
  # match a nested-call value like `foo()`; the coverage assertion in the
  # first test below is what catches such a call slipping through unmatched.
  @setitem_pattern ~r/\.\s*setItem\s*\(\s*([^,()]+?)\s*,\s*([^)]+?)\s*\)/

  # Matches `const NAME = "dos_boot_state"` (or let/var). boot_hint.js binds
  # the key to a local `KEY` const, so the scanner has to follow that
  # indirection or every real call would look like `setItem(KEY, …)` with
  # no visible link to dos_boot_state.
  @key_alias_pattern ~r/(?:const|let|var)\s+(\w+)\s*=\s*"dos_boot_state"/

  # CRLF checkouts on Windows would break the multi-line-aware regexes above,
  # so normalise line endings the same way NoPersonalPersistenceTest does.
  defp read(path), do: path |> File.read!() |> String.replace("\r\n", "\n")

  defp js_sources do
    @assets
    |> Path.join("**/*.js")
    |> Path.wildcard()
    |> Enum.map(&{Path.relative_to(&1, @assets), read(&1)})
  end

  # Every setItem call in `source` whose first argument targets
  # dos_boot_state — matched either as the literal string or as a same-file
  # const alias. Returns the raw argument-2 text for each such call so the
  # caller can assert on it verbatim.
  defp boot_state_writes(source) do
    aliases =
      @key_alias_pattern
      |> Regex.scan(source, capture: :all_but_first)
      |> Enum.map(fn [name] -> name end)

    key_forms = MapSet.new([~s("dos_boot_state") | aliases])

    for [_full, arg1, value] <- Regex.scan(@setitem_pattern, source),
        MapSet.member?(key_forms, String.trim(arg1)) do
      String.trim(value)
    end
  end

  describe "AC-4: dos_boot_state accepts only literal never / has_data" do
    test "the JS walk reaches boot_hint.js" do
      # Without this floor, a broken glob or a rename that removed the file
      # would let every value-constraint assertion below pass vacuously on an
      # empty list. boot_hint.js is the one file the design REQUIRES to have
      # setItem calls against dos_boot_state.
      sources = js_sources()

      assert Enum.any?(sources, fn {path, _} ->
               Path.basename(path) == "boot_hint.js"
             end),
             "the JS walk missed boot_hint.js — the `#{@assets}` glob is " <>
               "wrong; the value-envelope assertion below would pass on " <>
               "zero call sites"
    end

    test "the substring dos_boot_state appears in exactly one file (js/local_store/boot_hint.js)" do
      # Refactor-proof companion to the value-envelope scan: independent of
      # the setItem call SHAPE. The receiver regex above matches
      # `localStorage.setItem(...)`, `store.setItem(...)`, and any other
      # dotted receiver — but a rewrite that stashed the key on a wrapper
      # object (`api["dos_boot_state"] = ...`, `writeKey("dos_boot_state", …)`,
      # a `send(worker, {key: "dos_boot_state", …})` postMessage) would still
      # bypass every setItem-shaped check. Pin the string LITERAL to the one
      # module that owns it: any other file that mentions `dos_boot_state`
      # is either a stray literal (route the write through the boot_hint
      # module instead) or a second writer that bypasses INV-23.
      extensions = ~w(js ts mjs jsx tsx)

      files_with_key =
        for ext <- extensions,
            path <- Path.wildcard(Path.join(@assets, "**/*.#{ext}")),
            String.contains?(read(path), "dos_boot_state"),
            # Normalise Windows backslashes so the equality assertion below
            # holds identically on POSIX and Windows checkouts.
            do:
              path
              |> Path.relative_to(@assets)
              |> String.replace("\\", "/")

      assert files_with_key == ["js/local_store/boot_hint.js"],
             "the substring \"dos_boot_state\" must appear in exactly one " <>
               "file — app/assets/js/local_store/boot_hint.js, the sole " <>
               "module that owns the boot-hint key. A second occurrence " <>
               "means either a stray literal (route the write through the " <>
               "boot_hint module) or a second writer that bypasses INV-23 " <>
               "regardless of call syntax. Found in: #{inspect(files_with_key)}"
    end

    test "positive control: the scanner catches a synthetic write of a personal value" do
      # A vehicle_id is the archetypal personal field this test exists to
      # keep out of dos_boot_state. Without proving the scanner would in
      # fact see such a call, a clean result on the real sources below
      # proves nothing — a typo in either regex above would silently turn
      # the whole test into a tautology.
      #
      # Two shapes are exercised:
      #   1. A bare identifier (`vehicle_id`) — the obvious leak.
      #   2. A template literal that starts with the string "has_data" so
      #      a naive `String.starts_with?` check would let it through.
      #      The regex requires an EXACT `"has_data"` literal, and this
      #      case is the reason.
      synthetic = """
      const KEY = "dos_boot_state"
      function leak(vehicle_id) {
        localStorage.setItem(KEY, vehicle_id)
        localStorage.setItem("dos_boot_state", `has_data:${vehicle_id}`)
      }
      """

      writes = boot_state_writes(synthetic)

      assert length(writes) == 2,
             "the scanner failed to see both synthetic setItem calls " <>
               "(expected 2, got #{length(writes)}: #{inspect(writes)}) — " <>
               "either @setitem_pattern or @key_alias_pattern is broken"

      offenders = Enum.reject(writes, &(&1 in @allowed_values))

      assert length(offenders) == 2,
             "the scanner should flag both synthetic writes as offenders " <>
               "(a bare identifier AND an interpolated template literal), " <>
               "got: #{inspect(offenders)}"
    end

    test "every shipped setItem targeting dos_boot_state passes a literal never or has_data" do
      writes =
        for {path, source} <- js_sources(),
            value <- boot_state_writes(source),
            do: {path, value}

      # A shipped tree with zero matching calls means either boot_hint.js
      # was removed (the reader/writer contract is gone) or the const-alias
      # walk is broken — both cases require a human look.
      assert writes != [],
             "no `localStorage.setItem(dos_boot_state, …)` calls were found " <>
               "anywhere under #{@assets} — the boot-hint writer moved, was " <>
               "deleted, or is no longer bound to a scannable const alias; " <>
               "either update this scan or restore the writer"

      offenders =
        for {path, value} <- writes,
            value not in @allowed_values,
            do: "#{path}: setItem(dos_boot_state, #{value})"

      assert offenders == [],
             "dos_boot_state must hold only the literal \"never\" or " <>
               "\"has_data\" (INV-23); found dynamic or disallowed values " <>
               "at: #{Enum.join(offenders, "; ")}"
    end
  end
end
