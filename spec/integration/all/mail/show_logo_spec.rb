# spec/integration/all/mail/show_logo_spec.rb
#
# frozen_string_literal: true

# Tests for the emailer.show_logo config toggle.
#
# The show_logo? predicate on TemplateContext controls whether HTML email
# templates render the logo <img> tag. It reads OT.conf.dig('emailer',
# 'show_logo') and returns true only when the value is exactly `true`.
#
# Run with: pnpm run test:rspec spec/integration/all/mail/show_logo_spec.rb

require 'spec_helper'
require 'onetime/mail/views/base'
require 'onetime/mail/views/secret_link'
require 'onetime/mail/views/welcome'
require 'onetime/mail/views/password_request'
require 'onetime/mail/views/incoming_secret'
require 'onetime/mail/views/secret_revealed'
require 'onetime/mail/views/expiration_warning'
require 'onetime/mail/views/feedback_email'

RSpec.describe 'Email show_logo toggle', type: :integration do
  before(:all) do
    I18n::Backend::Simple.include(Onetime::Initializers::SetupI18n::JsonBackend) unless I18n::Backend::Simple.include?(Onetime::Initializers::SetupI18n::JsonBackend)

    I18n.available_locales = [:en]
    I18n.default_locale = :en

    I18n.load_path.clear
    locale_files = Dir[File.join(ENV['ONETIME_HOME'] || Onetime::HOME, 'generated/locales/*.json')]
    locale_files.each { |file| I18n.load_path << file }
    I18n.backend.reload!
  end

  around do |example|
    original_conf = OT.conf
    example.run
    OT.instance_variable_set(:@conf, original_conf)
  end

  # ---------------------------------------------------------------------------
  # show_logo? predicate on TemplateContext
  # ---------------------------------------------------------------------------
  describe 'TemplateContext#show_logo?' do
    subject(:context) { Onetime::Mail::Templates::Base::TemplateContext.new({}, 'en') }

    context 'when emailer.show_logo is absent from config' do
      before do
        conf = OT.conf.dup
        emailer = (conf['emailer'] || {}).dup
        emailer.delete('show_logo')
        conf['emailer'] = emailer
        OT.instance_variable_set(:@conf, conf)
      end

      it 'returns false' do
        expect(context.show_logo?).to be false
      end
    end

    context 'when emailer.show_logo is nil' do
      before do
        conf = OT.conf.dup
        conf['emailer'] = (conf['emailer'] || {}).merge('show_logo' => nil)
        OT.instance_variable_set(:@conf, conf)
      end

      it 'returns false' do
        expect(context.show_logo?).to be false
      end
    end

    context 'when emailer.show_logo is explicitly false' do
      before do
        conf = OT.conf.dup
        conf['emailer'] = (conf['emailer'] || {}).merge('show_logo' => false)
        OT.instance_variable_set(:@conf, conf)
      end

      it 'returns false' do
        expect(context.show_logo?).to be false
      end
    end

    context 'when emailer.show_logo is exactly true' do
      before do
        conf = OT.conf.dup
        conf['emailer'] = (conf['emailer'] || {}).merge('show_logo' => true)
        OT.instance_variable_set(:@conf, conf)
      end

      it 'returns true' do
        expect(context.show_logo?).to be true
      end
    end

    context 'when emailer.show_logo is the string "true"' do
      before do
        conf = OT.conf.dup
        conf['emailer'] = (conf['emailer'] || {}).merge('show_logo' => 'true')
        OT.instance_variable_set(:@conf, conf)
      end

      it 'returns false (strict boolean check)' do
        expect(context.show_logo?).to be false
      end
    end

    context 'when emailer section is missing entirely' do
      before do
        conf = OT.conf.dup
        conf.delete('emailer')
        OT.instance_variable_set(:@conf, conf)
      end

      it 'returns false' do
        expect(context.show_logo?).to be false
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Rendered HTML output with show_logo on/off
  # ---------------------------------------------------------------------------
  describe 'rendered HTML logo visibility' do
    # Use SecretLink as representative template; all 12 share the same
    # conditional <% if show_logo? && logo_url %> wrapper around the single
    # <img> tag. Both gates are required:
    #   - show_logo? is the operator's explicit opt-in. It is a safety gate:
    #     images can be blocked at the network or email-client level, so a
    #     broken <img> is a negative trust signal an operator may not want.
    #   - logo_url must be present (#3049 neutralized the default to nil) to
    #     avoid rendering an <img> with an empty src.
    let(:logo_url) { 'https://cdn.example.test/brand/logo.svg' }
    let(:template) do
      Onetime::Mail::Templates::SecretLink.new({
        secret_key: 'abc123def456',
        recipient: 'recipient@example.com',
        sender_email: 'sender@example.com',
        share_domain: nil
      })
    end

    context 'when show_logo is false (even with a brand logo_url set)' do
      before do
        conf = OT.conf.dup
        conf['emailer'] = (conf['emailer'] || {}).merge('show_logo' => false)
        # logo_url is present, so the safety gate (show_logo?) is what must
        # suppress the <img>, not the absence of a URL.
        conf['brand'] = (conf['brand'] || {}).merge('logo_url' => logo_url)
        OT.instance_variable_set(:@conf, conf)
      end

      it 'does not include an <img tag in HTML output' do
        html = template.render_html
        expect(html).not_to include('<img')
      end
    end

    context 'when show_logo is true but no brand logo_url is set' do
      before do
        conf = OT.conf.dup
        conf['emailer'] = (conf['emailer'] || {}).merge('show_logo' => true)
        conf['brand'] = (conf['brand'] || {}).merge('logo_url' => nil)
        OT.instance_variable_set(:@conf, conf)
      end

      it 'does not include an <img tag (no URL to render)' do
        html = template.render_html
        expect(html).not_to include('<img')
      end
    end

    context 'when show_logo is true and a brand logo_url is set' do
      before do
        conf = OT.conf.dup
        conf['emailer'] = (conf['emailer'] || {}).merge('show_logo' => true)
        conf['brand'] = (conf['brand'] || {}).merge('logo_url' => logo_url)
        OT.instance_variable_set(:@conf, conf)
      end

      it 'includes the logo <img tag in HTML output' do
        html = template.render_html
        expect(html).to include('<img')
        expect(html).to include(logo_url)
      end
    end

    # Verify the toggle across a second template to confirm the conditional
    # is wired consistently (not just in secret_link.html.erb).
    describe 'Welcome template' do
      let(:welcome_template) do
        Onetime::Mail::Templates::Welcome.new({
          email_address: 'test@example.com',
          secret: double('Secret', identifier: 'verify123'),
          product_name: 'Test Product'
        })
      end

      context 'when show_logo is false (even with a brand logo_url set)' do
        before do
          conf = OT.conf.dup
          conf['emailer'] = (conf['emailer'] || {}).merge('show_logo' => false)
          conf['brand'] = (conf['brand'] || {}).merge('logo_url' => logo_url)
          OT.instance_variable_set(:@conf, conf)
        end

        it 'omits <img from rendered HTML' do
          expect(welcome_template.render_html).not_to include('<img')
        end
      end

      context 'when show_logo is true and a brand logo_url is set' do
        before do
          conf = OT.conf.dup
          conf['emailer'] = (conf['emailer'] || {}).merge('show_logo' => true)
          conf['brand'] = (conf['brand'] || {}).merge('logo_url' => logo_url)
          OT.instance_variable_set(:@conf, conf)
        end

        it 'includes the logo <img in rendered HTML' do
          html = welcome_template.render_html
          expect(html).to include('<img')
          expect(html).to include(logo_url)
        end
      end
    end
  end
end
