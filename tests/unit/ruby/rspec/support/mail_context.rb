# tests/unit/ruby/rspec/support/mail_context.rb

def with_emailer(mail)
  mail.tap { |m| m.instance_variable_set(:@emailer, mail_emailer) }
end


def resolve_template_path(template_name)
  # Start from project root (where the tests directory is)
  project_root = Onetime::HOME
  File.join(project_root, 'templates', 'mail', "#{template_name}.html")
end


RSpec.shared_context "mail_test_context" do
  let(:mail_config) do
    {
      emailer: {
        mode: :smtp,
        from: 'sender@example.com',
        fromname: 'Test Sender',
        host: 'smtp.example.com',
        port: 587,
        user: 'testuser',
        tls: true,
        auth: true
      },
      site: {
        host: 'example.com',
        ssl: true,
        domains_enabled: true
      }
    }
  end

  let(:mail_locales) do
    {
      'en' => {
        email: {
          welcome: {
            subject: 'Welcome to OnetimeSecret',
            body: 'Welcome email body with {{ verify_uri }}',
            footer: 'Email footer text'
          },
          secretlink: {
            subject: '%s sent you a secret',
            body: 'Secret link email body',
            footer: 'Secret link footer'
          }
        },
        web: {
          COMMON: {
            description: 'Test Description',
            keywords: 'test,keywords'
          }
        }
      },
      'fr' => {
        email: {
          welcome: {
            subject: 'Bienvenue à OnetimeSecret',
            body: 'Corps du message avec {{ verify_uri }}',
            footer: 'Pied de page'
          },
          secretlink: {
            subject: '%s vous a envoyé un secret',
            body: 'Corps du message secret',
            footer: 'Pied de page secret'
          }
        },
        web: {
          COMMON: {
            description: 'Description Test',
            keywords: 'test,mots-clés'
          }
        }
      }
    }
  end

  let(:mail_customer) do
    instance_double('Customer',
      identifier: 'test@example.com',
      email: 'test@example.com',
      custid: 'test@example.com',
      anonymous?: false,
      verified?: false
    )
  end

  let(:mail_secret) do
    instance_double('Secret',
      identifier: 'secret123',
      key: 'testkey123',
      share_domain: nil,
      ttl: 7200,
      state: 'pending'
    )
  end

  let(:mail_emailer) do
    instance_double('SMTPMailer').tap do |emailer|
      allow(emailer).to receive(:send_email)
        .and_return({ status: 'sent', message_id: 'test123' })
      # Expect this to be called during initialization
      allow(emailer).to receive(:fromname=).with('Onetime Secret')
    end
  end

  before do
    allow(OT).to receive(:conf).and_return(mail_config)
    allow(OT).to receive(:locales).and_return(mail_locales)
    allow(OT).to receive(:info)
    allow(OT).to receive(:ld)
    allow(OT).to receive(:le)
    allow(Onetime::EmailReceipt).to receive(:create)

    # Mock the emailer creation instead of trying to replace it after
    mailer = mail_emailer
    allow(OT::App::Mail::SMTPMailer).to receive(:new)
      .with(mail_config[:emailer][:from], mail_config[:emailer][:fromname])
      .and_return(mailer)

    allow(OT::App::Mail::SendGridMailer).to receive(:new)
      .with(mail_config[:emailer][:from], mail_config[:emailer][:fromname])
      .and_return(mailer)

    allow_any_instance_of(Onetime::App::Mail::Base).to receive(:emailer).and_return(mailer)
  end
end

RSpec.shared_examples "mail delivery behavior" do
  describe "common mail functionality" do
    it "initializes with correct mode and locale" do
      expect(subject.mode).to eq(:smtp)
      expect(subject.locale).to eq('en')
    end

    it "loads correct locale data" do
      expect(subject.i18n[:locale]).to eq('en')
      expect(subject.i18n[:COMMON]).to include(
        description: 'Test Description',
        keywords: 'test,keywords'
      )
    end

    describe "delivery handling" do
      it "handles socket errors with logging" do
        allow(mail_emailer).to receive(:send_email)
          .and_raise(SocketError.new('Connection failed'))

        expect(OT).to receive(:le).with(/Cannot send mail/)

        expect {
          subject.deliver_email
        }.to raise_error(OT::Problem, /Your message wasn't sent/)
      end

      it "creates receipt after failed delivery" do
        allow(mail_emailer).to receive(:send_email)
          .and_raise(SocketError.new('Connection failed'))

        expect {
          subject.deliver_email
        }.to raise_error(OT::Problem)

        expect(Onetime::EmailReceipt).to have_received(:create)
          .with(mail_customer.identifier, anything, include('Connection failed'))
      end

      it "skips delivery with token present" do
        subject.deliver_email('skip_token')

        expect(mail_emailer).not_to have_received(:send_email)
        expect(Onetime::EmailReceipt).not_to have_received(:create)
      end
    end
  end
end

RSpec.shared_examples "mustache template behavior" do |template_name, options = {}|
  # Requires let(:subject) to be defined in including context
  # Requires let(:expected_content) to be defined as hash of expected key/value pairs

  describe "template rendering" do
    let(:template_path) { resolve_template_path(template_name) }
    let(:rendered_content) { subject.render }

    it "has correct template configuration" do
      expect(described_class.template_path).not_to be_nil
      expect(described_class.view_namespace).to eq(Onetime::App::Mail)
    end

    # Only run filesystem checks if templates exist
    if options[:check_filesystem]
      it "has accessible template file" do
        expect(File).to exist(template_path),
          "Template file not found at: #{template_path}"

        expect(File.readable?(template_path)).to be(true),
          "Template file not readable at: #{template_path}"
      end

      it "uses correct template path" do
        expected_path = File.join(File.dirname(template_path), '')
        actual_path = File.join(described_class.template_path, '')

        expect(actual_path).to eq(expected_path),
          "Template path mismatch:\nExpected: #{expected_path}\nActual: #{actual_path}"
      end

      it "contains valid mustache syntax" do
        template_content = File.read(template_path)
        expect(template_content).to include('{{')
      end
    end

    describe "rendering behavior" do
      it "renders without errors" do
        expect { rendered_content }.not_to raise_error
        expect(rendered_content).to be_a(String)
        expect(rendered_content).not_to be_empty
      end

      it "produces valid HTML email" do
        expect(rendered_content).to include('<!DOCTYPE html')
        expect(rendered_content).to include('</html>')
        expect(rendered_content).to match(/<body[^>]*>.*<\/body>/m)
      end

      it "includes critical business content" do
        if subject.respond_to?(:uri_path)
          expect(rendered_content).to include(subject.uri_path)
        end

        if subject.respond_to?(:display_domain)
          expect(rendered_content).to include(subject.display_domain)
        end
      end
    end
  end
end

RSpec.shared_examples "localized email template" do |template_key|
  describe "localization" do
    # Let's make dependencies explicit
    let(:customer) { mail_customer }
    let(:locale) { 'en' }
    let(:init_args) { [mail_secret, 'recipient@example.com'] }

    subject { described_class.new(customer, locale, *init_args) }

    context "with default locale" do
      it "uses correct subject template and interpolation" do
        subject_template = mail_locales['en'][:email][template_key][:subject]
        expect(subject.subject).to eq(
          subject_template % [customer.custid]
        )
      end
    end

    context "with alternative locale" do
      let(:locale) { 'fr' }

      it "uses localized subject with interpolation" do
        subject_template = mail_locales['fr'][:email][template_key][:subject]
        expect(subject.subject).to eq(
          subject_template % [customer.custid]
        )
      end
    end

    context "with invalid locale" do
      let(:locale) { 'xx' }

      it "falls back to English with interpolation" do
        subject_template = mail_locales['en'][:email][template_key][:subject]
        expect(subject.subject).to eq(
          subject_template % [customer.custid]
        )
      end
    end
  end
end
