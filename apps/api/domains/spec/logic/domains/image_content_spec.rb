# frozen_string_literal: true

require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')
require_relative '../../../../../../apps/api/domains/application'

RSpec.describe 'Domain image content validation' do
  # A complete 1x1 PNG, so these examples exercise the real format detector.
  let(:png) do
    Base64.strict_decode64('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jN9kAAAAASUVORK5CYII=')
  end
  let(:svg) { '<svg xmlns="http://www.w3.org/2000/svg" width="1" height="1"></svg>' }

  it 'derives a canonical raster MIME from the file bytes' do
    expect(Onetime::ImageContent.content_type(png)).to eq('image/png')
  end

  it 'refuses SVG, XML, HTML and empty content' do
    [svg, "<?xml version=\"1.0\"?>#{svg}", '<html>image</html>', ''].each do |bytes|
      expect(Onetime::ImageContent.content_type(bytes)).to be_nil
    end
  end

  describe 'upload validation' do
    let(:logic) { DomainsAPI::Logic::Domains::UpdateDomainLogo.allocate }
    let(:domain) { instance_double(Onetime::CustomDomain, display_domain: 'example.com') }

    before do
      logic.instance_variable_set(:@extid, 'abc123')
      logic.instance_variable_set(:@custom_domain, domain)
      allow(logic).to receive(:authorize_domain_config!)
      # Isolate format validation from error localization and policy setup.
      allow(logic).to receive(:raise_form_error) { |message| raise ArgumentError, message }
    end

    def upload(bytes, declared_type)
      logic.instance_variable_set(:@uploaded_file, StringIO.new(bytes))
      logic.instance_variable_set(:@content_type, declared_type)
      logic.raise_concerns
    end

    it 'rejects an SVG declared as SVG' do
      expect { upload(svg, 'image/svg+xml') }.to raise_error(ArgumentError, 'Invalid file type')
    end

    it 'rejects an SVG disguised as a PNG before processing' do
      expect { upload(svg, 'image/png') }.to raise_error(ArgumentError, 'Invalid file type')
      expect(logic.greenlighted).not_to be(true)
    end

    it 'rejects an empty upload as an invalid file' do
      expect { upload('', 'image/png') }.to raise_error(ArgumentError, 'Invalid file type')
    end

    it 'rejects HTML disguised as a JPEG' do
      expect { upload('<html>image</html>', 'image/jpeg') }.to raise_error(ArgumentError, 'Invalid file type')
    end

    it 'stores a canonical MIME rather than trusting the multipart header' do
      upload(png, 'image/jpeg')
      expect(logic.content_type).to eq('image/png')
      expect(logic.bytes).to eq(png.bytesize)
      expect(logic.greenlighted).to be(true)
    end

    it 'preserves icon-only ICO support and refuses it for logos' do
      ico        = "\x00\x00\x01\x00\x01\x00".b + ("\x00" * 16)
      expect(Onetime::ImageContent.content_type(ico)).to eq('image/x-icon')
      expect { upload(ico, 'image/png') }.to raise_error(ArgumentError, 'Invalid file type')
      icon_logic = DomainsAPI::Logic::Domains::UpdateDomainIcon.allocate
      icon_logic.instance_variable_set(:@extid, 'abc123')
      icon_logic.instance_variable_set(:@custom_domain, domain)
      icon_logic.instance_variable_set(:@uploaded_file, StringIO.new(ico))
      icon_logic.instance_variable_set(:@content_type, 'image/vnd.microsoft.icon')
      allow(icon_logic).to receive(:authorize_domain_config!)
      icon_logic.raise_concerns
      expect(icon_logic.content_type).to eq('image/x-icon')
    end

    it 'gates on the bytes, not a missing or generic multipart type' do
      ['', 'application/octet-stream', nil].each do |declared_type|
        upload(png, declared_type)
        expect(logic.content_type).to eq('image/png')
        expect(logic.greenlighted).to be(true)
      end
    end
  end

  describe 'legacy image serving' do
    let(:logic) { DomainsAPI::Logic::Domains::GetImage.allocate }

    before do
      allow(logic).to receive(:raise_not_found) { |message| raise ArgumentError, message }
    end

    def stored_image(bytes, stored_type)
      logic.instance_variable_set(:@encoded_content, Base64.strict_encode64(bytes))
      logic.instance_variable_set(:@content_type, stored_type)
      logic.process
    end

    it 'refuses an already-stored SVG even with a raster MIME' do
      expect { stored_image(svg, 'image/png') }.to raise_error(ArgumentError, 'Invalid image content')
    end

    it 'refuses corrupt base64 instead of emitting stored content' do
      logic.instance_variable_set(:@encoded_content, 'not base64!')
      expect { logic.process }.to raise_error(ArgumentError, 'Invalid image content')
    end

    it 'serves raster bytes under their detected MIME despite unsafe metadata' do
      expect(stored_image(png, 'text/html')).to eq(png)
      expect(logic.content_type).to eq('image/png')
      expect(logic.content_length).to eq(png.bytesize.to_s)
    end
  end

end
