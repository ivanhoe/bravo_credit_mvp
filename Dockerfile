FROM elixir:1.19.5-otp-28 AS build

RUN apt-get update -y && \
    apt-get install -y --no-install-recommends build-essential git ca-certificates && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

RUN mix local.hex --force && mix local.rebar --force

ENV MIX_ENV=prod

COPY mix.exs mix.lock ./
COPY config config

RUN mix deps.get --only $MIX_ENV
RUN mix deps.compile

COPY priv priv
COPY lib lib

RUN mix compile
RUN mix release

FROM debian:trixie-slim AS app

RUN apt-get update -y && \
    apt-get install -y --no-install-recommends openssl libstdc++6 libncurses6 ca-certificates && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

ENV LANG=C.UTF-8
ENV MIX_ENV=prod
ENV PHX_SERVER=true

COPY --from=build /app/_build/prod/rel/bravo_credit ./
COPY config/countries config/countries
COPY docker/entrypoint.sh /usr/local/bin/bravo-credit-entrypoint

RUN chmod +x /usr/local/bin/bravo-credit-entrypoint

EXPOSE 4000

ENTRYPOINT ["bravo-credit-entrypoint"]
CMD ["bin/bravo_credit", "start"]
