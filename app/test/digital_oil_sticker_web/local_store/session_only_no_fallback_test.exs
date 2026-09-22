defmodule DigitalOilStickerWeb.LocalStore.SessionOnlyNoFallbackTest do
  @moduledoc """
  DOS-M09-003 AC-8: a failed IndexedDB open has ZERO fallback path — no
  localStorage shadow, no server-side persistence, no quiet writeback.

  The invariant this locks in place is stated bluntly by INV-25 and FR-8:
  when the browser refuses durable storage (private mode, cleared site data,
  policy-blocked IDB, quota-driven eviction, whatever), the app runs strictly
  ephemeral for the tab's lifetime. Anything that looked like a save would be
  a lie, and anything that fell back to localStorage would move the personal
  records from the store the user thinks they are in to one they have no way
  to inspect or clear from the settings page.

  Two halves guard the two shapes the failure can take:

    1. LiveView-level. After a hydrate declaring `storage.mode = "session_only"`
       (which the client sends when `idb.open()` fails or the store is not
       writable), the server MUST NOT push `local_store:put` back — that is the
       protocol event that persists records. And any mutation event that a
       user could still trigger (`switch_vehicle`, `toggle_garage` on the
       sticker page) MUST leave the server-side garage assign untouched:
       `mutations_enabled?/1` refuses to stage the write, and no side channel
       exists to persist it anyway.

    2. Source-level. Every `localStorage.setItem` call under
       `app/assets/js/**/*.{js,mjs}` must be one of exactly two approved sites:
       `local_store/boot_hint.js` writing `dos_boot_state` (the origin-scoped
       "have we ever held data" hint that INV-23/25 explicitly carves out as
       non-personal), or a `phx:theme` setter. Any other setItem is a
       regression that would either shadow the durable store or leak personal
       data into a bucket the settings-page Erase flow does not clear. A
       positive-control case plants a synthetic violation in a temp dir and
       asserts the scanner catches it — a scanner that never fires is a
       scanner that never fails, and this test would still pass if the
       predicate were silently broken.

  This test is intentionally paired with `session_only_banner_test.exs` (AC-6,
  the persistent banner) and `storage_recovery_test.exs` (surrounding hydration
  states). Those cover the visible UX; this one covers the silent, invisible
  guarantee that the visible UX rests on.
  """
  use DigitalOilStickerWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  # A minimally valid envelope that declares the browser could not provide
  # durable storage. The client emits this shape from `pushSessionOnly()` in
  # `hooks/local_store.js` when `idb.open()` fails or the DB is not writable;
  # simulating it via `render_hook` exercises the same server-side handler
  # (`Session.handle_hydrate/2` -> `resolve_state/2` -> `:storage_unavailable`).
  @session_only_envelope %{
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
    "storage" => %{"mode" => "session_only", "boot_hint" => "never", "reason" => "unavailable"}
  }

  # Narrow the snapshot to the assigns that a fallback-path regression would
  # be observable in: the garage (the personal data), the seq counter (which
  # any real stage_mutation bumps), and the mode+state flags that gate the
  # write path.
  defp assigns_snapshot(view) do
    :sys.get_state(view.pid).socket.assigns
    |> Map.take([:local_state, :storage_mode, :seq, :garage, :pending_writes, :unsaved_writes])
  end

  describe "(1) LiveView refuses every persistence path under session_only" do
    test "a session_only hydrate on the sticker page pushes no local_store:put", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      render_hook(view, "local_store:hydrate", @session_only_envelope)

      # A server that shipped a `local_store:put` in response to a mere
      # hydrate would be treating the empty session_only garage as
      # "authoritative, please overwrite the browser" — the exact fallback
      # this AC forbids. The idempotence test already forbids write-back on
      # any hydrate; this asserts it specifically under session_only where a
      # careless "reset the browser to a clean state" reflex is tempting.
      refute_push_event(view, "local_store:put", %{})

      # And the assigns settle in the mode the rest of the guards depend on.
      snapshot = assigns_snapshot(view)
      assert snapshot.storage_mode == :session_only
      assert snapshot.local_state == :storage_unavailable
    end

    test "toggle_garage on the sticker page pushes no put and does not mutate the garage",
         %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      render_hook(view, "local_store:hydrate", @session_only_envelope)

      before = assigns_snapshot(view)

      # `toggle_garage` is a UI-only handler by design (it flips
      # :garage_open?, no stage_mutation). Firing it under session_only
      # proves the trivial-click case: the mere invocation of a handle_event
      # under this mode does not leak a put or move the personal-data
      # assigns. A future refactor that made toggle_garage stage anything
      # into prefs (say, "remember the panel was open") would trip both
      # assertions below.
      _ = render_click(view, "toggle_garage", %{})

      refute_push_event(view, "local_store:put", %{})

      after_ = assigns_snapshot(view)
      assert before.garage == after_.garage
      assert before.seq == after_.seq
      assert before.pending_writes == after_.pending_writes
      assert before.unsaved_writes == after_.unsaved_writes
    end

    test "switch_vehicle under session_only is refused, not persisted", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      render_hook(view, "local_store:hydrate", @session_only_envelope)

      before = assigns_snapshot(view)

      # `switch_vehicle` IS a mutation handler: on the durable path it calls
      # Session.stage_mutation/3 which push_events `local_store:put`. Under
      # session_only, `mutations_enabled?/1` returns false and the handler
      # takes the put_flash branch instead. This is the whole test in one
      # call: the mutation attempt reaches the handler, and yet nothing
      # persists — no put pushed, no seq bump, no pending_writes entry, no
      # garage delta. If any of those changed, session_only would be a lie.
      _ = render_click(view, "switch_vehicle", %{"vehicle-id" => "no-such-vehicle"})

      refute_push_event(view, "local_store:put", %{})

      after_ = assigns_snapshot(view)

      assert before.garage == after_.garage,
             "session_only allowed a mutation to reach garage — fallback path exists"

      assert before.seq == after_.seq,
             "session_only bumped the seq counter — a write was staged"

      assert before.pending_writes == after_.pending_writes,
             "session_only staged a pending write — the ledger recorded a write it must never have"

      assert before.unsaved_writes == after_.unsaved_writes
    end
  end

  describe "(2) source scan: no unauthorised localStorage.setItem in app/assets/js" do
    # Regex captures the FIRST argument of a `localStorage.setItem(...)` call.
    # Matches the identifier or quoted-literal up to the first comma or
    # whitespace/close-paren. `KEY` (bare identifier), `"dos_boot_state"`,
    # `'phx:theme'` all normalise to a single capture we can classify below.
    @setitem_re ~r/localStorage\.setItem\s*\(\s*([^,\s)]+)/

    # Every allowed setItem site MUST match exactly one of these two rules:
    #   - Path is `local_store/boot_hint.js` AND the key is either the bare
    #     identifier `KEY` (the const in that file) or the literal
    #     `"dos_boot_state"`. Anything else in boot_hint.js — a new key, a
    #     smuggled second identifier — fails.
    #   - Any path, but the key is the literal `"phx:theme"` (single or
    #     double quoted). Today this only appears in the CSP-nonced inline
    #     script in `layouts/root.html.heex`, which the scan does not see;
    #     the rule is prospective, allowing the theme setter to be moved into
    #     a hook file in the future without tripping this gate.
    @boot_hint_path "local_store/boot_hint.js"
    @allowed_boot_hint_keys ["KEY", ~s("dos_boot_state"), ~s('dos_boot_state')]
    @allowed_theme_keys [~s("phx:theme"), ~s('phx:theme')]

    defp allowed_setitem?(rel_path, key) do
      cond do
        rel_path == @boot_hint_path and key in @allowed_boot_hint_keys -> true
        key in @allowed_theme_keys -> true
        true -> false
      end
    end

    # The reusable scanner. Extracted from the test bodies so the positive
    # control can drive it against a synthetic directory and prove the
    # predicate actually rejects — a test whose scanner is inlined and whose
    # only assertion is "no violations found" would silently keep passing if
    # the predicate were broken to always return true.
    defp scan_for_violations(root) do
      # Normalise the root to forward slashes before glob expansion. On
      # Windows, `System.tmp_dir!()` returns a mixed-separator path
      # ("C:\\Users\\...\\Temp"), and `Path.wildcard/1` given a pattern with
      # mixed `\` and `/` silently returns `[]` — which would let the
      # positive control pass while proving nothing. Normalising here keeps
      # the scanner correct on both platforms.
      root = String.replace(root, "\\", "/")

      paths =
        Path.wildcard(Path.join(root, "**/*.js")) ++
          Path.wildcard(Path.join(root, "**/*.mjs"))

      Enum.flat_map(paths, fn path ->
        rel = path |> Path.relative_to(root) |> String.replace("\\", "/")

        path
        |> File.read!()
        |> String.split(~r/\r?\n/)
        |> Enum.with_index(1)
        |> Enum.flat_map(fn {line, line_no} ->
          case Regex.run(@setitem_re, line) do
            [_, key] ->
              if allowed_setitem?(rel, key),
                do: [],
                else: [{rel, line_no, key, String.trim(line)}]

            nil ->
              []
          end
        end)
      end)
    end

    test "every localStorage.setItem in app/assets/js is on the approved list" do
      # Mix runs tests from the app/ project root, so this relative path is
      # stable across CI and local runs. Kept relative (not __DIR__-based) so
      # a future move of the test file does not silently re-scope the scan.
      root = "assets/js"

      violations = scan_for_violations(root)

      formatted =
        violations
        |> Enum.map(fn {rel, line_no, key, line} ->
          "  #{rel}:#{line_no}: setItem(#{key}, ...)  -- #{line}"
        end)
        |> Enum.join("\n")

      assert violations == [],
             """
             DOS-M09-003 AC-8 / INV-25: unauthorised localStorage.setItem call(s) \
             under app/assets/js.

             Only these writes are allowed:
               - local_store/boot_hint.js writing dos_boot_state (via the KEY const)
               - a phx:theme setter (any file)

             Any other setItem breaks the "no fallback to localStorage" invariant \
             for session_only mode: personal records or app state would land in a \
             bucket the Storage settings Erase flow does not clear.

             Offending call site(s):
             #{formatted}
             """
    end

    test "the scanner itself detects a synthetic setItem violation (positive control)" do
      # Without this, a bug that silently made `allowed_setitem?/2` return
      # true for every key would leave the main test forever green — the
      # invariant would erode and this file would still pass. Plant a call
      # the scanner MUST flag, in a directory with no legitimate setItem
      # anywhere else, and assert both (a) that the scanner reports at least
      # one violation and (b) that the report names the offending path.
      tmp =
        Path.join(
          System.tmp_dir!(),
          "dos-m09-003-ac8-#{System.unique_integer([:positive])}"
        )

      File.mkdir_p!(tmp)
      on_exit(fn -> File.rm_rf!(tmp) end)

      bad_js = Path.join(tmp, "leak.js")

      File.write!(
        bad_js,
        # A key that matches NEITHER of the two allow rules — not
        # dos_boot_state, not KEY (no such const in this file), not
        # phx:theme. The scanner must find it.
        "localStorage.setItem(\"forbidden_key\", \"payload\")\n"
      )

      # Also plant a legitimate-looking phx:theme setter in the same tree so
      # the positive control ALSO proves the allow rule fires — otherwise a
      # broken predicate that flagged everything would look "correct" here.
      good_js = Path.join(tmp, "theme.js")
      File.write!(good_js, "localStorage.setItem(\"phx:theme\", theme)\n")

      violations = scan_for_violations(tmp)

      assert violations != [],
             "positive control failed: scanner missed the synthetic setItem in leak.js"

      assert Enum.any?(violations, fn {rel, _line_no, key, _line} ->
               rel == "leak.js" and key == ~s("forbidden_key")
             end),
             """
             positive control failed: scanner did not identify the synthetic \
             violation by path AND key. Got: #{inspect(violations)}
             """

      # And the theme setter must have been allowed through — proving the
      # allow rule is not vacuously permissive but also is not vacuously
      # rejecting: exactly one violation, exactly for the bad file.
      refute Enum.any?(violations, fn {rel, _, _, _} -> rel == "theme.js" end),
             "positive control: scanner incorrectly flagged a legitimate phx:theme setter"
    end
  end
end
