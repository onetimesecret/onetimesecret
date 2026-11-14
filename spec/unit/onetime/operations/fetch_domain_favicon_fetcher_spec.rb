# spec/unit/onetime/operations/fetch_domain_favicon_fetcher_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'onetime/operations/fetch_domain_favicon'

# The fetch of a tenant host is bounded by jobs.favicon_fetch; each limit is
# read from its own key.
RSpec.describe Onetime::Operations::FetchDomainFavicon, '#fetcher' do
  subject(:operation) { described_class.new(domain_id: 'domain123') }

  before { allow(Onetime::Http::SafeFetch).to receive(:new).and_call_original }

  it 'builds SafeFetch from the jobs.favicon_fetch settings' do
    allow(OT).to receive(:conf).and_return(
      OT::Config.wrap(
        'jobs' => {
          'favicon_fetch' => {
            'timeout' => 7,
            'max_response_bytes' => 2048,
            'max_redirects' => 2,
            'allowed_content_types' => ['image/png'],
          },
        },
      ),
    )

    operation.send(:fetcher)

    expect(Onetime::Http::SafeFetch).to have_received(:new)
      .with(timeout: 7, max_bytes: 2048, max_redirects: 2, allowed_content_types: ['image/png'])
  end

  it 'uses the class defaults when the settings are unset' do
    allow(OT).to receive(:conf).and_return(OT::Config.wrap('jobs' => { 'favicon_fetch' => {} }))

    operation.send(:fetcher)

    expect(Onetime::Http::SafeFetch).to have_received(:new).with(
      timeout: described_class::DEFAULT_TIMEOUT,
      max_bytes: described_class::DEFAULT_MAX_BYTES,
      max_redirects: described_class::DEFAULT_MAX_REDIRECTS,
      allowed_content_types: described_class::DEFAULT_CONTENT_TYPES,
    )
  end
end
