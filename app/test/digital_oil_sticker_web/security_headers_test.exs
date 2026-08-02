defmodule DigitalOilStickerWeb.SecurityHeadersTest do
  @moduledoc """
  The ADR-0004 header set, asserted against what the server actually sends
  (DOS-M09-007 FR-2, FR-3, FR-4).

  Revision 1.0.0 kept personal data safe with a physical fact: the endpoint
  bound `127.0.0.1`, so nothing off-device could reach it. That fact is gone.
  What replaces it is configuration — a plug, a header string, a config key —
  and configuration rots quietly. A CSP directive dropped in a refactor does
  not raise; it just stops constraining anything, and nobody finds out until
  an injected script has already run.

  So every assertion here goes through a real request. Reading
  `SecurityHeaders.policy/1` alone would prove the module composes a good
  string, not that the string reaches the wire — and there are three places
  between the two where it can be lost:

    * the plug could be moved below the router, so responses that never reach a
      pipeline (a 404, a parser error) go out bare;
    * Phoenix's `put_secure_browser_headers` could be re-added to the `:browser`
      pipeline, where it serves a *second*, weaker CSP beside ours and a
      `referrer-policy` that leaks the origin — this suite found exactly that
      and the pipeline no longer runs it;
    * the layout's nonce and the header's nonce could drift apart, which fails
      *closed* — the theme script is silently blocked and the page flashes the
      wrong theme, with nothing in the logs.

  ## What these tests do NOT cover

  They assert what the server sends. They cannot assert that a browser honours
  it. And while the policy ships report-only (FR-3), a browser *reports*
  violations rather than blocking them, so a passing suite here means the
  policy is correct and inert, not correct and enforced. Flipping `enforce:
  true` is what makes it load-bearing, and that flip is covered below.

  `async: false` on purpose: the enforce test mutates application env, which is
  global, and a concurrent request in another test would read the flipped value.
  """
  use DigitalOilStickerWeb.ConnCase, async: false

  alias DigitalOilStickerWeb.Hosts
  alias DigitalOilStickerWeb.Plugs.SecurityHeaders

  @report_only "content-security-policy-report-only"
  @enforced "content-security-policy"

  # The CSP directives whose source list FR-2 pins exactly. script-src and
  # connect-src are checked separately because they legitimately carry more —
  # the per-request nonce, the socket origin — and everything else is compared
  # for equality, because "img-src 'self' data: https://cdn.example" satisfies
  # a contains-check while having given away the whole point of the directive.
  @exact_directives %{
    "default-src" => ["'self'"],
    "style-src" => ["'self'"],
    "img-src" => ["'self'", "data:"],
    "font-src" => ["'self'"],
    "frame-ancestors" => ["'none'"],
    "base-uri" => ["'self'"],
    "form-action" => ["'self'"],
    "object-src" => ["'none'"]
  }

  setup %{conn: conn} do
    conn = get(conn, ~p"/")
    assert conn.status == 200, "the home page must render for these headers to mean anything"

    policy = only_header(conn, @report_only)

    %{conn: conn, html: response(conn, 200), policy: policy, directives: directives(policy)}
  end

  describe "FR-2: the ADR-0004 content security policy is served on a real response" do
    test "every directive ADR-0004 names is present", %{directives: directives} do
      # Absence is the failure mode that matters. A missing `object-src` does
      # not error, it just permits <object> again, and `default-src` does not
      # cover `form-action` or `frame-ancestors` at all — those fall back to
      # "anything" when omitted.
      for {name, sources} <- @exact_directives do
        assert Map.has_key?(directives, name),
               "the served CSP has no #{name} directive, so that resource type is unconstrained"

        assert Map.fetch!(directives, name) == sources,
               "#{name} is #{inspect(Map.fetch!(directives, name))}, ADR-0004 pins it to #{inspect(sources)}"
      end

      # The loop above walks the test's own expectation list, so deleting a row
      # from @exact_directives would quietly shrink what is checked. Comparing
      # the full directive set closes that, and catches the other direction too:
      # a directive added to the served policy that no one here has reviewed.
      assert MapSet.new(Map.keys(directives)) ==
               MapSet.new(["script-src", "connect-src" | Map.keys(@exact_directives)]),
             "the served CSP directive set is #{inspect(Enum.sort(Map.keys(directives)))}, " <>
               "which is not the ADR-0004 set"
    end

    test "script-src is first-party plus exactly one per-request nonce", %{directives: directives} do
      sources = Map.fetch!(directives, "script-src")

      assert "'self'" in sources
      assert Enum.any?(sources, &String.starts_with?(&1, "'nonce-"))

      # Length is the assertion doing the work: it is what catches a source
      # appended later. A CDN host or a hash added here would widen the one
      # directive that decides whether injected script runs.
      assert length(sources) == 2,
             "script-src carries more than 'self' and a nonce: #{inspect(sources)}"
    end

    test "connect-src reaches our own websocket and nothing third-party", %{
      directives: directives
    } do
      sources = Map.fetch!(directives, "connect-src")

      assert "'self'" in sources

      # 'self' does not cover a websocket — different scheme — so without this
      # entry our own policy blocks our own LiveView socket. That is the exact
      # failure Hosts.connect_src/0 exists to prevent.
      assert "wss://#{Hosts.canonical()}" in sources,
             "connect-src does not permit wss://#{Hosts.canonical()}, the host this deployment " <>
               "serves. PHX_HOST and Hosts.production/0 have drifted apart and the LiveView " <>
               "socket will be blocked by our own CSP. Got: #{inspect(sources)}"

      # Nothing else. An https:// entry here is how telemetry, error reporting
      # or an analytics beacon would get permission to leave the origin with
      # whatever the page can read (INV-26).
      production = Hosts.production()

      for source <- sources -- ["'self'"] do
        assert String.starts_with?(source, "wss://"),
               "connect-src source #{source} is not a wss:// origin"

        host = String.replace_prefix(source, "wss://", "")

        assert host in production,
               "connect-src permits #{source}, which is not one of our hosts (#{inspect(production)})"
      end
    end

    test "'unsafe-inline' and 'unsafe-eval' appear in no directive of any policy served", %{
      conn: conn
    } do
      policies =
        Enum.filter(conn.resp_headers, fn {name, _value} ->
          name in [@report_only, @enforced]
        end)

      # Guard against a vacuous pass: if no policy header was served at all,
      # "contains no unsafe-inline" is trivially true and meaningless.
      assert policies != [], "no content-security-policy header of any kind was served"

      for {name, value} <- policies, token <- ["'unsafe-inline'", "'unsafe-eval'"] do
        refute String.contains?(value, token),
               "RELEASE BLOCKER (FR-2): #{name} contains #{token}. FR-2 permits a per-request " <>
                 "nonce as the resolution for inline content and names a blanket relaxation a " <>
                 "release blocker — this build must not ship. Policy: #{value}"
      end
    end

    test "the policy on the wire is the one policy/1 reports", %{policy: policy} do
      # policy/1 is what a reviewer, a runbook, or a future report-sink test
      # will read. If the plug ever stops using it, that function becomes a
      # description of a policy nobody is served.
      assert policy == SecurityHeaders.policy(nonce_from(policy))
    end
  end

  describe "FR-2: the nonce" do
    test "is different on every request", %{policy: first} do
      second = build_conn() |> get(~p"/") |> only_header(@report_only)

      # Two reasons this matters, and either alone would be enough. A fixed
      # nonce is a password an attacker reads out of the header and copies into
      # the injected tag, which is 'unsafe-inline' with extra steps. And a value
      # stable across a visit is a correlatable identifier — the thing INV-26
      # says this application does not hand out.
      refute nonce_from(first) == nonce_from(second),
             "the CSP nonce did not change between two requests"
    end

    test "is long enough not to be guessed", %{policy: policy} do
      # 16 random bytes, base64 without padding. Short enough to be worth
      # asserting because a truncation here is invisible and fatal.
      assert String.length(nonce_from(policy)) >= 20
    end

    test "matches the nonce on the rendered inline script", %{html: html, policy: policy} do
      nonce = nonce_from(policy)
      inline = for tag <- script_tags(html), not String.contains?(tag, "src="), do: tag

      # Without this the test is vacuous: if the theme bootstrap were ever
      # inlined into app.js, "every inline script carries the nonce" would pass
      # over an empty list while proving nothing.
      assert inline != [],
             "the page rendered no inline <script>, so the nonce path is untested — if the " <>
               "theme bootstrap moved, delete this test rather than let it pass empty"

      for tag <- inline do
        assert String.contains?(tag, ~s(nonce="#{nonce}")),
               "an inline script carries no nonce matching the CSP header, so the browser will " <>
                 "silently refuse to run it (the theme bootstrap runs before first paint; when " <>
                 "it is blocked the page flashes the wrong theme and nothing is logged). " <>
                 "Header nonce: #{nonce}. Tag: #{tag}"
      end
    end
  end

  describe "FR-3: report-only first, enforced second" do
    test "the default posture is report-only", %{conn: conn} do
      # FR-3 requires the policy ship in report-only mode and be reviewed before
      # it blocks anything. Shipping straight to enforcement is how a directive
      # nobody validated takes the application's own assets down.
      assert get_resp_header(conn, @report_only) != [],
             "no #{@report_only} header was served; FR-3 requires the policy report before it enforces"
    end

    test "the report-only phase serves no second, weaker enforced policy", %{conn: conn} do
      # A regression guard for a defect this suite found on the real response.
      # Phoenix's put_secure_browser_headers adds "content-security-policy:
      # base-uri 'self'; frame-ancestors 'self';" whenever no header of that
      # exact name is already set. In report-only mode ours is named
      # content-security-policy-report-only, so Phoenix's policy was added
      # alongside it — and Phoenix's was the one actually ENFORCED, while the
      # strict one only reported. frame-ancestors was therefore effectively
      # 'self', not 'none': per spec a browser that honours CSP frame-ancestors
      # ignores X-Frame-Options, so the DENY we also send did not rescue it.
      #
      # It would also have hidden itself. The moment enforce: true lands, our
      # header occupies the name, Phoenix skips it, and the symptom vanishes —
      # so the weak window was exactly the review period FR-3 exists to create.
      #
      # Re-adding :put_secure_browser_headers to the :browser pipeline brings it
      # straight back, which is what this asserts against.
      assert get_resp_header(conn, @enforced) == [],
             "a second, enforced CSP is served alongside the report-only one: " <>
               "#{inspect(get_resp_header(conn, @enforced))} — while the strict policy is only " <>
               "reporting, that weak one is what the browser actually enforces"
    end

    test "flipping enforce in config renames the header and changes nothing else" do
      original = Application.get_env(:digital_oil_sticker, SecurityHeaders)

      on_exit(fn ->
        case original do
          nil -> Application.delete_env(:digital_oil_sticker, SecurityHeaders)
          value -> Application.put_env(:digital_oil_sticker, SecurityHeaders, value)
        end
      end)

      Application.put_env(:digital_oil_sticker, SecurityHeaders, enforce: true)

      conn = get(build_conn(), ~p"/")

      assert get_resp_header(conn, @report_only) == [],
             "the report-only header is still served while enforcing, so a browser gets both"

      enforced = only_header(conn, @enforced)

      # The point of FR-3 is that what was reviewed in report-only mode is what
      # later blocks. Same directives, same sources, only the nonce differs
      # because it is per-request.
      assert Map.delete(directives(enforced), "script-src") ==
               Map.delete(directives(SecurityHeaders.policy("x")), "script-src"),
             "the enforced policy differs from the reported one, so the review proved nothing"
    end
  end

  describe "FR-4: the rest of the header set" do
    test "referrer-policy is exactly no-referrer, not Phoenix's default", %{conn: conn} do
      # put_secure_browser_headers sets strict-origin-when-cross-origin, which
      # still leaks our origin to every outbound link. INV-22 wants nothing
      # leaving with the request at all. The equality (rather than a membership
      # check) is deliberate: it fails both if Phoenix's default replaces ours
      # and if some plug adds a second referrer-policy beside it, in which case
      # which one applies is a browser detail nobody here decided.
      assert get_resp_header(conn, "referrer-policy") == ["no-referrer"],
             "referrer-policy is #{inspect(get_resp_header(conn, "referrer-policy"))} — " <>
               "Phoenix's strict-origin-when-cross-origin default has won over ours, or is " <>
               "being served alongside it"
    end

    test "x-content-type-options is nosniff", %{conn: conn} do
      assert get_resp_header(conn, "x-content-type-options") == ["nosniff"]
    end

    test "permissions-policy denies every capability FR-4 names", %{conn: conn} do
      policy = only_header(conn, "permissions-policy")

      # This application asks a browser for nothing beyond localStorage. A
      # capability left undeclared is a capability an injected script may
      # prompt for, and a geolocation prompt from an oil-change app is both a
      # privacy failure and a trust failure.
      for capability <- ~w(geolocation camera microphone payment) do
        assert policy =~ ~r/\b#{capability}=\(\s*\)/,
               "permissions-policy does not deny #{capability}: #{policy}"
      end
    end

    test "x-frame-options is DENY", %{conn: conn} do
      # Belt to frame-ancestors' braces, for the older browsers that read one
      # and not the other. Note it is only a backstop: a browser that honours a
      # CSP frame-ancestors directive ignores this header entirely, so it does
      # not rescue a weak frame-ancestors (see the second-policy test above).
      assert get_resp_header(conn, "x-frame-options") == ["DENY"]
    end
  end

  describe "responses that never reach a router pipeline" do
    test "a 404 still carries the full header set" do
      # The plug sits in the endpoint above the router precisely so this holds.
      # A 404 never reaches a pipeline, so a header set owned by the :browser
      # pipeline would be entirely absent here — and error responses are the
      # ones an attacker probes with. Same for the /health, /ready and /version
      # routes, which go through :api and would miss a :browser-only set.
      conn = get(build_conn(), "/no-such-path")

      assert conn.status == 404

      assert get_resp_header(conn, @report_only) != [],
             "a 404 was served with no content-security-policy at all"

      assert get_resp_header(conn, "referrer-policy") == ["no-referrer"]
      assert get_resp_header(conn, "x-content-type-options") == ["nosniff"]
      assert get_resp_header(conn, "permissions-policy") != []
      assert get_resp_header(conn, "x-frame-options") == ["DENY"]
    end
  end

  # Fetches a header and insists there is exactly one of it. Two values for the
  # same header is not a hypothetical: a plug that appends rather than replaces
  # produces one, and browsers then apply the most restrictive CSP, or the
  # first referrer-policy, depending on the header and the browser.
  defp only_header(conn, name) do
    case get_resp_header(conn, name) do
      [value] ->
        value

      [] ->
        flunk("no #{name} header was served")

      many ->
        flunk("#{name} was served #{length(many)} times: #{inspect(many)}")
    end
  end

  defp directives(policy) do
    policy
    |> String.split(";", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Map.new(fn directive ->
      [name | sources] = String.split(directive, ~r/\s+/, trim: true)
      {name, sources}
    end)
  end

  defp nonce_from(policy) do
    case Regex.run(~r/'nonce-([^']+)'/, policy) do
      [_, nonce] -> nonce
      nil -> flunk("the served policy carries no nonce: #{policy}")
    end
  end

  defp script_tags(html) do
    ~r/<script\b[^>]*>/
    |> Regex.scan(html)
    |> Enum.map(&hd/1)
  end
end
