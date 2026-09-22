defmodule DigitalOilStickerWeb.CsrfTest do
  @moduledoc """
  DOS-M09-007 AC-4: a request that would mutate state, and a socket that would
  open a live channel, are refused without a CSRF token.

  Two configurations already exist. `protect_from_forgery` sits in the `:browser`
  pipeline; the endpoint's `socket "/live", ...` runs with the default
  `check_csrf: true` on its transport. Neither is currently asserted anywhere.
  What that leaves is a wire that is right today by construction and rots
  quietly: `plug :protect_from_forgery` deleted in a pipeline refactor still
  compiles, and `check_csrf: false` added to the socket for a debugging session
  is a one-line change that nothing rings a bell about. Both failures look like
  a working app right up to the moment somebody notices that any form on any
  origin can drive our forms.

  ## What this suite asserts

    * The `:browser` pipeline declares `:protect_from_forgery`, and it actually
      fires: a POST/PUT/DELETE conn walked through the same plugs the pipeline
      runs raises `Plug.CSRFProtection.InvalidCSRFTokenError`.

    * The `/live` socket declaration does not disable the transport-level check
      via `check_csrf: false`, and the transport-level session validation
      returns `session: nil` when no `_csrf_token` param accompanies the
      handshake — the exact signal `Phoenix.LiveView.Channel`'s mount refuses
      on. The control case (a matching token) returns the real session.

  ## What this suite does NOT cover

    * It does not drive a real WebSocket upgrade or a browser at a foreign
      origin. Origin refusal is covered by `session_and_origin_test.exs`; this
      file is about the CSRF gate that sits alongside it.
    * It does not enumerate every browser route with a mutating verb, because
      there is none today — the app runs on live_view events and LocalStore
      hooks. The plug is what closes that gap the moment someone adds a
      `post "/vehicle"`.
  """
  use DigitalOilStickerWeb.ConnCase, async: true

  alias DigitalOilStickerWeb.Endpoint
  alias Phoenix.Socket.Transport

  @router_source Path.expand("../../lib/digital_oil_sticker_web/router.ex", __DIR__)
  @endpoint_source Path.expand("../../lib/digital_oil_sticker_web/endpoint.ex", __DIR__)

  # The endpoint's @session_options attribute isn't reachable through
  # Application config at runtime, so we evaluate the literal off disk. Copying
  # its shape into this file would rot silently the moment the real declaration
  # changed — mirroring the pattern in session_and_origin_test.exs.
  defp session_options do
    source = File.read!(@endpoint_source)

    literal =
      case Regex.run(~r/@session_options\s*(\[.*?^  \])/ms, source) do
        [_whole, literal] -> literal
        nil -> flunk("could not find the @session_options literal in #{@endpoint_source}")
      end

    {opts, _bindings} = Code.eval_string(literal)
    assert Keyword.keyword?(opts), "@session_options did not evaluate to a keyword list"
    opts
  end

  # `Phoenix.Socket.Transport.connect_info/4` expects the session already
  # initialised into `{key, store, {csrf_token_key, init}}` — the endpoint's
  # `child_spec` does this once at boot. We do the same construction here so
  # the tests below call the transport with what it would actually see, rather
  # than a raw keyword list that would `FunctionClauseError` before ever
  # reaching the CSRF check.
  defp initialised_session_config do
    opts = session_options()
    key = Keyword.fetch!(opts, :key)
    store = Plug.Session.Store.get(Keyword.fetch!(opts, :store))
    init = store.init(Keyword.drop(opts, [:store, :key]))
    {key, store, {"_csrf_token", init}}
  end

  # A real GET through the endpoint. The response is what the browser would
  # hold: a signed session cookie carrying `_csrf_token` state, and a
  # meta-tag-embedded masked token generated in the same request that the
  # session was written in — the pair that must line up for a POST or a socket
  # handshake to be accepted.
  defp establish_session(conn) do
    conn = get(conn, ~p"/")
    assert conn.status == 200, "the home page must render for these tests to have a session"

    html = response(conn, 200)
    cookie_key = Keyword.fetch!(session_options(), :key)

    cookie_value =
      case conn.resp_cookies do
        %{^cookie_key => %{value: value}} ->
          value

        _ ->
          flunk(
            "the home page set no #{cookie_key} cookie: #{inspect(Map.keys(conn.resp_cookies))}"
          )
      end

    masked_token =
      case Regex.run(~r/name="csrf-token"\s+content="([^"]+)"/, html) do
        [_whole, token] -> token
        nil -> flunk("no csrf-token meta tag in the rendered page")
      end

    %{cookie: cookie_value, cookie_key: cookie_key, token: masked_token}
  end

  # Runs the same three plugs the router applies before `:protect_from_forgery`
  # would fire (`Plug.Session` at the endpoint, then `:fetch_session` in the
  # `:browser` pipeline). This is what the plug expects to see: a fetched
  # session that may or may not carry `_csrf_token`.
  defp session_conn(method, cookie_pair \\ nil, body_params \\ nil) do
    opts = session_options()
    session_opts = Plug.Session.init(opts)
    endpoint_secret = Endpoint.config(:secret_key_base)

    conn =
      Plug.Test.conn(method, "/", body_params || %{})
      |> Map.put(:secret_key_base, endpoint_secret)

    conn =
      case cookie_pair do
        {key, value} -> Plug.Test.put_req_cookie(conn, key, value)
        nil -> conn
      end

    conn
    |> Plug.Conn.fetch_cookies()
    |> Plug.Session.call(session_opts)
    |> Plug.Conn.fetch_session()
  end

  # A minimal Plug.Conn approximating the initial HTTP request the WebSocket /
  # LongPoll transport sees before upgrade. `Transport.connect_info/4` reads
  # `conn.cookies[key]` and `conn.params["_csrf_token"]`; nothing else in this
  # function's body cares whether the request "arrived" on a WebSocket vs an
  # HTTP GET.
  defp handshake_conn(cookie_pair, params) do
    conn =
      Plug.Test.conn(:get, "/live/websocket")
      |> Map.put(:params, params)

    conn =
      case cookie_pair do
        {key, value} -> Plug.Test.put_req_cookie(conn, key, value)
        nil -> conn
      end

    Plug.Conn.fetch_cookies(conn)
  end

  describe "the :browser pipeline runs :protect_from_forgery (AC-4, HTTP clause)" do
    test "the pipeline declaration wires the plug into :browser" do
      # Source scan rather than an @-attribute read: the pipeline is a compile-
      # time macro, its plug list is not exposed at runtime, and a POST route
      # to prove it end-to-end does not exist in this app. Deleting the line
      # would still compile, still route, still serve — the source is the only
      # place a drift shows.
      router = File.read!(@router_source)

      case Regex.run(~r/pipeline\s+:browser\s+do(.*?)end/s, router) do
        [_whole, body] ->
          assert body =~ ~r/plug\s+:protect_from_forgery/,
                 ":browser pipeline does not run :protect_from_forgery. Every form driven " <>
                   "through this pipeline would accept a POST from any origin. Body was:\n" <>
                   body

        nil ->
          flunk("could not locate `pipeline :browser do ... end` in #{@router_source}")
      end
    end

    test "a POST without a CSRF token raises InvalidCSRFTokenError even with a fresh session",
         %{conn: conn} do
      # Uses a real established session (with `_csrf_token` state written into
      # it by the GET) to prove the failure is "the client token is missing",
      # not "there is no session to check against" — which would pass for the
      # wrong reason.
      %{cookie: cookie, cookie_key: key} = establish_session(conn)
      conn = session_conn(:post, {key, cookie})

      assert_raise Plug.CSRFProtection.InvalidCSRFTokenError, fn ->
        Phoenix.Controller.protect_from_forgery(conn, [])
      end
    end

    test "a PUT without a CSRF token is rejected", %{conn: conn} do
      %{cookie: cookie, cookie_key: key} = establish_session(conn)
      conn = session_conn(:put, {key, cookie})

      assert_raise Plug.CSRFProtection.InvalidCSRFTokenError, fn ->
        Phoenix.Controller.protect_from_forgery(conn, [])
      end
    end

    test "a DELETE without a CSRF token is rejected", %{conn: conn} do
      %{cookie: cookie, cookie_key: key} = establish_session(conn)
      conn = session_conn(:delete, {key, cookie})

      assert_raise Plug.CSRFProtection.InvalidCSRFTokenError, fn ->
        Phoenix.Controller.protect_from_forgery(conn, [])
      end
    end

    test "a POST without any session cookie at all is still rejected" do
      # The plug's fallback: no session state means no state to compare against,
      # and the request should still be refused rather than waved through with
      # nothing to check. This is the case a form on a foreign origin produces.
      conn = session_conn(:post)

      assert_raise Plug.CSRFProtection.InvalidCSRFTokenError, fn ->
        Phoenix.Controller.protect_from_forgery(conn, [])
      end
    end

    test "a GET without a CSRF token is accepted (control)" do
      # If GETs also raised, every failure above would prove "the plug rejects
      # anything without a token" rather than "the plug rejects mutating
      # methods without a token", which is the property AC-4 actually asks for.
      conn = session_conn(:get)

      # Runs without raising.
      _ = Phoenix.Controller.protect_from_forgery(conn, [])
    end

    test "a POST WITH a matching CSRF token is accepted (control)", %{conn: conn} do
      # Proves the raises above are about the missing token, not a mistake in
      # the plug construction that would refuse every POST regardless.
      %{cookie: cookie, cookie_key: key, token: masked_token} = establish_session(conn)
      conn = session_conn(:post, {key, cookie}, %{"_csrf_token" => masked_token})

      # Runs without raising.
      _ = Phoenix.Controller.protect_from_forgery(conn, [])
    end
  end

  describe "the /live socket handshake refuses without CSRF (AC-4, socket clause)" do
    test "the endpoint's socket declaration does not disable the check" do
      # `Transport.connect_info/4` defaults `check_csrf` to true, but any of
      # `check_csrf: false` in the socket options, in the transport options,
      # or a stray override for a debug session would silently open the socket
      # to anyone. The tests below only exercise the code path — this one
      # guards the configuration that puts the code path there.
      endpoint = File.read!(@endpoint_source)

      refute endpoint =~ ~r/check_csrf:\s*false/,
             "endpoint declares check_csrf: false somewhere, which disables the socket-level " <>
               "CSRF gate for the LiveView handshake."

      assert endpoint =~ ~r/socket\s+"\/live",\s+Phoenix\.LiveView\.Socket/,
             "the /live socket declaration is missing — the tests below assume it exists"

      # The `connect_info` block may carry other keys (peer_data, x_headers) —
      # what has to be there for the transport's CSRF check to have anything to
      # compare against is `session: @session_options`.
      assert endpoint =~ ~r/connect_info:\s*\[[^\]]*session:\s*@session_options/,
             "the /live socket does not pass @session_options to connect_info, so the " <>
               "transport cannot validate the CSRF token against the session at handshake"
    end

    test "session is nil when no _csrf_token param accompanies the handshake", %{conn: conn} do
      %{cookie: cookie, cookie_key: key} = establish_session(conn)
      handshake = handshake_conn({key, cookie}, %{})

      connect_info =
        Transport.connect_info(handshake, Endpoint, session: initialised_session_config())

      assert connect_info[:session] == nil,
             "handshake with a valid session cookie but no _csrf_token param resolved to a " <>
               "usable session. LiveView's channel mount treats nil as `stale` and refuses; a " <>
               "non-nil here means the socket would open for any caller who could steal or " <>
               "spoof the cookie."
    end

    test "session is nil when the _csrf_token param is wrong", %{conn: conn} do
      %{cookie: cookie, cookie_key: key} = establish_session(conn)

      # 56 bytes — same length as a real masked token so the check reaches
      # `valid_masked_token?` and fails on content, not on the outer length
      # match (which would prove nothing about the actual comparison).
      spoofed = String.duplicate("a", 56)
      handshake = handshake_conn({key, cookie}, %{"_csrf_token" => spoofed})

      connect_info =
        Transport.connect_info(handshake, Endpoint, session: initialised_session_config())

      assert connect_info[:session] == nil,
             "handshake with a fabricated _csrf_token was accepted. The transport is either " <>
               "not comparing the token against the session state, or is accepting any 56-byte " <>
               "string as valid."
    end

    test "session is nil when the cookie is missing entirely", %{conn: conn} do
      # A request that never went through the browser (a raw curl to the
      # socket) has no session to validate against; the transport must not
      # invent one.
      %{token: masked_token} = establish_session(conn)
      handshake = handshake_conn(nil, %{"_csrf_token" => masked_token})

      connect_info =
        Transport.connect_info(handshake, Endpoint, session: initialised_session_config())

      assert connect_info[:session] == nil,
             "handshake with a client CSRF token but no session cookie resolved to a session"
    end

    test "session is populated when the _csrf_token matches (control)", %{conn: conn} do
      # The positive case, so the three refusals above are not passing because
      # the transport is broken and refusing every handshake.
      %{cookie: cookie, cookie_key: key, token: masked_token} = establish_session(conn)
      handshake = handshake_conn({key, cookie}, %{"_csrf_token" => masked_token})

      connect_info =
        Transport.connect_info(handshake, Endpoint, session: initialised_session_config())

      session = connect_info[:session]

      assert is_map(session),
             "handshake with the browser's own session cookie and matching CSRF token was " <>
               "refused (session was #{inspect(session)}). The gate rejects everything, which " <>
               "would break the app in production, not just this test."

      assert Map.has_key?(session, "_csrf_token"),
             "the returned session does not carry the CSRF state key the transport was checking: " <>
               inspect(Map.keys(session))
    end
  end
end
