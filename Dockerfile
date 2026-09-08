FROM hexpm/elixir:1.18.3-erlang-27.3.4-debian-bookworm-20250623-slim AS builder

WORKDIR /app

ENV MIX_ENV=prod

RUN apt-get update \
    && apt-get install --no-install-recommends -y build-essential git \
    && rm -rf /var/lib/apt/lists/* \
    && mix local.hex --force \
    && mix local.rebar --force

COPY mix.exs mix.lock ./
RUN mix deps.get --only prod \
    && mix deps.compile

COPY config config
COPY lib lib
COPY priv priv

RUN mix compile \
    && mix release

FROM debian:bookworm-20250610-slim

RUN apt-get update \
    && apt-get install --no-install-recommends -y ca-certificates curl libncurses5 libstdc++6 openssl \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd --system lens \
    && useradd --system --gid lens --home-dir /app lens

WORKDIR /app

COPY --from=builder --chown=lens:lens /app/_build/prod/rel/lens ./

ENV HOME=/app \
    LANG=C.UTF-8

USER lens

CMD ["/app/bin/lens", "start"]
