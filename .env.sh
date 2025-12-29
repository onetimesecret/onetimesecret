#!/usr/bin/env bash
# .env.sh

# A convenience wrapper so that .env is just a basic environment file
# that is compatible everywhere while still using the auto-export
# functionality the shell gods left for us.

# set -a enables automatic export mode. All variable assignments between
# here and and set +a will be exported to child processes without needing
# 'export' keyword.
set -a

# Load the vars
[ -f .env ] && . .env

# Set +a restores default behavior where variables must be explicitly exported
set +a
