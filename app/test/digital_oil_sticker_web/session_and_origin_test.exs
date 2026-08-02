defmodule DigitalOilStickerWeb.SessionAndOriginTest do
  @moduledoc """
  DOS-M09-007 FR-5 (`check_origin`) and FR-7 (session cookie contents).

  Both requirements replace a physical guarantee with a configured one. Until
  revision 1.0.0 the endpoint bound `127.0.0.1`, so no foreign origin could
  reach it and no cookie ever crossed a network. Hosting the application
  deletes that fact, and what stands in its place is a host list and a seven
  line cookie declaration. ADR-0004 puts it plainly: the replacement boundary
  is weaker in kind and therefore must be stronger in detail.

  Neither failure is loud. A wrong `check_origin` does not raise — it either
  accepts every origin (`false`) or accepts whatever `:url` happens to be
  (`true`), and the app keeps serving. A session cookie that grows a key does
  not raise either; it just starts carrying something across visits that the
  product promises it never carries. Nothing in a smoke test notices, so the
  assertions live here.

  What these tests do NOT cover:

    * They do not prove a real browser at a foreign origin is refused. This
      suite never performs the websocket handshake; it asserts the
      configuration the refusal is derived from. FR-5's second clause — that
      the refusal is not distinguishable in a way that aids probing — is not
      covered here at all.
    * They cannot observe `secure` as production sets it, because it is
      `Mix.env() == :prod` and this suite runs under `:test`. The test asserts
      the gate expression rather than a value it cannot produce.
    * The sentinel scan below is secondary to the allowlist assertion. A
      LiveView holds no `conn` and cannot write a cookie, so state cannot
      reach the session by any path that exists today. The scan is there to
      catch the path someone adds later.
  """
  use DigitalOilStickerWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias DigitalOilStickerWeb.Hosts

  @endpoint_source Path.expand("../../lib/digital_oil_sticker_web/endpoint.ex", __DIR__)
  @runtime_source Path.expand("../../config/runtime.exs", __DIR__)

  # Plug's own session key for the CSRF token, and the identifier LiveView
  # reads when it needs to disconnect a session's sockets. FR-7 allows these
  # two and nothing else. `live_socket_id` is currently never written — there
  # is no login to force a disconnect after — so the assertion is a subset
  # check rather than an equality one.
  @allowed_session_keys MapSet.new(["_csrf_token", "live_socket_id"])

  # Distinctive values driven through a real session below. They are shaped to
  # pass schema validation so they actually land in LiveView state rather than
  # being quarantined on the way in, which would make the scan meaningless.
  @sentinel_nickname "SentinelNicknameZQ7"
  @sentinel_vin_last6 "ZQ7X41"
  @sentinel_note "sentinel-note-oil-was-low"
  @sentinel_odometer 198_734_567
  @sentinel_date "2019-03-17"
  @sentinel_tab_id "sentinel-tab-id-9f2c"

  # Walked after hydration, on one cookie, so the scan sees the session as it
  # stands once the app has handled real vehicle data.
  @browse_routes ["/", "/vehicle", "/history", "/settings/storage"]

  @sentinels [
    @sentinel_nickname,
    @sentinel_vin_last6,
    @sentinel_note,
    Integer.to_string(@sentinel_odometer),
    @sentinel_date,
    @sentinel_tab_id
  ]

  # Substrings of the FR-7 prohibition list. These catch a future
  # `put_session(:tab_id, ...)` whose value this test could not have known to
  # look for — the key name is the tell.
  @prohibited_key_fragments ~w(vin odometer mileage tab_id vehicle garage note
                               prefs visitor user_id anon)

  setup_all do
    runtime = File.read!(@runtime_source)

    # Only the prod block configures check_origin. Asserting against the whole
    # file would let a dev-only occurrence satisfy the assertion.
    prod_block =
      case String.split(runtime, "if config_env() == :prod do") do
        [_before, block] ->
          block

        other ->
          flunk(
            "expected one `if config_env() == :prod do` in runtime.exs, found #{length(other) - 1}"
          )
      end

    %{
      # Comments explain why `true` and `false` are wrong, and naming them
      # there must not read as declaring them. Absence assertions run against
      # directives only.
      prod_directives: strip_comments(prod_block),
      session_options: session_options()
    }
  end

  defp strip_comments(source) do
    source
    |> String.split(["\r\n", "\n"])
    |> Enum.reject(&(&1 |> String.trim_leading() |> String.starts_with?("#")))
    |> Enum.join("\n")
  end

  # The endpoint's @session_options is a module attribute, so it is not
  # readable through Application config at runtime. Reading and evaluating the
  # literal keeps this test from carrying its own copy of max_age and friends:
  # a copy passes while the real declaration rots.
  defp session_options do
    source = File.read!(@endpoint_source)

    literal =
      case Regex.run(~r/@session_options\s*(\[.*?^  \])/ms, source) do
        [_whole, literal] -> literal
        nil -> flunk("could not find the @session_options literal in #{@endpoint_source}")
      end

    {opts, _bindings} = Code.eval_string(literal)

    assert Keyword.keyword?(opts), "@session_options did not evaluate to a keyword list"

    %{literal: literal, opts: opts}
  end

  describe "check_origin (FR-5)" do
    test "production names its origins instead of trusting a boolean", %{prod_directives: prod} do
      assert prod =~ ~r/check_origin:/,
             "the prod endpoint config does not set check_origin, so Phoenix falls back to its default"

      # `false` disables the check outright. `true` is the subtler mistake: it
      # compares the request origin against the endpoint's `:url`, which is
      # built from PHX_HOST. That is right today only by coincidence, and goes
      # silently wrong the moment a second hostname is served — the socket
      # just refuses to connect for the host nobody wrote down, and the page
      # looks stuck rather than misconfigured.
      refute prod =~ ~r/check_origin:\s*true\b/,
             "check_origin: true is prohibited by FR-5"

      refute prod =~ ~r/check_origin:\s*false\b/,
             "check_origin: false disables origin checking entirely"
    end

    test "the origin list is read from Hosts, not copied into the config", %{
      prod_directives: prod
    } do
      # A literal list here would be a second copy of the host list and the
      # CSP's connect-src a third. Copies drift, and the drift surfaces as a
      # socket that will not connect for exactly one host.
      assert prod =~ ~r/check_origin:\s*DigitalOilStickerWeb\.Hosts\.allowed_origins\(\)/,
             "check_origin must be sourced from DigitalOilStickerWeb.Hosts"

      refute prod =~ ~r/check_origin:\s*\[/,
             "check_origin carries an inline host list, which is a second copy of Hosts.production/0"
    end

    test "every allowed origin is https and matches the production host list" do
      origins = Hosts.allowed_origins()
      production = Hosts.production()

      # Without these the loops below would pass over nothing.
      assert length(production) > 0, "Hosts.production/0 is empty"

      assert length(origins) > 0,
             "Hosts.allowed_origins/0 is empty, which is check_origin: [] — nothing connects"

      for origin <- origins do
        assert URI.parse(origin).scheme == "https",
               "#{origin} is not https. On a force_ssl app an http origin is either a " <>
                 "misconfiguration or somebody probing, and neither should be trusted."
      end

      # Compared by parsed host rather than by rebuilding "https://" <> host,
      # so this asserts the relationship instead of restating the mapping the
      # code already performs. Equality covers both directions: no production
      # host is missing, and no origin is trusted that is not a production
      # host.
      assert Enum.sort(Enum.map(origins, &URI.parse(&1).host)) == Enum.sort(production),
             "allowed_origins/0 and production/0 disagree: #{inspect(origins)} vs #{inspect(production)}"
    end

    test "hosts that are owned but not yet resolving are not trusted" do
      planned = Hosts.planned()
      trusted = Enum.map(Hosts.allowed_origins(), &URI.parse(&1).host)

      assert length(planned) > 0, "Hosts.planned/0 is empty, so this test checks nothing"

      for host <- planned do
        refute host in trusted,
               "#{host} is trusted by check_origin, but DNS is not pointed at this app yet " <>
                 "(DOS-M09-006 / #84). Trusting a host whose resolution we do not control is " <>
                 "the one mistake this list exists to prevent."

        refute Hosts.connect_src() =~ host,
               "#{host} appears in the CSP connect-src before it serves anything"
      end
    end

    test "connect-src reaches every production host over wss" do
      connect_src = Hosts.connect_src()
      production = Hosts.production()

      assert length(production) > 0, "Hosts.production/0 is empty"

      # `'self'` covers same-origin HTTP but not the websocket: `wss:` is a
      # different scheme and connect-src does not infer it from the page
      # origin. Without the explicit entry our own CSP blocks the LiveView
      # socket, and the app looks merely unresponsive.
      assert connect_src =~ "'self'"

      for host <- production do
        assert connect_src =~ "wss://#{host}",
               "connect-src does not allow the LiveView socket for #{host}: #{connect_src}"
      end

      for token <- String.split(connect_src, ~r/\s+/, trim: true) do
        refute token =~ ~r{^(http|ws)://},
               "connect-src carries a plaintext origin, which is a mixed-content hole: #{token}"
      end
    end
  end

  describe "the session cookie declaration (FR-7)" do
    test "is http_only, Lax, and short-lived", %{session_options: %{opts: opts}} do
      assert opts[:http_only] == true,
             "a cookie readable from JavaScript is readable by anything injected into the page"

      # Lax still sends the cookie on a top-level navigation, which is what
      # CSRF verification needs to work after following a link. "None" would
      # attach it to every cross-site subrequest; "Strict" would break the
      # first request after an external link.
      assert opts[:same_site] == "Lax",
             "same_site is #{inspect(opts[:same_site])}, not \"Lax\""

      max_age = opts[:max_age]

      assert is_integer(max_age) and max_age > 0,
             "max_age is #{inspect(max_age)}. Unset makes this a session cookie whose lifetime " <>
               "is the browser's decision, and browsers restore sessions across restarts."

      # There is no account and nothing to stay signed in to. The cookie
      # exists for CSRF and socket identity, so anything past a long visit is
      # pure exposure — a longer-lived cookie is a longer-lived handle on one
      # browser.
      assert max_age <= 24 * 60 * 60,
             "max_age is #{max_age}s (over 24h). FR-7 requires a short max_age."
    end

    test "is signed by the cookie store rather than merely stored", %{
      session_options: %{opts: opts}
    } do
      assert opts[:store] == :cookie

      assert is_binary(opts[:signing_salt]) and opts[:signing_salt] != "",
             "without a signing_salt the cookie store cannot sign, and the session is tamperable"
    end

    test "declares secure as a production gate instead of inheriting a default", %{
      session_options: %{literal: literal, opts: opts}
    } do
      assert Keyword.has_key?(opts, :secure),
             "secure is not declared at all, so whether the cookie crosses plain HTTP is a default"

      # This suite runs under Mix.env() == :test, so the evaluated value here
      # is false and cannot be asserted true. What is assertable is the gate:
      # the flag is tied to the environment rather than left to a default, so
      # the production cookie is never sent over http.
      assert literal =~ ~r/secure:\s*Mix\.env\(\)\s*==\s*:prod/,
             "secure is not gated on the production environment"
    end
  end

  describe "the session cookie a real request sets (FR-7)" do
    test "carries the declared flags onto the wire", %{conn: conn, session_options: %{opts: opts}} do
      conn = get(conn, ~p"/")
      assert html_response(conn, 200)

      cookie = session_cookie(conn, opts)

      # Asserted against the response rather than the declaration a second
      # time: a flag Plug silently drops on the way out would still satisfy
      # the source-level test above.
      assert cookie.http_only == true
      assert cookie.same_site == "Lax"
      assert cookie.max_age == opts[:max_age]
    end

    test "is signed: a foreign key cannot read it", %{conn: conn, session_options: %{opts: opts}} do
      conn = get(conn, ~p"/")
      cookie = session_cookie(conn, opts)

      # Proves the decode below is doing real verification work rather than
      # reading a value anybody could read. A cookie that decodes under any
      # key is a cookie a client can rewrite.
      assert {nil, %{}} = decode_session(cookie.value, opts, String.duplicate("x", 64))
    end

    test "decodes to the CSRF token and nothing else, after a full session", %{
      conn: conn,
      session_options: %{opts: opts}
    } do
      raw = drive_a_session(conn, Keyword.fetch!(opts, :key))

      assert {:term, session} = decode_session(raw, opts)

      # Non-vacuous, twice over: an empty session would make the difference
      # below trivially empty and the test would pass for the wrong reason,
      # and finding the CSRF token specifically confirms this really is the
      # session Plug wrote rather than a map that decoded by luck.
      assert map_size(session) > 0,
             "the session decoded empty, so the allowlist check proves nothing"

      assert Map.has_key?(session, "_csrf_token"),
             "the session carries no CSRF token: #{inspect(Map.keys(session))}"

      extra = MapSet.difference(MapSet.new(Map.keys(session)), @allowed_session_keys)

      assert MapSet.size(extra) == 0,
             "the session cookie carries #{inspect(MapSet.to_list(extra))}. FR-7 allows the CSRF " <>
               "token and live_socket_id only: no vehicle, VIN, odometer, date, note, preference, " <>
               "garage fragment, anonymous identifier, tab_id, or anything else that correlates " <>
               "one visit to another. Adding a stable identifier needs a new ADR and a privacy " <>
               "re-review, not a put_session/3."

      # A key from the allowlist holding a structure rather than a token is
      # the obvious way to smuggle a payload past a key-name check.
      for {key, value} <- session do
        assert is_binary(value), "session key #{key} holds #{inspect(value)}, not an opaque token"
      end
    end

    test "contains no personal marker after a session that handled personal data", %{
      conn: conn,
      session_options: %{opts: opts}
    } do
      raw = drive_a_session(conn, Keyword.fetch!(opts, :key))

      assert {:term, session} = decode_session(raw, opts)

      decoded = inspect(session)

      for sentinel <- @sentinels do
        refute String.contains?(decoded, sentinel),
               "the session cookie carries #{sentinel}, which was entered as vehicle data in this " <>
                 "session and must never leave the browser"

        # Also checked against the raw cookie: a value appended outside the
        # signed payload would not appear in the decoded map at all.
        refute String.contains?(raw, sentinel)
      end

      # Key names, not values. This catches the leak whose value this test
      # could not have predicted.
      lowered = String.downcase(decoded)

      for fragment <- @prohibited_key_fragments do
        refute String.contains?(lowered, fragment),
               "the session cookie mentions #{inspect(fragment)}: #{decoded}"
      end
    end
  end

  ## Helpers

  defp session_cookie(conn, opts) do
    key = Keyword.fetch!(opts, :key)

    case Map.fetch(conn.resp_cookies, key) do
      {:ok, cookie} ->
        cookie

      :error ->
        flunk(
          "the response set no #{key} cookie, so nothing about the session was asserted. " <>
            "Set cookies: #{inspect(Map.keys(conn.resp_cookies))}"
        )
    end
  end

  # Decodes the cookie exactly the way the endpoint would, through the store
  # that wrote it, so this asserts the bytes on the wire rather than the map
  # the app happened to hold. Pass `secret` to prove the signature matters.
  defp decode_session(raw_cookie, opts, secret \\ nil) do
    secret = secret || DigitalOilStickerWeb.Endpoint.config(:secret_key_base)
    store_opts = Plug.Session.COOKIE.init(opts)

    Plug.Session.COOKIE.get(%Plug.Conn{secret_key_base: secret}, raw_cookie, store_opts)
  end

  # Hydrates a garage carrying every category FR-7 prohibits, then keeps
  # browsing on the same cookie. Returns the raw cookie the browser would hold
  # at the end of it.
  #
  # A LiveView holds no conn and cannot write a cookie, so today this cannot
  # fail by accident — an honest statement of its limit. It fails the day
  # something routes state back through the HTTP session: an on_mount that
  # writes, a controller that remembers the selected vehicle, a redirect that
  # stashes a fragment. That is the change FR-7 forbids and this is here to
  # notice it.
  defp drive_a_session(conn, key) do
    conn = get(conn, ~p"/vehicle/select")
    {:ok, view, _html} = live(conn)

    render_hook(view, "local_store:hydrate", sentinel_envelope())

    # Plug.Session is lazy: a request that writes nothing new sends no
    # Set-Cookie, so the last response in this sweep usually carries none.
    # What the browser holds is the newest value it was ever handed.
    {conn, raw} =
      Enum.reduce(@browse_routes, {conn, set_cookie_value(conn, key)}, fn route, {acc, last} ->
        acc = acc |> recycle() |> get(route)
        {acc, set_cookie_value(acc, key) || last}
      end)

    assert is_binary(raw), "no response in the driven session set a #{key} cookie"

    # One session really was carried across the whole sweep, rather than each
    # request starting from nothing and the scan below reading a cookie that
    # never met the hydrated data.
    assert conn.req_cookies[key] == raw,
           "the last request did not send back the session cookie the sweep established"

    raw
  end

  defp set_cookie_value(conn, key) do
    case conn.resp_cookies do
      %{^key => %{value: value}} -> value
      _ -> nil
    end
  end

  defp sentinel_envelope do
    vehicle_id = "22222222-2222-4222-8222-222222222222"

    %{
      "envelope" => "dos_local",
      "schema_version" => 1,
      "seq" => 4,
      "tab_id" => @sentinel_tab_id,
      "generated_at" => "2026-08-01T00:00:00Z",
      "data" => %{
        "meta" => nil,
        "vehicles" => [
          %{
            "vehicle_id" => vehicle_id,
            "archived" => false,
            "nickname" => @sentinel_nickname,
            "vin_last6" => @sentinel_vin_last6,
            "model_year" => 2019,
            "display_snapshot" => %{
              "year" => 2019,
              "make" => "Toyota",
              "model" => "Camry",
              "build" => "LE"
            },
            "support_status" => "identity_only",
            "maintenance_plan" => nil
          }
        ],
        "events" => [
          %{
            "event_id" => "33333333-3333-4333-8333-333333333333",
            "vehicle_id" => vehicle_id,
            "performed_at" => @sentinel_date <> "T00:00:00Z",
            "odometer_m" => @sentinel_odometer,
            "input_unit" => "mi",
            "provenance_mode" => "manual",
            "notes" => @sentinel_note
          }
        ],
        "readings" => [],
        "usage" => [],
        "reminders" => [],
        "prefs" => nil
      },
      "storage" => %{"mode" => "idb", "boot_hint" => "has_data"}
    }
  end
end
