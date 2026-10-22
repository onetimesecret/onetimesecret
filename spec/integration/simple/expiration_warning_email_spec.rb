# spec/integration/simple/expiration_warning_email_spec.rb
#
# frozen_string_literal: true

# The expiration-warning email is an account notification with a working
# link and no bearer capability.
#
# ExpirationWarningJob used to send receipt.secret_shortid under :secret_key,
# and the template built /secret/<short id>: the page shell opened, but an
# 8-character prefix is not a secret identifier, so the lookup behind it
# failed and every warning led to a not-found page. The payload now carries
# the short id under its own name, and the template names the secret by it
# and links to the owner's recent-secrets page on the canonical host, which
# requires a session. Neither the receipt identifier nor the secret
# identifier appears in the mail: /receipt/<identifier> answers without an
# ownership check and returns the share link, so either would turn the
# mailbox into a key to the secret.
#
# The job also used to hand the mail to Publisher.schedule_email with a
# delay, which published to email.message.schedule, a queue nothing
# consumed: with jobs enabled the warning expired into the DLQ and was
# discarded (#4844). It now calls Publisher.enqueue_email with the template
# and payload only, so the mail takes the same path as every other
# notification. This drives the job over a real owned receipt and checks
# the publisher call and the rendered mail.

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

  it 'enqueues the secret short id and links to the sign-in page, never an identifier' do
    enqueued = []
    allow(Onetime::Jobs::Publisher).to receive(:enqueue_email) do |*args|
      enqueued << args
      true
    end
    # The timeline is shared with every other receipt in the datastore; this
    # example is about the payload built for its own receipt.
    allow(Onetime::Receipt).to receive(:expiring_within).and_return([receipt.identifier])

    Onetime::Jobs::Scheduled::ExpirationWarningJob.send(:process_expiring_secrets)

    # Template and payload, nothing else: no delay option and no fallback
    # override, so the mail goes to email.message.send like every other
    # notification.
    expect(enqueued).to eq([
      [
        :expiration_warning,
        {
          recipient: owner.email,
          secret_shortid: secret.shortid,
          expires_at: receipt.secret_expiration,
        },
      ],
    ])
    payload = enqueued.first[1]

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
