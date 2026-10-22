# spec/integration/simple/expiration_warning_email_spec.rb
#
# frozen_string_literal: true

# The expiration-warning email is an account notification with a working
# link and no bearer capability.
#
# ExpirationWarningJob used to send receipt.secret_shortid under :secret_key,
# and the template built /secret/<short id>, which no route resolves: every
# link in every warning was dead. The payload now carries the short id under
# its own name, and the template names the secret by it and links to the
# owner's recent-secrets page on the canonical host, which requires a
# session. Neither the receipt identifier nor the secret identifier appears
# in the mail: /receipt/<identifier> answers without an ownership check and
# returns the share link, so either would turn the mailbox into a key to the
# secret. This drives the job over a real owned receipt and checks the
# payload and the rendered mail.

require_relative '../integration_spec_helper'
require 'onetime/jobs/scheduled/expiration_warning_job'
require 'onetime/jobs/publisher'

RSpec.describe 'Expiration warning email', type: :integration do
  before(:all) do
    Onetime.boot! :test
  end

  let(:owner) do
    Onetime::Customer.new(email: "expiring-owner-#{SecureRandom.hex(8)}@example.com").tap(&:save)
  end

  # Two days: not below the default min_ttl_hours (48), so spawn_pair puts the
  # receipt on the expiration timeline the job scans.
  let(:lifespan) { 2 * 24 * 3600 }
  let(:pair) { Onetime::Receipt.spawn_pair(owner.objid, lifespan, 'expiring secret') }
  let(:receipt) { pair[0] }
  let(:secret) { pair[1] }

  it 'sends the secret short id and links to the sign-in page, never an identifier' do
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
    expect(payload).to eq(
      recipient: owner.email,
      secret_shortid: secret.shortid,
      expires_at: receipt.secret_expiration,
    )

    mail = Onetime::Mail::Templates::ExpirationWarning.new(payload)
    text = mail.render_text
    html = mail.render_html

    expect(mail.recent_uri).to end_with('/recent')
    expect(mail.recent_uri).to start_with(mail.baseuri)
    [text, html].each do |body|
      expect(body).to include('/recent')
      expect(body).to include(secret.shortid)
      expect(body).not_to include(receipt.identifier)
      expect(body).not_to include(secret.identifier)
      expect(body).not_to include('/secret/')
      expect(body).not_to include('/receipt/')
    end
  end
end
