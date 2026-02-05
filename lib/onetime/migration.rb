# lib/onetime/migration.rb
#
# frozen_string_literal: true

# Migration infrastructure is provided by Familia gem (v2.1+)
#
# The original OTS migration classes (BaseMigration, ModelMigration,
# PipelineMigration) were upstreamed to Familia::Migration in v2.1.
#
# Use directly:
#   - Familia::Migration::Base
#   - Familia::Migration::Model
#   - Familia::Migration::Pipeline
#   - Familia::Migration::Runner
#
# @see https://github.com/delano/familia
require 'familia/migration'
