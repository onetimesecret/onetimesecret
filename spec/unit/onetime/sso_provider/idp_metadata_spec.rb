# spec/unit/onetime/sso_provider/idp_metadata_spec.rb
#
# frozen_string_literal: true

# Onetime::SsoProvider::IdpMetadata — SAML IdP metadata read into a form
# preview (docs/specs/sso/saml-idp-metadata-consumption.md, sections 4.3 and
# 4.4). What is pinned here:
#
#   - ruby-saml's parse_to_idp_metadata_array is the one parser entry
#     point, and only the selected descriptor is converted (#to_hash); an
#     aggregate is refused before any is, and only idp_cert_multi[:signing]
#     reaches the result (never idp_cert, never the encryption list, never
#     a fingerprint or trust option);
#   - SingleSignOnService and NameIDFormat are read from the SAME
#     IDPSSODescriptor the parser selected, namespace-aware;
#   - each signing certificate is PEM-wrapped, parsed, given SHA-256 and
#     SHA-1 display hashes from its DER bytes and run through
#     Saml.cert_problem;
#   - one error boundary around the whole parse maps ArgumentError,
#     REXML::ParseException and REXML's own expansion-limit RuntimeError to
#     :invalid_metadata, the upstream fingerprint's
#     OpenSSL::X509::CertificateError to :unreadable_certificate, and lets an
#     unrelated RuntimeError through;
#   - entity references fail on LAZY extraction under the expansion limit
#     ruby-saml's normal load path sets, and nothing reaches the network.
#
# Certificates are minted here with OpenSSL; no key material is checked in.
# Time is frozen wherever a validity window matters, including for the
# recorded Entra document below, so certificates expiring later never
# break the suite.
#
# FIXTURE: fixtures/entra_common_federationmetadata.xml is the public,
# tenant-neutral document at
#   https://login.microsoftonline.com/common/federationmetadata/2007-06/federationmetadata.xml
# recorded 2026-10-23 with `curl -sS`, byte-for-byte (UTF-8 BOM included)
# except for one trailing newline added for the end-of-file hook. It held
# FIVE signing keys in its IDPSSODescriptor that day (the spec's section 2
# recorded four a day earlier: the tenant document's key set moves) plus
# two WS-Federation RoleDescriptors with keys of their own.
#
# RUN (always via the lane runner — see AGENTS.md):
#   tests/lanes/run unit --only spec/unit/onetime/sso_provider/idp_metadata_spec.rb

require 'spec_helper'
require 'base64'
require 'open3'
require 'openssl'
require 'rbconfig'
require 'securerandom'
require 'socket'
require 'timeout'
require 'ruby-saml'
require_relative '../../../../lib/onetime/sso_provider/idp_metadata'

RSpec.describe Onetime::SsoProvider::IdpMetadata do
  BINDING_REDIRECT = 'urn:oasis:names:tc:SAML:2.0:bindings:HTTP-Redirect'
  BINDING_POST     = 'urn:oasis:names:tc:SAML:2.0:bindings:HTTP-POST'
  BINDING_SOAP     = 'urn:oasis:names:tc:SAML:2.0:bindings:SOAP'
  NAMEID_EMAIL    = 'urn:oasis:names:tc:SAML:1.1:nameid-format:emailAddress'
  NAMEID_PERSISTENT  = 'urn:oasis:names:tc:SAML:2.0:nameid-format:persistent'

  IDP_METADATA_NOW = Time.utc(2027, 3, 1, 12, 0, 0)

  ENTRA_FIXTURE = File.join(__dir__, 'fixtures', 'entra_common_federationmetadata.xml')
  ENTRA_COMMON_METADATA_URL  = 'https://login.microsoftonline.com/common/federationmetadata/2007-06/federationmetadata.xml'

  around do |example|
    Timecop.freeze(IDP_METADATA_NOW) { example.run }
  end

  def self.rsa_key
    @rsa_key ||= OpenSSL::PKey::RSA.new(2048)
  end

  def mint_cert(cn: 'idp.example.com', not_before: IDP_METADATA_NOW - 86_400, not_after: IDP_METADATA_NOW + (365 * 86_400),
                key: self.class.rsa_key)
    cert            = OpenSSL::X509::Certificate.new
    cert.version    = 2
    cert.serial     = SecureRandom.random_number(2**64)
    cert.subject    = OpenSSL::X509::Name.parse("/CN=#{cn}")
    cert.issuer     = cert.subject
    cert.public_key = key.is_a?(OpenSSL::PKey::RSA) ? key.public_key : key
    cert.not_before = not_before
    cert.not_after  = not_after
    cert.sign(key, OpenSSL::Digest.new('SHA256'))
    cert
  end

  # The X509Certificate element text as IdPs publish it: bare base64 of the
  # DER, no PEM armour.
  def b64(cert)
    Base64.strict_encode64(cert.to_der)
  end

  def key_descriptor(base64, use: 'signing')
    use_attr = use ? %( use="#{use}") : ''
    "<md:KeyDescriptor#{use_attr}><ds:KeyInfo><ds:X509Data><ds:X509Certificate>#{base64}" \
      '</ds:X509Certificate></ds:X509Data></ds:KeyInfo></md:KeyDescriptor>'
  end

  def sso_service(binding, location = 'https://idp.example.com/saml/sso')
    location_attr = location.nil? ? '' : %( Location="#{location}")
    %(<md:SingleSignOnService Binding="#{binding}"#{location_attr}/>)
  end

  def name_id_format(value)
    "<md:NameIDFormat>#{value}</md:NameIDFormat>"
  end

  def idp_descriptor(keys: [key_descriptor(b64(signing_cert))], services: [sso_service(BINDING_REDIRECT)], formats: [])
    '<md:IDPSSODescriptor protocolSupportEnumeration="urn:oasis:names:tc:SAML:2.0:protocol">' \
      "#{keys.join}#{formats.join}#{services.join}</md:IDPSSODescriptor>"
  end

  def entity(descriptor = idp_descriptor, entity_id: 'https://idp.example.com/saml/metadata', extra: '')
    id_attr = entity_id.nil? ? '' : %( entityID="#{entity_id}")
    %(<md:EntityDescriptor#{id_attr} xmlns:md="urn:oasis:names:tc:SAML:2.0:metadata" ) +
      %(xmlns:ds="http://www.w3.org/2000/09/xmldsig#">#{descriptor}#{extra}</md:EntityDescriptor>)
  end

  # A federation-style EntitiesDescriptor around several EntityDescriptors.
  def entities(*entity_xml)
    '<md:EntitiesDescriptor xmlns:md="urn:oasis:names:tc:SAML:2.0:metadata" ' \
      "xmlns:ds=\"http://www.w3.org/2000/09/xmldsig#\">#{entity_xml.join}</md:EntitiesDescriptor>"
  end

  def document(body = entity, doctype: nil)
    [%(<?xml version="1.0" encoding="UTF-8"?>), doctype, body].compact.join("\n")
  end

  def parse(xml, metadata_url: nil)
    described_class.parse(xml, metadata_url: metadata_url)
  end

  def expect_parse_error(xml, code)
    expect { parse(xml) }.to raise_error(described_class::Error) { |error|
      expect(error.code).to eq(code)
      expect(error.message).to eq(described_class::Error::MESSAGES.fetch(code))
      expect(error.cause).to be_nil
      yield error if block_given?
    }
  end

  def expect_invalid_metadata(xml, &)
    expect_parse_error(xml, :invalid_metadata, &)
  end

  def problem_codes(result)
    result.problems.map(&:code)
  end

  def colon_hex(hex)
    hex.upcase.scan(/../).join(':')
  end

  let(:signing_cert) { mint_cert(cn: 'signing.idp.example.com') }

  describe '.parse' do
    context 'with one signing certificate' do
      let(:result) { parse(document) }
      let(:certificate) { result.signing_certificates.first }

      it 'returns the EntityID, the Redirect SSO URL and the certificate, with no problems' do
        expect(result.idp_entity_id).to eq('https://idp.example.com/saml/metadata')
        expect(result.idp_sso_service_url).to eq('https://idp.example.com/saml/sso')
        expect(result.signing_certificates.size).to eq(1)
        expect(result.problems).to eq([])
        expect(result).not_to be_blocking
      end

      it 'wraps the bare base64 into ONE PEM block that Saml.cert_problem accepts' do
        expect(certificate.pem).to start_with("-----BEGIN CERTIFICATE-----\n")
        expect(certificate.pem).to end_with("\n-----END CERTIFICATE-----")
        expect(OpenSSL::X509::Certificate.new(certificate.pem).to_der).to eq(signing_cert.to_der)
        expect(Onetime::SsoProvider::Saml.cert_problem(certificate.pem)).to be_nil
        expect(certificate.problem).to be_nil
      end

      it 'reports the subject and the validity window' do
        expect(certificate.subject).to eq('CN=signing.idp.example.com')
        expect(certificate.not_before).to eq(signing_cert.not_before)
        expect(certificate.not_after).to eq(signing_cert.not_after)
      end

      it 'computes the SHA-256 fingerprint and the SHA-1 display thumbprint from the DER bytes' do
        der = signing_cert.to_der

        expect(certificate.fingerprint_sha256).to eq(colon_hex(OpenSSL::Digest::SHA256.hexdigest(der)))
        expect(certificate.thumbprint_sha1).to eq(colon_hex(OpenSSL::Digest::SHA1.hexdigest(der)))
        expect(certificate.fingerprint_sha256).to match(/\A(?:[0-9A-F]{2}:){31}[0-9A-F]{2}\z/)
        expect(certificate.thumbprint_sha1).to match(/\A(?:[0-9A-F]{2}:){19}[0-9A-F]{2}\z/)
      end

      it 'serves the API shape with UTC ISO 8601 timestamps' do
        api = result.to_api_h

        expect(api.keys).to eq(%i[idp_entity_id idp_sso_service_url signing_certificates name_id_formats problems])
        expect(api[:signing_certificates].first).to eq(
          pem: certificate.pem,
          subject: 'CN=signing.idp.example.com',
          not_before: signing_cert.not_before.getutc.iso8601,
          not_after: signing_cert.not_after.getutc.iso8601,
          fingerprint_sha256: certificate.fingerprint_sha256,
          thumbprint_sha1: certificate.thumbprint_sha1,
          problem: nil,
        )
        expect(api[:signing_certificates].first[:not_after]).to end_with('Z')
      end

      it 'accepts base64 wrapped across lines, as many IdPs publish it' do
        wrapped = b64(signing_cert).scan(/.{1,76}/).join("\n      ")
        result  = parse(document(entity(idp_descriptor(keys: [key_descriptor(wrapped)]))))

        expect(result.signing_certificates.first.fingerprint_sha256).to eq(certificate.fingerprint_sha256)
      end
    end

    # The parser's hash carries idp_cert, idp_cert_fingerprint and the
    # encryption list. None has a slot in the result.
    describe 'what the result can carry' do
      it 'has no member for an upstream certificate, fingerprint or trust option' do
        forbidden = %i[idp_cert idp_cert_fingerprint idp_cert_fingerprint_algorithm idp_cert_multi
                       name_identifier_format]

        expect(described_class::Result.members & forbidden).to eq([])
        expect(described_class::SigningCertificate.members).to eq(
          %i[pem subject not_before not_after fingerprint_sha256 thumbprint_sha1 problem],
        )
      end

      it 'serves no upstream fingerprint or trust key, only the explicit display hashes' do
        api  = parse(document).to_api_h
        keys = api.keys + api[:signing_certificates].flat_map(&:keys)

        expect(keys.map(&:to_s).grep(/idp_cert|fingerprint_algorithm|multi/)).to eq([])
        expect(api[:signing_certificates].first).to include(:fingerprint_sha256, :thumbprint_sha1)
      end
    end

    # The recorded public tenant-neutral document (see the header).
    context 'with the Entra ID tenant-neutral document' do
      let(:body) { File.binread(ENTRA_FIXTURE).force_encoding(Encoding::UTF_8) }
      let(:result) { parse(body) }

      # Recorded 2026-10-23; computed from the fixture with OpenSSL.
      let(:recorded_thumbprints) do
        %w[
          760BD20EF2BC0392B22B2A69C35740C135C3DC20
          BC481730A462F081CAC006E8048B5288E02982AA
          AF2071FBAE63368C47E05407FFACDAACD8DA35FE
          F1855CFC82F38770B7ABDE87D465579EE28BF104
          EF3B3ACD84E4F60E63FDBEDEEC8B565BE1DA00BE
        ].map { colon_hex(it) }
      end

      it 'parses through the BOM and returns the issuer template and the Redirect URL' do
        expect(result.idp_entity_id).to eq('https://sts.windows.net/{tenantid}/')
        expect(result.idp_sso_service_url).to eq('https://login.microsoftonline.com/common/saml2')
      end

      it "lists every signing key of the IDPSSODescriptor in document order, none of the RoleDescriptors' keys" do
        expect(body.scan('<KeyDescriptor use="signing">').size).to be > recorded_thumbprints.size
        expect(result.signing_certificates.map(&:thumbprint_sha1)).to eq(recorded_thumbprints)
        expect(result.signing_certificates.map(&:problem)).to all(be_nil)
      end

      # Every Issuer Entra sends carries the tenant GUID where the template
      # says {tenantid}, so the template cannot be imported as is.
      it 'blocks the {tenantid} EntityID template and advertises no NameID format' do
        expect(result.problems.map(&:to_api_h)).to eq(
          [{
            code: 'invalid_entity_id',
            severity: 'blocking',
            message: Onetime::SsoProvider::Saml::ENTITY_ID_PLACEHOLDER_PROBLEM,
          }],
        )
        expect(result).to be_blocking
        expect(result.name_id_formats).to eq([])
      end

      it 'adds the tenant-level advisory when fetched from the tenant-level URL' do
        problems = parse(body, metadata_url: ENTRA_COMMON_METADATA_URL).problems
        advisory = problems.find { it.code == 'tenant_level_entra_metadata' }

        expect(problems.map(&:to_api_h)).to contain_exactly(
          hash_including(code: 'invalid_entity_id', severity: 'blocking'),
          hash_including(code: 'tenant_level_entra_metadata', severity: 'advisory'),
        )
        expect(advisory.message).to include('App Federation Metadata Url', '?appid=')
      end
    end

    describe 'signing and encryption keys' do
      let(:encryption_cert) { mint_cert(cn: 'encryption.idp.example.com') }

      it 'drops a distinct encryption certificate from the result' do
        keys   = [key_descriptor(b64(signing_cert)), key_descriptor(b64(encryption_cert), use: 'encryption')]
        result = parse(document(entity(idp_descriptor(keys: keys))))

        expect(result.signing_certificates.map(&:subject)).to eq(['CN=signing.idp.example.com'])
        expect(result.to_api_h.inspect).not_to include(b64(encryption_cert)[0, 64])
      end

      # ruby-saml's merge_certificates_into sets idp_cert to the ENCRYPTION
      # key in this shape; offering it would fail every sign-in.
      it 'reports no_signing_certificates for an encryption-only document, never using the parser idp_cert' do
        xml = document(entity(idp_descriptor(keys: [key_descriptor(b64(encryption_cert), use: 'encryption')])))
        upstream = OneLogin::RubySaml::IdpMetadataParser.new.parse_to_array(xml, sso_binding: [BINDING_REDIRECT]).first
        expect(upstream[:idp_cert]).to eq(b64(encryption_cert))

        result = parse(xml)

        expect(result.signing_certificates).to eq([])
        expect(problem_codes(result)).to eq(['no_signing_certificates'])
        expect(result.problems.first.severity).to eq('blocking')
        expect(result.to_api_h.inspect).not_to include(b64(encryption_cert)[0, 64])
      end

      it 'counts a KeyDescriptor without a use attribute as a signing key (the parser lists it as both)' do
        result = parse(document(entity(idp_descriptor(keys: [key_descriptor(b64(signing_cert), use: nil)]))))

        expect(result.signing_certificates.size).to eq(1)
        expect(result.problems).to eq([])
      end
    end

    describe 'certificate eligibility' do
      it 'keeps an expired, a not-yet-valid and a non-RSA certificate visible with their problems' do
        expired  = mint_cert(cn: 'expired', not_before: IDP_METADATA_NOW - (400 * 86_400), not_after: IDP_METADATA_NOW - 86_400)
        future   = mint_cert(cn: 'future', not_before: IDP_METADATA_NOW + 86_400, not_after: IDP_METADATA_NOW + (400 * 86_400))
        ec       = mint_cert(cn: 'ec', key: OpenSSL::PKey::EC.generate('prime256v1'))
        keys     = [expired, future, ec].map { key_descriptor(b64(it)) }

        result = parse(document(entity(idp_descriptor(keys: keys))))

        problems = result.signing_certificates.to_h { [it.subject, it.problem] }
        expect(problems['CN=expired']).to match(/expired on/)
        expect(problems['CN=future']).to match(/not valid until/)
        expect(problems['CN=ec']).to match(/RSA public key/)
        expect(problem_codes(result)).to eq(['no_usable_signing_certificates'])
        expect(result).to be_blocking
      end

      it 'raises no record-level problem while one certificate is eligible' do
        expired = mint_cert(cn: 'expired', not_before: IDP_METADATA_NOW - (400 * 86_400), not_after: IDP_METADATA_NOW - 86_400)
        keys    = [key_descriptor(b64(expired)), key_descriptor(b64(signing_cert))]

        result = parse(document(entity(idp_descriptor(keys: keys))))

        expect(result.signing_certificates.map(&:problem)).to match([a_string_matching(/expired/), nil])
        expect(result.problems).to eq([])
      end

      it 'distinguishes zero signing entries (no_signing_certificates)' do
        result = parse(document(entity(idp_descriptor(keys: []))))

        expect(result.signing_certificates).to eq([])
        expect(problem_codes(result)).to eq(['no_signing_certificates'])
      end
    end

    # Two or more signing entries: the parser does not fingerprint, so a bad
    # member first meets OpenSSL in the wrapper, which leaves it out.
    describe 'unreadable signing certificates' do
      let(:not_a_certificate) { Base64.strict_encode64('not a certificate') }

      it 'leaves an unreadable member out, keeps its readable siblings and reports an advisory' do
        keys = [key_descriptor(not_a_certificate), key_descriptor(b64(signing_cert))]
        xml  = document(entity(idp_descriptor(keys: keys)))
        expect { OneLogin::RubySaml::IdpMetadataParser.new.parse_to_array(xml, sso_binding: [BINDING_REDIRECT]) }
          .not_to raise_error

        result = parse(xml)

        expect(result.signing_certificates.map(&:subject)).to eq(['CN=signing.idp.example.com'])
        expect(result.problems.map(&:to_api_h)).to eq(
          [{
            code: 'unreadable_signing_certificates',
            severity: 'advisory',
            message: 'Some signing certificates in the metadata could not be read as X.509 certificates and are not listed.',
          }],
        )
        expect(result).not_to be_blocking
      end

      it 'treats an empty X509Certificate element among several the same way' do
        keys   = [key_descriptor(b64(signing_cert)), key_descriptor('')]
        result = parse(document(entity(idp_descriptor(keys: keys))))

        expect(result.signing_certificates.size).to eq(1)
        expect(problem_codes(result)).to eq(['unreadable_signing_certificates'])
      end

      it 'reports one advisory however many members are unreadable' do
        keys   = [key_descriptor(not_a_certificate), key_descriptor(b64(signing_cert)), key_descriptor('')]
        result = parse(document(entity(idp_descriptor(keys: keys))))

        expect(problem_codes(result)).to eq(['unreadable_signing_certificates'])
      end

      it 'blocks when no member is readable, never as no_signing_certificates' do
        keys   = [key_descriptor(not_a_certificate), key_descriptor('')]
        result = parse(document(entity(idp_descriptor(keys: keys))))

        expect(result.signing_certificates).to eq([])
        expect(problem_codes(result)).to eq(%w[no_usable_signing_certificates unreadable_signing_certificates])
        expect(result).to be_blocking
      end

      it 'blocks when the readable members are all ineligible' do
        expired = mint_cert(cn: 'expired', not_before: IDP_METADATA_NOW - (400 * 86_400), not_after: IDP_METADATA_NOW - 86_400)
        keys    = [key_descriptor(not_a_certificate), key_descriptor(b64(expired))]
        result  = parse(document(entity(idp_descriptor(keys: keys))))

        expect(result.signing_certificates.map(&:subject)).to eq(['CN=expired'])
        expect(problem_codes(result)).to eq(%w[no_usable_signing_certificates unreadable_signing_certificates])
      end

      # One signing entry beside a DIFFERENT encryption key: the parser does
      # not fingerprint (the two differ), so the parse completes with nothing
      # to sign with.
      it 'blocks an unreadable lone signing entry beside a distinct encryption key' do
        keys   = [key_descriptor(not_a_certificate), key_descriptor(b64(signing_cert), use: 'encryption')]
        result = parse(document(entity(idp_descriptor(keys: keys))))

        expect(result.signing_certificates).to eq([])
        expect(problem_codes(result)).to eq(%w[no_usable_signing_certificates unreadable_signing_certificates])
      end
    end

    describe 'SSO service selection (HTTP-Redirect only)' do
      def result_for(services)
        parse(document(entity(idp_descriptor(services: services))))
      end

      it 'selects the Redirect Location when both bindings are offered, POST first' do
        result = result_for([sso_service(BINDING_POST, 'https://idp.example.com/post'),
                             sso_service(BINDING_REDIRECT, 'https://idp.example.com/redirect')])

        expect(result.idp_sso_service_url).to eq('https://idp.example.com/redirect')
        expect(result.problems).to eq([])
      end

      it 'refuses a POST-only document as unsupported_sso_binding, never returning the POST URL' do
        result = result_for([sso_service(BINDING_POST, 'https://idp.example.com/post')])

        expect(result.idp_sso_service_url).to be_nil
        expect(problem_codes(result)).to eq(['unsupported_sso_binding'])
        expect(result.problems.first.severity).to eq('blocking')
      end

      it 'refuses a SOAP-only document as unsupported_sso_binding' do
        result = result_for([sso_service(BINDING_SOAP, 'https://idp.example.com/soap')])

        expect(result.idp_sso_service_url).to be_nil
        expect(problem_codes(result)).to eq(['unsupported_sso_binding'])
      end

      it 'reports no_sso_url when the descriptor lists no service' do
        result = result_for([])

        expect(result.idp_sso_service_url).to be_nil
        expect(problem_codes(result)).to eq(['no_sso_url'])
      end

      it 'reports no_sso_url for a Redirect service without a Location' do
        result = result_for([sso_service(BINDING_REDIRECT, nil)])

        expect(result.idp_sso_service_url).to be_nil
        expect(problem_codes(result)).to eq(['no_sso_url'])
      end

      it 'reports no_sso_url for a Redirect service with a blank Location' do
        result = result_for([sso_service(BINDING_REDIRECT, '   ')])

        expect(result.idp_sso_service_url).to be_nil
        expect(problem_codes(result)).to eq(['no_sso_url'])
      end

      # The parser selects the first Redirect service that HAS a Location
      # attribute (XPath on @Location), so one without the attribute is
      # never the selected service. Accepted: the URL returned is a real
      # Redirect endpoint of the same descriptor.
      it 'selects a later Redirect Location when the first Redirect service has none' do
        result = result_for([sso_service(BINDING_REDIRECT, nil),
                             sso_service(BINDING_REDIRECT, 'https://idp.example.com/redirect')])

        expect(result.idp_sso_service_url).to eq('https://idp.example.com/redirect')
        expect(result.problems).to eq([])
      end

      it 'reports a Redirect URL the save would refuse as invalid_sso_url, with the URL' do
        result = result_for([sso_service(BINDING_REDIRECT, 'http://idp.example.com/sso')])

        expect(result.idp_sso_service_url).to eq('http://idp.example.com/sso')
        expect(result.problems.map(&:to_api_h)).to eq(
          [{ code: 'invalid_sso_url', severity: 'blocking', message: 'IdP SSO service URL must be an https:// URL' }],
        )
      end

      it 'keeps a query on the Redirect URL and decodes &amp;' do
        result = result_for([sso_service(BINDING_REDIRECT, 'https://idp.example.com/sso?idpid=a1&amp;tenant=b2')])

        expect(result.idp_sso_service_url).to eq('https://idp.example.com/sso?idpid=a1&tenant=b2')
        expect(result.problems).to eq([])
      end

      # Namespace-aware: a same-named element in another namespace is not a
      # SAML metadata endpoint.
      it 'ignores a SingleSignOnService element outside the metadata namespace' do
        foreign = %(<x:SingleSignOnService xmlns:x="urn:example:other" Binding="#{BINDING_REDIRECT}" ) +
                  'Location="https://idp.example.com/foreign"/>'
        result  = result_for([foreign])

        expect(result.idp_sso_service_url).to be_nil
        expect(problem_codes(result)).to eq(['no_sso_url'])
      end

      it 'reads a document that uses the metadata namespace as its default namespace' do
        xml = <<~XML
          <EntityDescriptor xmlns="urn:oasis:names:tc:SAML:2.0:metadata" entityID="https://idp.example.com/default-ns">
            <IDPSSODescriptor protocolSupportEnumeration="urn:oasis:names:tc:SAML:2.0:protocol">
              <KeyDescriptor use="signing"><KeyInfo xmlns="http://www.w3.org/2000/09/xmldsig#"><X509Data><X509Certificate>#{b64(signing_cert)}</X509Certificate></X509Data></KeyInfo></KeyDescriptor>
              <NameIDFormat>#{NAMEID_EMAIL}</NameIDFormat>
              <SingleSignOnService Binding="#{BINDING_REDIRECT}" Location="https://idp.example.com/default-ns/sso"/>
            </IDPSSODescriptor>
          </EntityDescriptor>
        XML

        result = parse(xml)

        expect(result.idp_sso_service_url).to eq('https://idp.example.com/default-ns/sso')
        expect(result.name_id_formats).to eq([NAMEID_EMAIL])
        expect(result.problems).to eq([])
      end
    end

    describe 'advertised NameID formats' do
      it 'returns every format in document order, trimmed, without blanks or duplicates' do
        formats = [name_id_format("  #{NAMEID_EMAIL}\n"), name_id_format(''), name_id_format(NAMEID_PERSISTENT),
                   name_id_format('   '), name_id_format(NAMEID_EMAIL)]

        result = parse(document(entity(idp_descriptor(formats: formats))))

        expect(result.name_id_formats).to eq([NAMEID_EMAIL, NAMEID_PERSISTENT])
      end

      it 'returns [] when the descriptor advertises none' do
        expect(parse(document).name_id_formats).to eq([])
      end
    end

    # Only the descriptor the parser selected is read: a sibling role
    # descriptor in the same EntityDescriptor, and an SP-only entity in the
    # same EntitiesDescriptor, contribute neither services nor formats.
    describe 'unrelated descriptors' do
      let(:sibling_role) do
        '<md:AttributeAuthorityDescriptor protocolSupportEnumeration="urn:oasis:names:tc:SAML:2.0:protocol">' \
          "#{name_id_format(NAMEID_PERSISTENT)}#{sso_service(BINDING_REDIRECT, 'https://unrelated.example.com/sso')}" \
          '</md:AttributeAuthorityDescriptor>'
      end

      it 'takes no service or format from a sibling descriptor of the same entity' do
        descriptor = idp_descriptor(services: [], formats: [name_id_format(NAMEID_EMAIL)])
        result     = parse(document(entity(descriptor, extra: sibling_role)))

        expect(result.idp_sso_service_url).to be_nil
        expect(problem_codes(result)).to eq(['no_sso_url'])
        expect(result.name_id_formats).to eq([NAMEID_EMAIL])
      end

      it 'takes nothing from an SP-only entity in the same EntitiesDescriptor' do
        sp_entity = '<md:EntityDescriptor entityID="https://sp.example.com/metadata">' \
                    '<md:SPSSODescriptor protocolSupportEnumeration="urn:oasis:names:tc:SAML:2.0:protocol">' \
                    "#{name_id_format(NAMEID_PERSISTENT)}" \
                    '</md:SPSSODescriptor></md:EntityDescriptor>'
        idp       = '<md:EntityDescriptor entityID="https://idp.example.com/saml/metadata">' \
                    "#{idp_descriptor(formats: [name_id_format(NAMEID_EMAIL)])}</md:EntityDescriptor>"
        result = parse(document(entities(sp_entity, idp)))

        expect(result.idp_entity_id).to eq('https://idp.example.com/saml/metadata')
        expect(result.name_id_formats).to eq([NAMEID_EMAIL])
        expect(result.problems).to eq([])
      end
    end

    # The parser yields one object per IDPSSODescriptor, so one entity
    # publishing a descriptor per protocol is not an aggregate.
    describe 'one entity with several IDPSSODescriptors' do
      let(:saml11_cert) { mint_cert(cn: 'saml11.idp.example.com') }

      def descriptor_for(protocols, keys:, services:, formats: [])
        %(<md:IDPSSODescriptor protocolSupportEnumeration="#{protocols}">) +
          "#{keys.join}#{formats.join}#{services.join}</md:IDPSSODescriptor>"
      end

      let(:saml11_descriptor) do
        descriptor_for(
          'urn:oasis:names:tc:SAML:1.1:protocol urn:mace:shibboleth:1.0',
          keys: [key_descriptor(b64(saml11_cert))],
          services: [sso_service('urn:mace:shibboleth:1.0:profiles:AuthnRequest', 'https://idp.example.com/shibboleth/sso')],
          formats: [name_id_format('urn:mace:shibboleth:1.0:nameIdentifier')],
        )
      end

      it 'reads the SAML 2.0 descriptor and nothing from the SAML 1.1 one' do
        saml2  = idp_descriptor(formats: [name_id_format(NAMEID_PERSISTENT)])
        result = parse(document(entity(saml11_descriptor, extra: saml2)))

        expect(result.idp_entity_id).to eq('https://idp.example.com/saml/metadata')
        expect(result.idp_sso_service_url).to eq('https://idp.example.com/saml/sso')
        expect(result.signing_certificates.map(&:subject)).to eq(['CN=signing.idp.example.com'])
        expect(result.name_id_formats).to eq([NAMEID_PERSISTENT])
        expect(result.problems).to eq([])
      end

      # Only the selected descriptor is converted, so ruby-saml's fingerprint
      # of a sibling's lone certificate never runs.
      it 'reads the SAML 2.0 descriptor when the SAML 1.1 one has an unreadable lone certificate' do
        broken = descriptor_for(
          'urn:oasis:names:tc:SAML:1.1:protocol',
          keys: [key_descriptor(Base64.strict_encode64('not a certificate'))],
          services: [sso_service('urn:mace:shibboleth:1.0:profiles:AuthnRequest', 'https://idp.example.com/shibboleth/sso')],
        )
        result = parse(document(entity(broken, extra: idp_descriptor)))

        expect(result.signing_certificates.map(&:subject)).to eq(['CN=signing.idp.example.com'])
        expect(result.problems).to eq([])
      end

      it 'refuses the SAML 2.0 descriptor\'s own unreadable lone certificate as unreadable_certificate' do
        broken = idp_descriptor(keys: [key_descriptor(Base64.strict_encode64('not a certificate'))])

        expect_parse_error(document(entity(saml11_descriptor, extra: broken)), :unreadable_certificate)
      end

      it 'refuses an entity with two SAML 2.0 descriptors as invalid_metadata, not aggregate_metadata' do
        expect_invalid_metadata(document(entity(idp_descriptor, extra: idp_descriptor)))
      end

      it 'refuses an entity whose descriptors include no SAML 2.0 one as invalid_metadata' do
        expect_invalid_metadata(document(entity(saml11_descriptor, extra: saml11_descriptor)))
      end

      it 'still reads a lone descriptor whatever its protocolSupportEnumeration says' do
        lone   = descriptor_for(
          'urn:oasis:names:tc:SAML:1.1:protocol',
          keys: [key_descriptor(b64(signing_cert))],
          services: [sso_service(BINDING_REDIRECT)],
        )
        result = parse(document(entity(lone)))

        expect(result.idp_sso_service_url).to eq('https://idp.example.com/saml/sso')
      end
    end

    describe 'EntityID' do
      it 'reports a missing entityID as invalid_entity_id' do
        result = parse(document(entity(entity_id: nil)))

        expect(result.idp_entity_id).to be_nil
        expect(result.problems.map(&:to_api_h)).to eq(
          [{ code: 'invalid_entity_id', severity: 'blocking', message: 'IdP EntityID is blank' }],
        )
      end

      it 'returns an EntityID with surrounding whitespace unchanged and reports it' do
        result = parse(document(entity(entity_id: ' https://idp.example.com/saml/metadata')))

        expect(result.idp_entity_id).to eq(' https://idp.example.com/saml/metadata')
        expect(problem_codes(result)).to eq(['invalid_entity_id'])
      end

      it 'returns a templated EntityID unchanged and reports it as blocking' do
        result = parse(document(entity(entity_id: 'https://idp.example.com/{tenant}/metadata')))

        expect(result.idp_entity_id).to eq('https://idp.example.com/{tenant}/metadata')
        expect(problem_codes(result)).to eq(['invalid_entity_id'])
        expect(result).to be_blocking
      end
    end

    it 'reports every blocking problem it finds, in a stable order' do
      xml    = document(entity(idp_descriptor(keys: [], services: [sso_service(BINDING_POST)]), entity_id: ''))
      result = parse(xml)

      expect(problem_codes(result)).to eq(%w[invalid_entity_id unsupported_sso_binding no_signing_certificates])
      expect(result.problems.map(&:severity)).to all(eq('blocking'))
    end

    describe 'refused documents' do
      it 'refuses a document with no IDPSSODescriptor (ArgumentError from the parser)' do
        sp_only = '<md:SPSSODescriptor protocolSupportEnumeration="urn:oasis:names:tc:SAML:2.0:protocol"/>'

        expect_invalid_metadata(document(entity(sp_only))) { expect(it.reason).to eq('ArgumentError') }
      end

      it 'refuses an empty body' do
        expect_invalid_metadata('')
      end

      it 'refuses malformed XML (REXML::ParseException)' do
        expect_invalid_metadata('<md:EntityDescriptor xmlns:md="urn:oasis:names:tc:SAML:2.0:metadata">') do
          expect(it.reason).to eq('REXML::ParseException')
        end
      end

      it 'refuses a JSON or HTML body without echoing it' do
        expect_invalid_metadata('{"issuer":"https://secret-detail.example.com"}') do
          expect(it.message).not_to include('secret-detail')
        end
        expect_invalid_metadata('<html><body>Sign in</body></html>')
      end

      it 'refuses a body that is not valid UTF-8' do
        expect_invalid_metadata("<?xml version=\"1.0\"?>\n<a>\xFF\xFE</a>".b.force_encoding(Encoding::UTF_8))
      end

      it 'refuses a federation aggregate as aggregate_metadata' do
        second = '<md:EntityDescriptor entityID="https://other-idp.example.com/metadata">' \
                 "#{idp_descriptor}</md:EntityDescriptor>"
        first  = '<md:EntityDescriptor entityID="https://idp.example.com/saml/metadata">' \
                 "#{idp_descriptor}</md:EntityDescriptor>"

        expect { parse(document(entities(first, second))) }.to raise_error(described_class::Error) { |error|
          expect(error.code).to eq(:aggregate_metadata)
          expect(error.message).to eq('The document describes more than one identity provider')
        }
      end

      it 'refuses an aggregate as aggregate_metadata even when a member has an unreadable lone certificate' do
        broken = idp_descriptor(keys: [key_descriptor(Base64.strict_encode64('not a certificate'))])
        first  = %(<md:EntityDescriptor entityID="https://idp.example.com/saml/metadata">#{broken}</md:EntityDescriptor>)
        second = '<md:EntityDescriptor entityID="https://other-idp.example.com/metadata">' \
                 "#{idp_descriptor}</md:EntityDescriptor>"

        expect_parse_error(document(entities(first, second)), :aggregate_metadata)
      end

      # The upstream parser fingerprints the certificate itself when there
      # is exactly one, so the failure comes from inside parse_to_array and
      # names the certificate, not the document.
      it 'refuses a malformed single signing certificate as unreadable_certificate' do
        xml = document(entity(idp_descriptor(keys: [key_descriptor(Base64.strict_encode64('not a certificate'))])))
        expect { OneLogin::RubySaml::IdpMetadataParser.new.parse_to_array(xml, sso_binding: [BINDING_REDIRECT]) }
          .to raise_error(OpenSSL::X509::CertificateError)

        expect_parse_error(xml, :unreadable_certificate) { expect(it.reason).to eq('OpenSSL::X509::CertificateError') }
      end

      it 'refuses a malformed encryption-only certificate as unreadable_certificate' do
        bad = key_descriptor(Base64.strict_encode64('not a certificate'), use: 'encryption')

        expect_parse_error(document(entity(idp_descriptor(keys: [bad]))), :unreadable_certificate)
      end

      # merge_certificates_into's second shape: one signing and one
      # encryption certificate that are the same. A KeyDescriptor without a
      # use attribute is listed as both, so it takes this path too, not the
      # lone-certificate one.
      it 'refuses a malformed certificate in a KeyDescriptor without a use attribute as unreadable_certificate' do
        bad = key_descriptor(Base64.strict_encode64('not a certificate'), use: nil)

        expect_parse_error(document(entity(idp_descriptor(keys: [bad]))), :unreadable_certificate)
      end

      it 'refuses an identical malformed signing and encryption pair as unreadable_certificate' do
        bad  = Base64.strict_encode64('not a certificate')
        keys = [key_descriptor(bad), key_descriptor(bad, use: 'encryption')]

        expect_parse_error(document(entity(idp_descriptor(keys: keys))), :unreadable_certificate)
      end
    end

    # ruby-saml's normal load path sets REXML::Security.entity_expansion_limit
    # to 0, and REXML expands lazily: Document.new succeeds, the first READ
    # of a value raises. Each fixture below parses as a document; the
    # failure must come from extraction and still map to invalid_metadata.
    describe 'entity handling' do
      def doctype(entities)
        "<!DOCTYPE md:EntityDescriptor [#{entities}]>"
      end

      def with_formats(*values, doctype_decl:)
        document(entity(idp_descriptor(formats: values.map { name_id_format(it) })), doctype: doctype_decl)
      end

      it 'runs under the limits the normal ruby-saml load path sets' do
        parse(document)

        expect(REXML::Security.entity_expansion_limit).to eq(0)
        expect(REXML::Security.entity_expansion_text_limit).to eq(10_240)
      end

      # #rexml_expansion_error? depends on two REXML internals: the method it
      # locates the library by, and REXML's fixed limit messages. A REXML
      # bump that moves either fails here, by name, instead of turning
      # expansion failures into unexpected_error at the endpoint.
      it 'pins the REXML internals the expansion mapping relies on' do
        parse(document)

        expect { REXML::Document.instance_method(:record_entity_expansion) }.not_to raise_error
        library_dir = described_class.send(:rexml_library_dir)
        source      = Dir.glob(File.join(library_dir, '**', '*.rb')).map { File.read(it) }.join
        described_class::REXML_EXPANSION_MESSAGES.each do |message|
          expect(source).to include(%(raise "#{message}")), message
        end
      end

      it 'refuses an internal entity reference, raised on lazy text extraction' do
        xml = with_formats('&fmt;', doctype_decl: doctype(%(<!ENTITY fmt "#{NAMEID_EMAIL}">)))
        expect { REXML::Document.new(xml) }.not_to raise_error

        expect_invalid_metadata(xml) { expect(it.reason).to eq('REXML entity expansion limit') }
      end

      # The parser reads only the FIRST NameIDFormat; the second is read by
      # the wrapper's descriptor inspection, so this one proves the boundary
      # covers extraction outside the parser.
      it 'refuses an entity reference that only the wrapper extraction reads' do
        xml = with_formats(NAMEID_EMAIL, '&fmt;', doctype_decl: doctype(%(<!ENTITY fmt "#{NAMEID_PERSISTENT}">)))
        expect { OneLogin::RubySaml::IdpMetadataParser.new.parse_to_array(xml, sso_binding: [BINDING_REDIRECT]) }
          .not_to raise_error

        expect_invalid_metadata(xml)
      end

      it 'refuses an internal entity in an attribute value' do
        descriptor = idp_descriptor(services: [sso_service(BINDING_REDIRECT, '&loc;')])
        xml        = document(entity(descriptor), doctype: doctype('<!ENTITY loc "https://idp.example.com/sso">'))

        expect_invalid_metadata(xml)
      end

      it 'refuses an entity bomb promptly, with no partial result' do
        bomb = %w[a b c d e f g h].each_cons(2).map { |name, inner| %(<!ENTITY #{inner} "#{"&#{name};" * 10}">) }
        xml  = with_formats('&h;', doctype_decl: doctype(%(<!ENTITY a "aaaaaaaaaa">#{bomb.join})))

        Timeout.timeout(5) { expect_invalid_metadata(xml) }
      end

      # Character references are not entity expansions, so the count limit
      # never fires; REXML's text-size limit (its other fixed message) does.
      it 'refuses text that grows past the expansion text limit' do
        xml = with_formats('&#65;' * 10_241, doctype_decl: nil)

        expect_invalid_metadata(xml) { expect(it.reason).to eq('REXML entity expansion limit') }
      end

      describe 'external entities and DTDs' do
        let(:attacker) { 'https://attacker.example.net/evil' }

        # Loud at both boundaries: a socket or Net::HTTP call raises (and
        # the error would surface as a RuntimeError, not an Error), and the
        # spies prove none was attempted.
        before do
          [[TCPSocket, :new], [TCPSocket, :open], [Socket, :tcp], [Net::HTTP, :new], [Net::HTTP, :start]].each do |klass, meth|
            allow(klass).to receive(meth).and_raise(RuntimeError, "network access attempted: #{klass}.#{meth}")
          end
        end

        after do
          expect(TCPSocket).not_to have_received(:new)
          expect(TCPSocket).not_to have_received(:open)
          expect(Socket).not_to have_received(:tcp)
          expect(Net::HTTP).not_to have_received(:new)
          expect(Net::HTTP).not_to have_received(:start)
          expect(a_request(:any, %r{\Ahttps?://attacker\.example\.net(?::\d+)?/})).not_to have_been_made
        end

        it 'refuses an external entity reference without fetching it' do
          xml = with_formats('&ext;', doctype_decl: doctype(%(<!ENTITY ext SYSTEM "#{attacker}">)))

          expect_invalid_metadata(xml)
        end

        # REXML 3.4.4 neither fetches nor expands an external parameter
        # entity in the internal subset; the document reads as if it were
        # absent.
        it 'never fetches an external parameter entity' do
          xml = with_formats(NAMEID_EMAIL, doctype_decl: doctype(%(<!ENTITY % ext SYSTEM "#{attacker}"> %ext;)))

          expect(parse(xml).name_id_formats).to eq([NAMEID_EMAIL])
        end

        it 'never fetches an external DTD subset (and the document still parses)' do
          xml = with_formats(NAMEID_EMAIL, doctype_decl: %(<!DOCTYPE md:EntityDescriptor SYSTEM "#{attacker}.dtd">))

          expect(parse(xml).name_id_formats).to eq([NAMEID_EMAIL])
        end
      end
    end

    # Only REXML's own expansion RuntimeError is a parse failure; anything
    # else is a defect the endpoint reports as unexpected_error.
    describe 'an unrelated RuntimeError' do
      let(:parser) { OneLogin::RubySaml::IdpMetadataParser.new }

      before { allow(OneLogin::RubySaml::IdpMetadataParser).to receive(:new).and_return(parser) }

      it 'propagates' do
        allow(parser).to receive(:parse_to_idp_metadata_array).and_raise(RuntimeError, 'boom')

        expect { parse(document) }.to raise_error(RuntimeError, 'boom')
      end

      it "propagates even with REXML's message when it was not raised inside REXML" do
        message = 'number of entity expansions exceeded, processing aborted.'
        allow(parser).to receive(:parse_to_idp_metadata_array).and_raise(RuntimeError, message)

        expect { parse(document) }.to raise_error(RuntimeError, message) { |error|
          expect(error).not_to be_a(described_class::Error)
        }
      end

      it 'propagates a RuntimeError subclass carrying the REXML message' do
        allow(parser).to receive(:parse_to_idp_metadata_array)
          .and_raise(Class.new(RuntimeError), 'entity expansion has grown too large')

        expect { parse(document) }.to raise_error(RuntimeError)
      end
    end

    # ruby-saml is loaded only on the first parse (this file is required
    # wherever the domains API is), and that load is the one that sets the
    # REXML limits. A fresh process, so nothing else has loaded the gem.
    it 'loads ruby-saml on the first parse, and that normal load path sets the expansion limits' do
      script = <<~RUBY
        require 'onetime/sso_provider/idp_metadata'
        loaded_before = !defined?(OneLogin::RubySaml).nil?
        begin
          Onetime::SsoProvider::IdpMetadata.parse('<x/>')
        rescue Onetime::SsoProvider::IdpMetadata::Error
          nil
        end
        puts [loaded_before, REXML::Security.entity_expansion_limit, REXML::Security.entity_expansion_text_limit].join(',')
      RUBY

      output, status = Open3.capture2e(RbConfig.ruby, '-rbundler/setup', '-Ilib', '-e', script, chdir: Onetime::HOME)

      expect(status).to be_success, output
      expect(output.lines.last.to_s.strip).to eq('false,0,10240')
    end
  end

  describe '.tenant_level_entra_metadata?' do
    it 'is true for the tenant metadata path on each Entra host with no usable appid' do
      described_class::ENTRA_METADATA_HOSTS.each do |host|
        ['', '?appid', '?appid=', '?appid=%20', '?other=1'].each do |query|
          url = "https://#{host}/contoso.onmicrosoft.com/federationmetadata/2007-06/federationmetadata.xml#{query}"
          expect(described_class.tenant_level_entra_metadata?(url)).to be(true), url
        end
      end
    end

    it 'matches the documented FederationMetadata casing and an upper-case host' do
      url = 'https://LOGIN.microsoftonline.com/common/FederationMetadata/2007-06/FederationMetadata.xml'

      expect(described_class.tenant_level_entra_metadata?(url)).to be(true)
    end

    it 'is false once a nonempty appid is present, wherever it sits in the query' do
      base = 'https://login.microsoftonline.com/common/federationmetadata/2007-06/federationmetadata.xml'

      expect(described_class.tenant_level_entra_metadata?("#{base}?appid=00000000-1111-2222-3333-444444444444"))
        .to be(false)
      expect(described_class.tenant_level_entra_metadata?("#{base}?x=1&appid=abc&y=2")).to be(false)
      expect(described_class.tenant_level_entra_metadata?("#{base}?appid=&appid=abc")).to be(false)
    end

    it 'does not search the query as a string' do
      base = 'https://login.microsoftonline.com/common/federationmetadata/2007-06/federationmetadata.xml'

      expect(described_class.tenant_level_entra_metadata?("#{base}?notappid=abc")).to be(true)
      expect(described_class.tenant_level_entra_metadata?("#{base}?x=appid%3Dabc")).to be(true)
    end

    it 'is false for another host, a look-alike host, another path or an empty tenant segment' do
      [
        'https://idp.example.com/common/federationmetadata/2007-06/federationmetadata.xml',
        'https://login.microsoftonline.com.evil.example/common/federationmetadata/2007-06/federationmetadata.xml',
        'https://evil.login.microsoftonline.com/common/federationmetadata/2007-06/federationmetadata.xml',
        'https://login.microsoftonline.com/common/saml2',
        'https://login.microsoftonline.com/federationmetadata/2007-06/federationmetadata.xml',
        'https://login.microsoftonline.com//federationmetadata/2007-06/federationmetadata.xml',
        'https://login.microsoftonline.com/a/b/federationmetadata/2007-06/federationmetadata.xml',
        'http://login.microsoftonline.com/common/federationmetadata/2007-06/federationmetadata.xml',
        'not a url',
        nil,
      ].each do |url|
        expect(described_class.tenant_level_entra_metadata?(url)).to be(false), url.inspect
      end
    end
  end

  describe '.metadata_url_problem' do
    it 'accepts a public-shaped https URL with a query' do
      expect(described_class.metadata_url_problem("#{ENTRA_COMMON_METADATA_URL}?appid=abc")).to be_nil
    end

    it 'names the metadata URL, never the SSO URL, for each structural refusal' do
      ['http://idp.example.com/m', 'https://user:pw@idp.example.com/m', 'https://idp.example.com/m#frag',
       'https://idp.example.com./m', '', 'not a url'].each do |url|
        expect(described_class.metadata_url_problem(url)).to eq(described_class::METADATA_URL_SHAPE_PROBLEM), url
      end
      expect(described_class::METADATA_URL_SHAPE_PROBLEM).to start_with('IdP metadata URL')
    end
  end
end
