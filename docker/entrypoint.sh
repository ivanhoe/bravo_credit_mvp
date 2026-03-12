#!/bin/sh
set -eu

bin/bravo_credit eval "BravoCredit.Release.create"
bin/bravo_credit eval "BravoCredit.Release.migrate"
exec "$@"
