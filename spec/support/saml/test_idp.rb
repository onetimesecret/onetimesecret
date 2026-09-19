# spec/support/saml/test_idp.rb
#
# frozen_string_literal: true

# A throwaway SAML IdP for specs (#4450): generates its own RSA keypair and
# self-signed certificate at runtime and mints REAL signed SAML Responses, so
# specs exercise ruby-saml's full validate path (XSD structure, signature,
# audience, destination, conditions, InResponseTo) instead of stubbing it.
#
# NOT auto-loaded (spec_helper globs spec/support/*.rb and a few named
# subdirectories; this directory is deliberately not one of them) because it
# requires ruby-saml, which the application itself only loads lazily when a
# SAML provider is configured. Require it explicitly:
#
#   require_relative '<...>/spec/support/saml/test_idp'
#
# No key material is checked in — the keypair is generated once per process.
#
# Signing uses ruby-saml's own XMLSecurity::Document#sign_document (the same
# code path its SP-side request signing uses): the Assertion is built and
# signed as a standalone document, then embedded verbatim in the Response.
# The enveloped signature survives the embedding because the Assertion
# declares, on its own root, every namespace the canonical form will contain
# (see the xmlns:samlp note in #assertion_xml).

require 'base64'
require 'openssl'
require 'securerandom'
require 'time'
require 'ruby-saml'

module SamlSpec
  class TestIdp
    PERSISTENT = 'urn:oasis:names:tc:SAML:2.0:nameid-format:persistent'
    TRANSIENT  = 'urn:oasis:names:tc:SAML:2.0:nameid-format:transient'
    EMAIL      = 'urn:oasis:names:tc:SAML:1.1:nameid-format:emailAddress'

    ASSERTION_NS = 'urn:oasis:names:tc:SAML:2.0:assertion'
    PROTOCOL_NS  = 'urn:oasis:names:tc:SAML:2.0:protocol'

    # 2048-bit keygen costs ~100ms; share one default keypair per process.
    def self.shared_key
      @shared_key ||= OpenSSL::PKey::RSA.new(2048)
    end

    attr_reader :entity_id, :key, :cert

    # @param entity_id [String] the IdP EntityID written into Issuer elements
    # @param key [OpenSSL::PKey::RSA] pass a fresh key to model a DIFFERENT IdP
    # @param cert [OpenSSL::X509::Certificate, nil] an EXISTING certificate for
    #   `key` — models an IdP operator who keeps their pinned certificate and
    #   changes only what they assert (e.g. claims another IdP's EntityID)
    # @param cert_not_after [Time] certificate expiry (ignored when cert given)
    def initialize(entity_id: 'https://idp.example.com/saml/metadata', key: self.class.shared_key,
                   cert: nil, cert_not_after: Time.now + 86_400)
      @entity_id = entity_id
      @key       = key
      @cert      = cert || self_signed_cert(key, cert_not_after)
    end

    def cert_pem
      cert.to_pem
    end

    # Build a base64 SAMLResponse form value.
    #
    # Every structural knob a gate cares about is a keyword so a spec states
    # exactly the one thing that is wrong with its response.
    #
    # @param in_response_to [String, nil] AuthnRequest id; nil omits the
    #   attribute everywhere (an unsolicited / IdP-initiated response)
    # @param acs_url [String] Destination + SubjectConfirmationData Recipient
    # @param audience [String] the SP EntityID
    # @param response_issuer [String, nil] nil omits the Response Issuer
    # @param assertion_issuer [String]
    # @param sign [Boolean] false leaves the Assertion unsigned
    # @param signature_method [String] XML-DSig SignatureMethod URI; SHA-1
    #   (XMLSecurity::Document::RSA_SHA1) models a legacy IdP
    # @param digest_method [String] XML-DSig DigestMethod URI
    # @return [String] base64-encoded Response XML
    def response(in_response_to:, acs_url:, audience:,
                 name_id: 'user-1234', name_id_format: PERSISTENT,
                 attributes: { 'email' => ['user@example.com'] },
                 assertion_id: "_#{SecureRandom.uuid}",
                 response_issuer: entity_id, assertion_issuer: entity_id,
                 now: Time.now.utc, not_on_or_after: nil,
                 session_index: "_#{SecureRandom.hex(8)}", sign: true,
                 signature_method: XMLSecurity::Document::RSA_SHA256,
                 digest_method: XMLSecurity::Document::SHA256)
      not_on_or_after ||= now + 300

      assertion = assertion_xml(
        id: assertion_id, issuer: assertion_issuer, name_id: name_id, name_id_format: name_id_format,
        in_response_to: in_response_to, acs_url: acs_url, audience: audience, attributes: attributes,
        now: now, not_on_or_after: not_on_or_after, session_index: session_index
      )
      assertion = sign_xml(assertion, signature_method, digest_method) if sign

      Base64.strict_encode64(response_xml(
        assertion: assertion, issuer: response_issuer, in_response_to: in_response_to,
        acs_url: acs_url, now: now
      ))
    end

    # A non-Success Response with no Assertion and an IdP-chosen
    # StatusMessage — what a login failure at the IdP looks like, and what
    # an attacker who can start a login can post unsigned: ruby-saml appends
    # the StatusMessage verbatim to its ValidationError BEFORE any signature
    # check (validate_success_status precedes validate_signature).
    #
    # @return [String] base64-encoded Response XML
    def failure_response(in_response_to:, acs_url:, status_message:, now: Time.now.utc)
      irt = in_response_to ? %( InResponseTo="#{esc(in_response_to)}") : ''

      Base64.strict_encode64(
        %(<samlp:Response xmlns:samlp="#{PROTOCOL_NS}" ID="_#{SecureRandom.uuid}" Version="2.0" ) +
        %(IssueInstant="#{ts(now)}" Destination="#{esc(acs_url)}"#{irt}>) +
        %(<saml:Issuer xmlns:saml="#{ASSERTION_NS}">#{esc(entity_id)}</saml:Issuer>) +
        '<samlp:Status><samlp:StatusCode Value="urn:oasis:names:tc:SAML:2.0:status:Requester"/>' \
        "<samlp:StatusMessage>#{esc(status_message)}</samlp:StatusMessage></samlp:Status>" \
        '</samlp:Response>',
      )
    end

    private

    def response_xml(assertion:, issuer:, in_response_to:, acs_url:, now:)
      irt        = in_response_to ? %( InResponseTo="#{esc(in_response_to)}") : ''
      issuer_xml = issuer ? %(<saml:Issuer xmlns:saml="#{ASSERTION_NS}">#{esc(issuer)}</saml:Issuer>) : ''

      %(<samlp:Response xmlns:samlp="#{PROTOCOL_NS}" ID="_#{SecureRandom.uuid}" Version="2.0" ) +
        %(IssueInstant="#{ts(now)}" Destination="#{esc(acs_url)}"#{irt}>) +
        issuer_xml +
        %(<samlp:Status><samlp:StatusCode Value="urn:oasis:names:tc:SAML:2.0:status:Success"/></samlp:Status>) +
        assertion +
        '</samlp:Response>'
    end

    # rubocop:disable Metrics/ParameterLists -- mirrors the SAML assertion's own shape
    def assertion_xml(id:, issuer:, name_id:, name_id_format:, in_response_to:, acs_url:, audience:,
                      attributes:, now:, not_on_or_after:, session_index:)
      irt = in_response_to ? %( InResponseTo="#{esc(in_response_to)}") : ''

      # xmlns:samlp is declared although the Assertion never uses it: ruby-saml
      # signs with an InclusiveNamespaces PrefixList that names `samlp`
      # (XMLSecurity::Document::INC_PREFIX_LIST), so once embedded the
      # canonical form inherits the Response's samlp declaration. Declaring
      # it here makes the standalone digest equal the embedded one.
      %(<saml:Assertion xmlns:saml="#{ASSERTION_NS}" xmlns:samlp="#{PROTOCOL_NS}" ID="#{esc(id)}" ) +
        %(Version="2.0" IssueInstant="#{ts(now)}">) +
        %(<saml:Issuer>#{esc(issuer)}</saml:Issuer>) +
        '<saml:Subject>' +
        %(<saml:NameID Format="#{esc(name_id_format)}">#{esc(name_id)}</saml:NameID>) +
        '<saml:SubjectConfirmation Method="urn:oasis:names:tc:SAML:2.0:cm:bearer">' +
        %(<saml:SubjectConfirmationData NotOnOrAfter="#{ts(not_on_or_after)}" Recipient="#{esc(acs_url)}"#{irt}/>) +
        '</saml:SubjectConfirmation>' +
        '</saml:Subject>' +
        %(<saml:Conditions NotBefore="#{ts(now - 5)}" NotOnOrAfter="#{ts(not_on_or_after)}">) +
        %(<saml:AudienceRestriction><saml:Audience>#{esc(audience)}</saml:Audience></saml:AudienceRestriction>) +
        '</saml:Conditions>' +
        %(<saml:AuthnStatement AuthnInstant="#{ts(now)}" SessionIndex="#{esc(session_index)}">) +
        '<saml:AuthnContext><saml:AuthnContextClassRef>' \
        'urn:oasis:names:tc:SAML:2.0:ac:classes:PasswordProtectedTransport' \
        '</saml:AuthnContextClassRef></saml:AuthnContext>' \
        '</saml:AuthnStatement>' +
        attribute_statement_xml(attributes) +
        '</saml:Assertion>'
    end
    # rubocop:enable Metrics/ParameterLists

    def attribute_statement_xml(attributes)
      return '' if attributes.nil? || attributes.empty?

      body = attributes.map do |name, values|
        vals = Array(values).map { |value| %(<saml:AttributeValue>#{esc(value)}</saml:AttributeValue>) }.join
        %(<saml:Attribute Name="#{esc(name)}" ) +
          %(NameFormat="urn:oasis:names:tc:SAML:2.0:attrname-format:basic">#{vals}</saml:Attribute>)
      end.join

      "<saml:AttributeStatement>#{body}</saml:AttributeStatement>"
    end

    def sign_xml(xml, signature_method, digest_method)
      doc = XMLSecurity::Document.new(xml)
      doc.sign_document(key, cert, signature_method, digest_method)
      doc.to_s
    end

    def self_signed_cert(key, not_after)
      cert            = OpenSSL::X509::Certificate.new
      cert.version    = 2
      cert.serial     = SecureRandom.random_number(2**64)
      cert.subject    = OpenSSL::X509::Name.parse('/CN=spec-idp.example.com')
      cert.issuer     = cert.subject
      cert.public_key = key.public_key
      cert.not_before = [Time.now, not_after].min - 3600
      cert.not_after  = not_after
      cert.sign(key, OpenSSL::Digest.new('SHA256'))
      cert
    end

    def ts(time)
      time.utc.strftime('%Y-%m-%dT%H:%M:%SZ')
    end

    def esc(value)
      value.to_s.encode(xml: :text).gsub('"', '&quot;')
    end
  end
end
