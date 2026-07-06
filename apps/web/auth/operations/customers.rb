# apps/web/auth/operations/customers.rb
#
# frozen_string_literal: true

# Aggregator for the customer admin operations (epic #20). These are the single
# implementation of each customer admin verb; the colonel API Logic classes and
# the `bin/ots customers *` CLI commands are thin adapters over them.
#
# Placement follows decision D3 (see lib/onetime/operations/README.md): customer
# ops are auth-domain-owned, so they live app-scoped under
# apps/web/auth/operations/customers/ as Auth::Operations::Customers::*.

require_relative 'customers/list'
require_relative 'customers/show'
require_relative 'customers/set_role'
require_relative 'customers/set_verification'
require_relative 'customers/purge'
require_relative 'customers/doctor'
