# spec/unit/onetime/config/normalize_legal_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Onetime::Config do
  describe '.normalize_legal' do
    # site.legal is the single authority for legal/policy URLs (#4278). The
    # YAML/ERB layer resolves TERMS_URL et al. into site.legal; these specs
    # exercise the Ruby normalization that collapses blanks and resolves the
    # footer "legal" group from the block.

    def normalized(conf)
      described_class.normalize_legal(conf)
      conf
    end

    def conf_with_legal(legal)
      { 'site' => { 'legal' => legal } }
    end

    it 'keeps configured URLs and trims surrounding whitespace' do
      conf = normalized(conf_with_legal(
        'terms_url' => '  https://example.com/terms  ',
        'privacy_url' => '/privacy',
      ))
      legal = conf['site']['legal']
      expect(legal['terms_url']).to eq('https://example.com/terms')
      expect(legal['privacy_url']).to eq('/privacy')
    end

    it 'collapses blank and whitespace-only values to nil' do
      conf  = normalized(conf_with_legal('terms_url' => '', 'dpa_url' => '   '))
      legal = conf['site']['legal']
      expect(legal['terms_url']).to be_nil
      expect(legal['dpa_url']).to be_nil
    end

    it 'fills every known key with nil when the block is missing entirely' do
      conf  = normalized({ 'site' => {} })
      legal = conf['site']['legal']
      expect(legal.keys).to match_array(described_class::LEGAL_URL_KEYS)
      expect(legal.values).to all(be_nil)
    end

    it 'nils out non-string values' do
      conf = normalized(conf_with_legal('terms_url' => true, 'privacy_url' => 42))
      expect(conf['site']['legal']['terms_url']).to be_nil
      expect(conf['site']['legal']['privacy_url']).to be_nil
    end

    context 'footer "legal" group resolution' do
      def conf_with_footer(legal:, links:)
        {
          'site' => {
            'legal' => legal,
            'interface' => {
              'ui' => {
                'footer_links' => {
                  'enabled' => true,
                  'groups' => [
                    { 'name' => 'legal', 'i18n_key' => 'web.footer.legals', 'links' => links },
                    {
                      'name' => 'resources',
                      'links' => [{ 'i18n_key' => 'web.footer.docs', 'url' => '' }],
                    },
                  ],
                },
              },
            },
          },
        }
      end

      let(:default_links) do
        [
          { 'text' => 'Terms of Service', 'i18n_key' => 'web.layout.terms_of_service' },
          { 'text' => 'Privacy Policy', 'i18n_key' => 'web.layout.privacy_policy' },
          { 'text' => 'Data Processing Agreement', 'i18n_key' => 'web.footer.dpa' },
          { 'text' => 'Cookie Policy', 'i18n_key' => 'web.footer.cookie_policy' },
          { 'text' => 'Acceptable Use Policy', 'i18n_key' => 'web.footer.acceptable_use' },
          { 'text' => 'Security', 'i18n_key' => 'web.footer.security' },
        ]
      end

      it 'resolves each legal link URL from site.legal by i18n key' do
        conf = normalized(conf_with_footer(
          legal: {
            'terms_url' => 'https://example.com/terms',
            'privacy_url' => 'https://example.com/privacy',
            'dpa_url' => 'https://example.com/dpa',
          },
          links: default_links,
        ))

        links = conf['site']['interface']['ui']['footer_links']['groups'][0]['links']
        expect(links.map { |l| l['url'] }).to eq(
          %w[https://example.com/terms https://example.com/privacy https://example.com/dpa],
        )
      end

      it 'drops legal links whose URL stays unset (absent, not a dead placeholder)' do
        conf  = normalized(conf_with_footer(legal: {}, links: default_links))
        links = conf['site']['interface']['ui']['footer_links']['groups'][0]['links']
        expect(links).to be_empty
      end

      it 'keeps an explicit operator URL over the site.legal value' do
        conf = normalized(conf_with_footer(
          legal: { 'terms_url' => 'https://example.com/terms' },
          links: [{ 'i18n_key' => 'web.layout.terms_of_service', 'url' => 'https://operator.example/tos' }],
        ))

        links = conf['site']['interface']['ui']['footer_links']['groups'][0]['links']
        expect(links.map { |l| l['url'] }).to eq(['https://operator.example/tos'])
      end

      it 'leaves non-legal groups untouched' do
        conf      = normalized(conf_with_footer(legal: {}, links: default_links))
        resources = conf['site']['interface']['ui']['footer_links']['groups'][1]
        expect(resources['links']).to eq([{ 'i18n_key' => 'web.footer.docs', 'url' => '' }])
      end

      it 'tolerates a config without footer link groups' do
        expect { normalized(conf_with_legal({})) }.not_to raise_error
      end
    end
  end
end
