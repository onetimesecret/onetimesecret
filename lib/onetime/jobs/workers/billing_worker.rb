# lib/onetime/jobs/workers/billing_worker.rb
#
# frozen_string_literal: true

# DEPRECATED: BillingWorker has moved to apps/web/billing/workers/billing_worker.rb
#
# This stub exists for backward compatibility with specs and tools that
# require the old path. The worker is now part of the billing app and is
# only loaded when billing is enabled.
#
# Migration path:
# - Specs should require 'apps/web/billing/workers/billing_worker'
# - The worker is auto-loaded by WorkerCommand when billing is enabled
#
# This file can be removed once all references are updated.

unless ENV['RACK_ENV'] == 'test'
  warn '[DEPRECATION] lib/onetime/jobs/workers/billing_worker.rb is deprecated. ' \
       'BillingWorker has moved to apps/web/billing/workers/billing_worker.rb'
end

# Load from new location if billing is enabled
if Onetime.billing_config&.enabled?
  require_relative '../../../../apps/web/billing/workers/billing_worker'

  # Re-export under old namespace for backward compatibility
  # This allows existing code using Onetime::Jobs::Workers::BillingWorker to work
  module Onetime
    module Jobs
      module Workers
        BillingWorker = Billing::Workers::BillingWorker
      end
    end
  end
end
