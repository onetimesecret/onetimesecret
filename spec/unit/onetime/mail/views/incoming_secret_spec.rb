# spec/unit/onetime/mail/views/incoming_secret_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'onetime/mail/views/base'
require 'onetime/mail/views/incoming_secret'
require 'onetime/mail/views/secret_link'

RSpec.describe Onetime::Mail::Templates::IncomingSecret do
  let(:valid_data) do
    {
      secret_key: 'abc123def456',
      recipient: 'recipient@example.com',
      share_domain: nil,
      memo: 'Please review',
      has_passphrase: false,
    }
  end

  subject(:template) { described_class.new(valid_data) }

  # ---------------------------------------------------------------------------
  # Inheritance
  # ---------------------------------------------------------------------------

  describe 'class hierarchy' do
    it 'inherits from Base' do
      expect(described_class.superclass).to eq(Onetime::Mail::Templates::Base)
    end

    it 'is distinct from SecretLink' do
      expect(described_class).not_to eq(Onetime::Mail::Templates::SecretLink)
    end
  end

  # ---------------------------------------------------------------------------
  # validate_data!
  # ---------------------------------------------------------------------------

  describe '#validate_data! (called on initialize)' do
    it 'raises ArgumentError when secret_key is missing' do
      data = valid_data.reject { |k, _| k == :secret_key }
      expect { described_class.new(data) }.to raise_error(ArgumentError, /Secret key required/)
    end

    it 'raises ArgumentError when recipient is missing' do
      data = valid_data.reject { |k, _| k == :recipient }
      expect { described_class.new(data) }.to raise_error(ArgumentError, /Recipient required/)
    end

    it 'does not raise when both required fields are present' do
      expect { described_class.new(valid_data) }.not_to raise_error
    end
  end

  # ---------------------------------------------------------------------------
  # subject
  # ---------------------------------------------------------------------------

  describe '#subject' do
    it 'returns a String' do
      # subject() is translated; stub the translation to avoid I18n dependency
      allow(Onetime::Mail::Templates::EmailTranslations).to receive(:translate)
        .with('email.incoming_secret.subject', locale: 'en')
        .and_return('You received a secret')

      expect(template.subject).to be_a(String)
    end

    it 'does not include the memo value' do
      allow(Onetime::Mail::Templates::EmailTranslations).to receive(:translate)
        .and_return('You received a secret')

      expect(template.subject).not_to include('Please review')
    end

    it 'delegates to EmailTranslations with the correct key' do
      expect(Onetime::Mail::Templates::EmailTranslations).to receive(:translate)
        .with('email.incoming_secret.subject', locale: 'en')
        .and_return('You received a secret')

      template.subject
    end
  end

  # ---------------------------------------------------------------------------
  # display_domain
  # ---------------------------------------------------------------------------

  describe '#display_domain' do
    context 'when share_domain is nil' do
      it 'falls back to the configured site host' do
        result = template.display_domain
        expect(result).to match(%r{\Ahttps?://})
      end
    end

    context 'when share_domain is provided' do
      let(:valid_data) { super().merge(share_domain: 'secrets.example.com') }

      it 'uses the share_domain in the URL' do
        expect(template.display_domain).to include('secrets.example.com')
      end

      it 'starts with a scheme' do
        expect(template.display_domain).to match(%r{\Ahttps?://secrets\.example\.com})
      end
    end

    context 'when share_domain is an empty string' do
      let(:valid_data) { super().merge(share_domain: '') }

      it 'falls back to the site host' do
        result = template.display_domain
        expect(result).to match(%r{\Ahttps?://})
        expect(result).not_to match(%r{://\z})
      end
    end
  end

  # ---------------------------------------------------------------------------
  # uri_path
  # ---------------------------------------------------------------------------

  describe '#uri_path' do
    it 'builds the path from secret_key' do
      expect(template.uri_path).to eq('/secret/abc123def456')
    end

    it 'raises when secret_key is nil after construction' do
      # Force nil after construction to simulate corrupt state
      allow(template).to receive(:data).and_return(
        valid_data.merge(secret_key: nil, recipient: 'recipient@example.com')
      )
      expect(template.uri_path).to eq('/secret/')
    end
  end

  # ---------------------------------------------------------------------------
  # has_passphrase? (private, tested via to_email / template_binding)
  # ---------------------------------------------------------------------------

  describe 'has_passphrase? behavior' do
    context 'when has_passphrase is not set' do
      let(:valid_data) { super().reject { |k, _| k == :has_passphrase } }

      it 'defaults to false' do
        # Access via send since it is private
        expect(template.send(:has_passphrase?)).to be false
      end
    end

    context 'when has_passphrase is explicitly false' do
      let(:valid_data) { super().merge(has_passphrase: false) }

      it 'returns false' do
        expect(template.send(:has_passphrase?)).to be false
      end
    end

    context 'when has_passphrase is true' do
      let(:valid_data) { super().merge(has_passphrase: true) }

      it 'returns true' do
        expect(template.send(:has_passphrase?)).to be true
      end
    end
  end

  # ---------------------------------------------------------------------------
  # to_email
  # ---------------------------------------------------------------------------

  describe '#to_email' do
    let(:from_address) { 'noreply@onetimesecret.com' }

    before do
      allow(Onetime::Mail::Templates::EmailTranslations).to receive(:translate)
        .and_return('You received a secret')
      # Avoid actual ERB template file reads
      allow(template).to receive(:render_text).and_return('text body')
      allow(template).to receive(:render_html).and_return('<html>html body</html>')
    end

    it 'returns a hash with all required keys' do
      result = template.to_email(from: from_address)
      expect(result).to include(:to, :from, :subject, :text_body, :html_body)
    end

    it 'sets :to to the recipient email' do
      expect(template.to_email(from: from_address)[:to]).to eq('recipient@example.com')
    end

    it 'sets :from to the provided from address' do
      expect(template.to_email(from: from_address)[:from]).to eq(from_address)
    end

    it 'sets :text_body from render_text' do
      expect(template.to_email(from: from_address)[:text_body]).to eq('text body')
    end

    it 'sets :html_body from render_html' do
      expect(template.to_email(from: from_address)[:html_body]).to eq('<html>html body</html>')
    end
  end

  # ---------------------------------------------------------------------------
  # memo helpers
  # ---------------------------------------------------------------------------

  describe '#memo and #has_memo?' do
    it 'returns the memo from data' do
      expect(template.memo).to eq('Please review')
    end

    it 'has_memo? is true when memo is present' do
      expect(template.has_memo?).to be true
    end

    context 'when memo is nil' do
      let(:valid_data) { super().merge(memo: nil) }

      it 'has_memo? is false' do
        expect(template.has_memo?).to be false
      end
    end

    context 'when memo is an empty string' do
      let(:valid_data) { super().merge(memo: '') }

      it 'has_memo? is false' do
        expect(template.has_memo?).to be false
      end
    end
  end

  # ---------------------------------------------------------------------------
  # recipient_email
  # ---------------------------------------------------------------------------

  describe '#recipient_email' do
    it 'returns the recipient from data' do
      expect(template.recipient_email).to eq('recipient@example.com')
    end
  end

  # ---------------------------------------------------------------------------
  # ERB template rendering — passphrase conditional block
  #
  # These tests render actual ERB templates from disk and verify that the
  # passphrase notice block appears or is absent based on has_passphrase.
  # I18n.t is stubbed to return the translation key so we can match on it
  # without loading locale files.
  # ---------------------------------------------------------------------------

  describe 'ERB rendering — passphrase notice' do
    before do
      # Stub I18n.t to echo the key so template rendering doesn't require
      # locale files. The returned value is the key itself, which lets us
      # assert on key presence/absence in the rendered output.
      allow(I18n).to receive(:t) { |key, **_opts| key.to_s }
    end

    context 'when has_passphrase is false' do
      let(:valid_data) { super().merge(has_passphrase: false) }

      it 'does not render the passphrase notice block in plain text' do
        text = template.render_text
        expect(text).not_to include('email.incoming_secret.passphrase_label')
        expect(text).not_to include('email.incoming_secret.passphrase_required')
      end

      it 'does not render the passphrase notice block in HTML' do
        html = template.render_html
        expect(html).not_to include('email.incoming_secret.passphrase_label')
        expect(html).not_to include('email.incoming_secret.passphrase_required')
      end
    end

    context 'when has_passphrase is true' do
      let(:valid_data) { super().merge(has_passphrase: true) }

      it 'renders the passphrase notice block in plain text' do
        text = template.render_text
        expect(text).to include('email.incoming_secret.passphrase_label')
        expect(text).to include('email.incoming_secret.passphrase_required')
      end

      it 'renders the passphrase notice block in HTML' do
        html = template.render_html
        expect(html).to include('email.incoming_secret.passphrase_label')
        expect(html).to include('email.incoming_secret.passphrase_required')
      end
    end
  end
end
