# frozen_string_literal: true

require_relative '../../../../../spec/spec_helper'
require_relative '../../../core/controllers/page'
require_relative '../../../core/logic/page/get_favicon'
require_relative '../../../../api/domains/application'

RSpec.describe Core::Controllers::Page do
  let(:request) { double('Request', locale: 'en', params: {}, env: {}) }
  let(:response) { Rack::Response.new }
  let(:controller) { described_class.new(request, response) }

  it 'sends passive-content headers when serving a domain image' do
    logic = double('GetImage', content_type: 'image/png', content_length: '3', image_data: 'png')
    allow(DomainsAPI::Logic::Domains::GetImage).to receive(:new).and_return(logic)
    allow(logic).to receive(:raise_concerns)
    allow(logic).to receive(:process)

    controller.imagine

    expect(response['x-content-type-options']).to eq('nosniff')
    expect(response['content-security-policy']).to eq("default-src 'none'; sandbox")
    expect(response['content-type']).to eq('image/png')
    expect(response.body.join).to eq('png')
  end

  it 'sends passive-content headers when serving a custom favicon' do
    logic = double('GetFavicon', redirect_url: nil, content_type: 'image/x-icon', content_length: '3', icon_data: 'ico')
    allow(Core::Logic::Page::GetFavicon).to receive(:new).and_return(logic)
    allow(logic).to receive(:raise_concerns)
    allow(logic).to receive(:process)

    controller.favicon

    expect(response['x-content-type-options']).to eq('nosniff')
    expect(response['content-security-policy']).to eq("default-src 'none'; sandbox")
    expect(response['content-type']).to eq('image/x-icon')
    expect(response.body.join).to eq('ico')
  end
end

RSpec.describe Core::Logic::Page::GetFavicon do
  let(:logic) { described_class.allocate }
  let(:svg) { '<svg xmlns="http://www.w3.org/2000/svg" width="1" height="1"></svg>' }
  let(:png) do
    Base64.strict_decode64('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jN9kAAAAASUVORK5CYII=')
  end
  let(:image_hash) { {} }
  let(:domain) { double('CustomDomain', icon: image_hash, display_domain: 'example.com') }

  before do
    logic.instance_variable_set(:@use_default, false)
    logic.instance_variable_set(:@custom_domain, domain)
    logic.instance_variable_set(:@image_source, :icon)
    allow(logic).to receive(:serve_default_favicon) do
      logic.instance_variable_set(:@icon_data, 'default-icon')
      logic.instance_variable_set(:@content_type, 'image/x-icon')
      logic.instance_variable_set(:@content_length, '12')
    end
  end

  it 'refuses a legacy SVG in the derived cache' do
    image_hash['content_type']    = 'image/svg+xml'
    image_hash['encoded_favicon'] = Base64.strict_encode64(svg)
    logic.process
    expect(logic.icon_data).to eq('default-icon')
  end

  it 'refuses a legacy SVG mislabeled as an ICO' do
    image_hash['content_type'] = 'image/x-icon'
    image_hash['encoded']      = Base64.strict_encode64(svg)
    logic.process
    expect(logic.icon_data).to eq('default-icon')
  end

  it 'preserves a cached raster favicon and derives its canonical MIME' do
    image_hash['content_type']    = 'image/jpeg'
    image_hash['encoded_favicon'] = Base64.strict_encode64(png)
    logic.process
    expect(logic.icon_data).to eq(png)
    expect(logic.content_type).to eq('image/png')
  end

  it 'preserves the direct ICO serving path' do
    ico                        = "\x00\x00\x01\x00\x01\x00".b + ("\x00" * 16)
    image_hash['content_type'] = 'image/vnd.microsoft.icon'
    image_hash['encoded']      = Base64.strict_encode64(ico)
    logic.process
    expect(logic.icon_data).to eq(ico)
    expect(logic.content_type).to eq('image/x-icon')
  end
end
