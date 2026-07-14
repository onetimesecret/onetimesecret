# spec/unit/onetime/config/apply_brand_manifest_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'

# Brand-pack manifest layer (#3774): a pack's brand.yaml is absorbed into
# conf['brand'] as a fallback BELOW the operator `brand:` config (and, later,
# below BRAND_* env via normalize_brand). apply_brand_manifest resolves the pack
# via Onetime.resolve_brand_pack_dir; the specs drive it with an explicit
# brand_assets_dir pointing at a temp pack.
RSpec.describe Onetime::Config do
  describe '.apply_brand_manifest' do
    around do |example|
      Dir.mktmpdir('ots-manifest-spec') do |dir|
        @pack_dir = dir
        example.run
      end
    end

    def write_manifest(yaml)
      File.write(File.join(@pack_dir, 'brand.yaml'), yaml)
    end

    def conf_with(brand: {}, assets_dir: @pack_dir)
      { 'site' => { 'brand_assets_dir' => assets_dir }, 'brand' => brand }
    end

    def applied(conf)
      described_class.apply_brand_manifest(conf)
      conf['brand']
    end

    it 'fills a nil brand key from the pack manifest' do
      write_manifest("primary_color: \"#0A0B0C\"\nproduct_name: Acme\n")
      brand = applied(conf_with(brand: {}))
      expect(brand['primary_color']).to eq('#0A0B0C')
      expect(brand['product_name']).to eq('Acme')
    end

    it 'does not overwrite an operator brand: value (manifest is lower precedence)' do
      write_manifest("product_name: FromPack\n")
      brand = applied(conf_with(brand: { 'product_name' => 'FromOperator' }))
      expect(brand['product_name']).to eq('FromOperator')
    end

    it 'fills only the keys the operator left nil' do
      write_manifest("primary_color: \"#111111\"\nproduct_name: FromPack\n")
      brand = applied(conf_with(brand: { 'product_name' => 'FromOperator' }))
      expect(brand['product_name']).to eq('FromOperator')
      expect(brand['primary_color']).to eq('#111111')
    end

    it 'ignores keys outside the whitelist (cannot reach non-brand config)' do
      write_manifest("product_name: Acme\nhost: evil.example.com\nbutton_text_light: false\n")
      conf = conf_with(brand: {})
      described_class.apply_brand_manifest(conf)
      expect(conf['brand']).not_to have_key('host')
      # button_text_light is deliberately not manifest-settable
      expect(conf['brand']['button_text_light']).to be_nil
      expect(conf.dig('site', 'host')).to be_nil
    end

    it 'treats blank/whitespace manifest values as unset (skips them)' do
      write_manifest("product_name: \"   \"\nsupport_email: \"\"\n")
      brand = applied(conf_with(brand: {}))
      expect(brand['product_name']).to be_nil
      expect(brand['support_email']).to be_nil
    end

    it 'is a no-op when the pack has no brand.yaml' do
      brand = applied(conf_with(brand: { 'product_name' => 'Keep' }))
      expect(brand).to eq('product_name' => 'Keep')
    end

    it 'does not abort boot on a malformed manifest' do
      write_manifest('{ this is: not valid: yaml ]')
      conf = conf_with(brand: {})
      expect { described_class.apply_brand_manifest(conf) }.not_to raise_error
    end

    it 'ignores a manifest that parses to a non-mapping' do
      write_manifest("- just\n- a\n- list\n")
      brand = applied(conf_with(brand: {}))
      expect(brand).to eq({})
    end

    it 'creates the brand hash when the config had none' do
      write_manifest("product_name: Acme\n")
      conf = { 'site' => { 'brand_assets_dir' => @pack_dir } }
      described_class.apply_brand_manifest(conf)
      expect(conf['brand']).to eq('product_name' => 'Acme')
    end

    context 'the tracked default pack' do
      it 'adds no brand values (its brand.yaml is value-free)' do
        default_pack = File.join(Onetime::HOME, 'public', 'branding', 'default')
        conf = { 'site' => { 'brand_pack' => 'default' }, 'brand' => {} }
        described_class.apply_brand_manifest(conf)
        expect(conf['brand']).to eq({}), "default pack #{default_pack} leaked brand values"
      end
    end
  end
end
