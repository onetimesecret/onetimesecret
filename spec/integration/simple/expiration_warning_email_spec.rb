# spec/integration/simple/expiration_warning_email_spec.rb
#
# frozen_string_literal: true

# The expiration-warning email links to the owner's receipt page.
#
# ExpirationWarningJob used to send receipt.secret_shortid (8 characters)
# under :secret_key, and the template built /secret/<short id>. No route
# resolves a short id, so every link in every warning was dead. The payload
# now carries the receipt identifier and the template links to
# /receipt/<identifier>. This drives the job over a real receipt and checks
# that the identifier it sends loads that receipt and that the rendered mail
# links to it.

require_relative '../integration_spec_helper'

RSpec.describe 'Expiration warning email link', type: :integration do
  before(:all) do
    Onetime.boot! :test
  end

  let(:owner) do
    Onetime::Customer.new(email: "expiring-owner-#{SecureRandom.hex(8)}@example.com").tap(&:save)
  end

  # Two days: not below the default min_ttl_hours (48), so spawn_pair puts the
  # receipt on the expiration timeline the job scans.
  let(:lifespan) { 2 * 24 * 3600 }
  let(:receipt) { Onetime::Receipt.spawn_pair(owner.objid, lifespan, 'expiring secret').first }

  it 'sends the receipt identifier and links to the receipt page, not to a short id' do
    scheduled = []
    allow(Onetime::Jobs::Publisher).to receive(:schedule_email) do |*args|
      scheduled << args
      true
    end
    # The timeline is shared with every other receipt in the datastore; this
    # example is about the payload built for its own receipt.
    allow(Onetime::Receipt).to receive(:expiring_within).and_return([receipt.identifier])

    Onetime::Jobs::Scheduled::ExpirationWarningJob.send(:process_expiring_secrets)

    expect(scheduled.size).to eq(1)
    template, payload, options = scheduled.first
    expect(template).to eq(:expiration_warning)
    expect(options).to have_key(:delay_seconds)
    expect(payload[:recipient]).to eq(owner.email)
    expect(payload[:receipt_identifier]).to eq(receipt.identifier)
    expect(payload).not_to have_key(:secret_key)

    # The identifier in the payload is the one the receipt endpoints resolve.
    expect(Onetime::Receipt.load(payload[:receipt_identifier])&.identifier).to eq(receipt.identifier)

    mail = Onetime::Mail::Templates::ExpirationWarning.new(payload)
    expect(mail.receipt_uri).to end_with("/receipt/#{receipt.identifier}")
    expect(mail.render_text).to include("/receipt/#{receipt.identifier}")
    expect(mail.render_html).to include("/receipt/#{receipt.identifier}")
    expect(mail.render_text).not_to include('/secret/')
    expect(mail.render_html).not_to include('/secret/')
  end
end
