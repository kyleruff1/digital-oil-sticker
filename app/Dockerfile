# This file is based on these images:
#
#   - https://hub.docker.com/r/hexpm/elixir/tags - for the builder image
#     E.g.: docker.io/hexpm/elixir:1.18-erlang-28.4-debian-trixie-20260610-slim
#   - https://hub.docker.com/_/debian/tags?name=trixie-20260610-slim - for the runner image
#     E.g.: docker.io/debian:trixie-20260610-slim
#
# Find builder and runner images on Docker Hub or on Hex's Build Server (Bob).
# We recommend using Bob's Web UI to find recent tags:
#
#   - https://bob.hex.pm/docker
#
# We suggest using the same Debian version for both the builder and runner images.
#
# We suggest Debian/Ubuntu instead of Alpine to avoid production compatibility issues
# (such as DNS resolution failures, and dynamically linked NIFs/precompiled binaries).
#
# For finding packages in Debian, search on https://packages.debian.org/.

# Pinned by DIGEST, not by tag. A tag is a moving target — `trixie-20260610-slim`
# can be republished — so two builds of the same commit would not be the same
# image. The tag is kept alongside the digest as documentation of what the
# digest was, and both are recorded in the release ledger.
#
# To advance a pin, resolve the new digest and update BOTH the tag comment and
# the digest in the same commit:
#   curl -s "https://auth.docker.io/token?service=registry.docker.io&scope=repository:library/debian:pull"
ARG ELIXIR_VERSION=1.18
ARG OTP_VERSION=28.4
ARG DEBIAN_VERSION=trixie-20260610-slim

# hexpm/elixir:1.18-erlang-28.4-debian-trixie-20260610-slim resolved 2026-08-01
ARG BUILDER_IMAGE="docker.io/hexpm/elixir@sha256:5d6cb10d27bd00e3c51cd4a3d2f7b8cc7fcd60dfae0b2d4feff43cb28bd4af05"
# debian:trixie-20260610-slim resolved 2026-08-01
ARG RUNNER_IMAGE="docker.io/debian@sha256:4e401d95de7083948053197a9c3913343cd06b706bf15eb6a0c3ccd26f436a0e"

FROM ${BUILDER_IMAGE} AS builder

# install build dependencies
RUN apt-get update \
  && apt-get install -y --no-install-recommends build-essential git \
  && rm -rf /var/lib/apt/lists/*

# prepare build dir
WORKDIR /app

# install hex + rebar
RUN mix local.hex --force \
  && mix local.rebar --force

# set build ENV
ENV MIX_ENV="prod"

# install mix dependencies
COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV
RUN mkdir config

# copy compile-time config files before we compile dependencies
# to ensure any relevant config change will trigger the dependencies
# to be re-compiled.
COPY config/config.exs config/${MIX_ENV}.exs config/
RUN mix deps.compile

RUN mix assets.setup

COPY priv priv

COPY lib lib

# The catalog artifact IS the product. Verify it before anything is built on
# top of it: a truncated, swapped, or stale artifact would otherwise ship and
# stay invisible until a user got a wrong answer. Each failure mode gets its
# own message, because "catalog check failed" is not actionable.
RUN set -eu;     manifest="priv/catalog/catalog-manifest.json";     catalog="priv/catalog/catalog.sqlite3";     test -f "$manifest" || { echo "FAIL: $manifest is absent — the catalog build did not run"; exit 1; };     test -f "$catalog"  || { echo "FAIL: $catalog is absent — no catalog to serve"; exit 1; };     expected_sha="$(sed -n 's/.*"payload_sha256"[[:space:]]*:[[:space:]]*"\([0-9a-f]*\)".*//p' "$manifest")";     expected_size="$(sed -n 's/.*"size"[[:space:]]*:[[:space:]]*\([0-9]*\).*//p' "$manifest" | head -1)";     expected_schema="$(sed -n 's/.*"schema_version"[[:space:]]*:[[:space:]]*"\([0-9]*\)".*//p' "$manifest" | head -1)";     test -n "$expected_sha" || { echo "FAIL: manifest carries no payload_sha256"; exit 1; };     actual_size="$(wc -c < "$catalog")";     test "$actual_size" = "$expected_size" || { echo "FAIL: catalog is $actual_size bytes, manifest says $expected_size — truncated or replaced"; exit 1; };     actual_sha="$(sha256sum "$catalog" | cut -d" " -f1)";     test "$actual_sha" = "$expected_sha" || { echo "FAIL: catalog sha256 $actual_sha does not match manifest $expected_sha"; exit 1; };     case "$expected_schema" in       1) : ;;       *) echo "FAIL: catalog schema_version '"'"'$expected_schema'"'"' is outside the window this app supports"; exit 1 ;;     esac;     echo "catalog verified: sha256 $actual_sha, $actual_size bytes, schema $expected_schema"

# Compile the release
RUN mix compile

COPY assets assets

# compile assets
RUN mix assets.deploy

# Changes to config/runtime.exs don't require recompiling the code
COPY config/runtime.exs config/

# Release identity, baked at build time so a running machine can say which
# commit it is without shelling out to git (which is not in the runtime image,
# and would be answering about the wrong tree anyway).
ARG GIT_SHA=unknown
ARG BUILD_TIMESTAMP=unknown
ENV GIT_SHA=${GIT_SHA}
ENV BUILD_TIMESTAMP=${BUILD_TIMESTAMP}

COPY rel rel
RUN mix release

# start a new build stage so that the final image will only contain
# the compiled release and other runtime necessities
FROM ${RUNNER_IMAGE} AS final

RUN apt-get update \
  && apt-get install -y --no-install-recommends libstdc++6 openssl libncurses6 locales ca-certificates \
  && rm -rf /var/lib/apt/lists/*

# Set the locale
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen \
  && locale-gen

ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

WORKDIR "/app"
RUN chown nobody /app

# set runner ENV
ENV MIX_ENV="prod"

# Carried into the runtime stage: ARGs do not cross a FROM boundary.
ARG GIT_SHA=unknown
ARG BUILD_TIMESTAMP=unknown
ENV GIT_SHA=${GIT_SHA}
ENV BUILD_TIMESTAMP=${BUILD_TIMESTAMP}

# Only copy the final release from the build stage
COPY --from=builder --chown=nobody:root /app/_build/${MIX_ENV}/rel/digital_oil_sticker ./

# The catalog artifact is read-only data baked into the image: root-owned and
# 0444 so the nobody-running app cannot write it (fourth write-prevention
# layer after read_only: true, mode: :readonly, and PRAGMA query_only).
USER root
RUN set -eux; \
    catalog="$(find /app/lib -path '*/priv/catalog/catalog.sqlite3' | head -1)"; \
    test -n "$catalog"; \
    chown root:root "$catalog"; \
    chmod 0444 "$catalog"

USER nobody

# If using an environment that doesn't automatically reap zombie processes, it is
# advised to add an init process such as tini via `apt-get install`
# above and adding an entrypoint. See https://github.com/krallin/tini for details
# ENTRYPOINT ["/tini", "--"]

CMD ["/app/bin/server"]
