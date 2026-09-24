# spec/cli/email_sync_feedback_command_spec.rb
#
# frozen_string_literal: true

# CLI adapter tests for `bin/ots email sync-feedback`.
#
# The pull itself belongs to Onetime::Operations::Email::SyncProviderFeedback
# and its provider fetchers; this covers the operator-input contract the
# command owns. A negative --limit used to travel all the way into
# `records.first(limit)` in every provider fetcher, which raises on a negative
# size — so the value is rejected at the boundary, before any provider call.
#
# NOTE for later PRs: append `describe` blocks to this file rather than
# creating a sibling spec.
#
# Run: tests/lanes/run unit --only spec/cli/email_sync_feedback_command_spec.rb

require_relative 'cli_spec_helper'

RSpec.describe 'Email Sync Feedback Command', type: :cli do
  describe '--limit validation' do
    it 'rejects a negative --limit before reaching a provider' do
      expect(Onetime::Operations::Email::SyncProviderFeedback).not_to receive(:new)

      output = run_cli_command_quietly('email', 'sync-feedback', '--limit', '-1')
      expect(output[:stderr]).to include('--limit must be a positive integer')
      expect(last_exit_code).to eq(1)
    end

    it 'rejects a zero --limit rather than pulling nothing' do
      output = run_cli_command_quietly('email', 'sync-feedback', '--limit', '0')
      expect(output[:stderr]).to include('--limit must be a positive integer')
      expect(last_exit_code).to eq(1)
    end
  end
end
