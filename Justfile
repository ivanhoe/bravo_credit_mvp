set shell := ["zsh", "-cu"]

default:
  @just --list

db-up:
  docker compose up -d postgres

app-up:
  docker compose --profile app up --build

app-down:
  docker compose down

db-down:
  docker compose down

db-logs:
  docker compose logs -f postgres

db-ps:
  docker compose ps

setup:
  mix setup

seed-demo:
  mix run priv/repo/seeds.exs

demo-tokens:
  mix bravo.demo.tokens

demo-tokens-env:
  mix bravo.demo.tokens --env

server:
  mix phx.server

test:
  mix test

lint:
  mix format --check-formatted
  mix credo --strict

check:
  just lint
  just test

ecto-create:
  mix ecto.create

ecto-migrate:
  mix ecto.migrate
