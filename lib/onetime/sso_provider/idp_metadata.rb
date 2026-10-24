# lib/onetime/sso_provider/idp_metadata.rb
#
# frozen_string_literal: true

require 'openssl'
require 'time'
require 'uri'
# Gem-free (it never loads omniauth-saml/ruby-saml): the shared SAML
# validators every value read here is checked with.
require_relative 'saml'

module Onetime
  module SsoProvider
    # Reads a SAML 2.0 IdP metadata document into the values the tenant SAML
    # form can prefill (docs/specs/sso/saml-idp-metadata-consumption.md,
    # Phase 1). Nothing here stores, trusts or applies anything: the result
    # is a PREVIEW, and the admin's save through the unchanged PUT/PATCH
    # path, where Saml.cert_problem and friends are the acceptance gate, is
    # what makes any of it live.
    #
    # ruby-saml's OneLogin::RubySaml::IdpMetadataParser does the XML work,
    # through ONE entry point: parse_to_idp_metadata_array(body, options),
    # one object per IDPSSODescriptor (not per entity), and #to_hash(options)
    # on the ONE object selected, with options sso_binding: [Redirect]. That
    # pair is what parse_to_array does for every descriptor; converting only
    # the selected one means a descriptor that is never read (another
    # entity's, a SAML 1.1 sibling's) cannot fail the parse. Descriptors
    # under more than one EntityDescriptor are an aggregate and refused
    # before any is converted, and one entity's descriptors are narrowed to
    # its SAML 2.0 one (#selected_index). The parse_remote* methods are never
    # called (they fetch with a bare Net::HTTP and no egress guard; the
    # caller fetches through DiscoveryFetcher and hands the body here), and
    # parse_to_hash is never called (it is parse_to_array(...)[0], which
    # silently picks the first IdP of a federation aggregate). What is read
    # from the selected entry, and what is deliberately not:
    #
    #   idp_entity_id            read; the issuer half of the identity key
    #   idp_sso_service_url      read; the first HTTP-Redirect Location
    #   idp_cert_multi[:signing] read; the ONLY certificate source
    #   valid_until, cache_duration  read (refresh pacing hints, Phase 2)
    #   idp_cert                 NEVER read. merge_certificates_into sets it
    #                            only in some shapes, and in the "one use, one
    #                            certificate" shape it is the ENCRYPTION key
    #                            when that is the only key — offered as a
    #                            signing anchor it would fail every sign-in.
    #   idp_cert_fingerprint     NEVER read. Fingerprint trust is refused
    #                            everywhere (SamlFields::FORBIDDEN_PARAMS).
    #   name_identifier_format   NEVER read; the parser keeps one value. All
    #                            advertised formats come from the descriptor
    #                            itself (below).
    #   idp_cert_multi[:encryption]  NEVER read. Encrypted assertions are not
    #                            requested (Saml::SECURITY), so an encryption
    #                            key has no use here.
    #
    # Result has no member for any of the NEVER-read keys, so a later caller
    # cannot reach for an upstream fingerprint or trust option by accident.
    #
    # BINDING. The login path only ever redirects (RequestBoundSAML builds
    # the AuthnRequest with Authrequest#create, i.e. HTTP-Redirect), so the
    # parser is asked for HTTP-Redirect and nothing else, and a POST-only
    # IdP gets no SSO URL rather than a POST endpoint the login would send
    # a redirect to. Which of "no endpoint", "wrong binding" and "endpoint
    # without a Location" applies is read from the SingleSignOnService
    # children of the SAME IDPSSODescriptor the selected entry came from, not
    # inferred from the parser's nil.
    #
    # ERROR BOUNDARY. The whole operation — the parser, the descriptor
    # inspection and the certificate enrichment — runs inside one rescue
    # that turns a document the parser or REXML rejects into
    # Error(:invalid_metadata), and a certificate OpenSSL rejects inside the
    # parser into Error(:unreadable_certificate) (UNREADABLE CERTIFICATES),
    # each with a fixed message: exception text can carry document content
    # and is never echoed. REXML expands entities LAZILY, when text or an
    # attribute value is first read, so an entity reference fails after
    # REXML::Document.new has already succeeded, anywhere a value is read
    # (in the parser or here); hence one boundary around all of it, not a
    # rescue around document construction.
    #
    # UNREADABLE CERTIFICATES. A signing entry OpenSSL will not parse is left
    # out of signing_certificates and reported once, as the advisory
    # unreadable_signing_certificates, so one bad KeyDescriptor beside good
    # ones still leaves the good ones to pick from; when no readable entry
    # is left, no_usable_signing_certificates blocks. One shape fails the
    # whole parse instead: where ruby-saml fingerprints the certificate
    # itself (merge_certificates_into: the descriptor's only certificate,
    # signing or encryption, or one of each that are the same), its
    # CertificateError is raised inside #to_hash before the entry exists,
    # and the boundary maps it to :unreadable_certificate, which names the
    # cause instead of calling the whole document unusable. Only the
    # selected descriptor is converted, so this is always that descriptor's
    # own certificate: it has no sibling to keep, and there is nothing to
    # import either way.
    #
    # ENTITY EXPANSION. ruby-saml's normal load path (xml_security.rb, loaded
    # by `require 'ruby-saml'`) sets REXML::Security.entity_expansion_limit to
    # 0, so ANY reference to a DOCTYPE-declared entity raises on first read;
    # entity_expansion_text_limit stays at REXML's 10,240 bytes. Neither is
    # changed here (they are process-wide). REXML reports both limits with a
    # plain RuntimeError, which this boundary maps to :invalid_metadata only
    # when it is one of REXML's own two fixed messages AND was raised inside
    # the REXML library (#rexml_expansion_error?), so an unrelated
    # RuntimeError still propagates (the endpoint reports it as
    # unexpected_error). REXML never fetches external entities; the caller's
    # body cap bounds the input.
    #
    # LOADING. ruby-saml is required on the first #parse, never at file load:
    # this file is required wherever the domains API is, and the app loads
    # ruby-saml only where SAML is in use (the endpoint refuses before
    # parsing while SAML_ENABLED is off). IdpMetadataParser does not log, so
    # the logger re-point request_bound_saml.rb makes on load is not needed
    # for this path.
    #
    # The structural rules for every value are the platform definition's own
    # (Saml.entity_id_problem, .sso_url_problem, .cert_problem), so "the
    # preview shows no problem" means "the save will accept these values"
    # (session-cookie and policy rules aside, which are not metadata).
    module IdpMetadata
      METADATA_NS      = 'urn:oasis:names:tc:SAML:2.0:metadata'
      REDIRECT_BINDING = 'urn:oasis:names:tc:SAML:2.0:bindings:HTTP-Redirect'
      SAML2_PROTOCOL   = 'urn:oasis:names:tc:SAML:2.0:protocol'
      NAMESPACES       = { 'md' => METADATA_NS }.freeze

      BLOCKING = 'blocking'
      ADVISORY = 'advisory'

      # The Microsoft Entra ID sign-in hosts that serve SAML federation
      # metadata (commercial, US Government, China / 21Vianet). Matched
      # exactly, after downcasing (hostnames are case-insensitive): no
      # subdomain or suffix match.
      ENTRA_METADATA_HOSTS = %w[
        login.microsoftonline.com
        login.microsoftonline.us
        login.partner.microsoftonline.cn
      ].freeze

      # /{tenant}/federationmetadata/2007-06/federationmetadata.xml with ONE
      # nonempty tenant segment (a GUID, a tenant domain or `common`). Both
      # this casing and FederationMetadata/.../FederationMetadata.xml are in
      # circulation and Entra answers both (checked 2026-10-23), so the fixed
      # segments match case-insensitively.
      ENTRA_TENANT_METADATA_PATH = %r{\A/[^/]+/federationmetadata/2007-06/federationmetadata\.xml\z}i

      # The two RuntimeError messages REXML 3.4.4 raises for its expansion
      # limits (document.rb / parsers/baseparser.rb record_entity_expansion,
      # and text.rb / parsers/baseparser.rb for the text-size limit).
      # RE-VERIFY on a REXML bump.
      REXML_EXPANSION_MESSAGES = [
        'number of entity expansions exceeded, processing aborted.',
        'entity expansion has grown too large',
      ].freeze

      # Structural problem with a metadata URL, in words that name the
      # metadata URL (Saml.sso_url_problem's own messages name the SSO URL).
      METADATA_URL_SHAPE_PROBLEM = 'IdP metadata URL must be an https:// URL with a plain hostname, ' \
                                   'no credentials and no fragment'

      # The metadata URL's host is not a public egress target
      # (SsrfProtection#valid_issuer_host?). Used by the callers that do I/O.
      METADATA_URL_HOST_PROBLEM = 'IdP metadata URL must point to a public host'

      # A document the parser, REXML or OpenSSL refused, or one describing
      # more than one IdP. #message is fixed per code and never carries
      # exception text; #reason is the underlying exception's CLASS name
      # (nil for :aggregate_metadata), for a log line.
      class Error < StandardError
        MESSAGES = {
          invalid_metadata: 'The document is not usable SAML 2.0 IdP metadata',
          aggregate_metadata: 'The document describes more than one identity provider',
          unreadable_certificate: 'A certificate in the document could not be read as an X.509 certificate',
        }.freeze

        attr_reader :code, :reason

        def initialize(code, reason: nil)
          @code   = code
          @reason = reason
          super(MESSAGES.fetch(code))
        end
      end

      # One signing certificate as the picker shows it. fingerprint_sha256
      # identifies the certificate; thumbprint_sha1 is DISPLAY-ONLY, for
      # matching the certificate the Entra portal marks active (the portal
      # shows SHA-1 thumbprints). Both are computed here from the DER bytes;
      # neither is a trust input anywhere. problem is Saml.cert_problem(pem):
      # nil means the save will accept this certificate.
      SigningCertificate = Data.define(:pem, :subject, :not_before, :not_after, :fingerprint_sha256, :thumbprint_sha1, :problem) do
        def to_api_h
          {
            pem: pem,
            subject: subject,
            not_before: not_before.getutc.iso8601,
            not_after: not_after.getutc.iso8601,
            fingerprint_sha256: fingerprint_sha256,
            thumbprint_sha1: thumbprint_sha1,
            problem: problem,
          }
        end
      end

      # severity is BLOCKING (the trio must not be imported) or ADVISORY
      # (shown as a warning; the import stays possible).
      Problem = Data.define(:code, :severity, :message) do
        def to_api_h
          { code: code, severity: severity, message: message }
        end
      end

      # A parse that SUCCEEDED, which is not the same as an importable
      # configuration: see #problems. idp_sso_service_url is nil whenever
      # no_sso_url or unsupported_sso_binding is reported, and is never a
      # POST endpoint.
      Result = Data.define(
        :idp_entity_id,
        :idp_sso_service_url,
        :signing_certificates,
        :name_id_formats,
        :valid_until,
        :cache_duration,
        :problems,
      ) do
        def blocking?
          problems.any? { it.severity == BLOCKING }
        end

        # The API response fields (FetchIdpMetadata). valid_until and
        # cache_duration are refresh hints for Phase 2 and not served.
        def to_api_h
          {
            idp_entity_id: idp_entity_id,
            idp_sso_service_url: idp_sso_service_url,
            signing_certificates: signing_certificates.map(&:to_api_h),
            name_id_formats: name_id_formats,
            problems: problems.map(&:to_api_h),
          }
        end
      end

      extend self

      # @param body [String] the fetched document
      # @param metadata_url [String, nil] the URL it was fetched from, for
      #   the tenant_level_entra_metadata advisory; nil skips it
      # @return [Result]
      # @raise [Error] :invalid_metadata, :aggregate_metadata or
      #   :unreadable_certificate
      def parse(body, metadata_url: nil)
        load_parser!
        parse_document(body.to_s, metadata_url)
      end

      # Structural check of a metadata URL: the Saml.sso_url_problem rules
      # (https, a plain host with no trailing dot, no credentials, no
      # fragment; a query is fine), reported in metadata-URL words. No I/O,
      # so the model can use it; callers that fetch or save over the API
      # also require SsrfProtection#valid_issuer_host?.
      #
      # @return [String, nil] problem description, or nil when usable
      def metadata_url_problem(url)
        Saml.sso_url_problem(url).nil? ? nil : METADATA_URL_SHAPE_PROBLEM
      end

      # True for Entra's TENANT-level federation metadata URL, which may
      # publish the tenant's keys rather than this application's signing
      # certificate: an Entra host (exact), the tenant metadata path, and no
      # nonempty `appid` query parameter. `?appid`, `?appid=` and a missing
      # appid are all tenant-level. The query is decoded as form parameters
      # (URI.decode_www_form), never searched as a string; a query that will
      # not decode has no usable appid either.
      #
      # @param url [String, nil]
      # @return [Boolean]
      def tenant_level_entra_metadata?(url)
        uri = URI.parse(url.to_s.strip)
        return false unless uri.is_a?(URI::HTTPS)
        return false unless ENTRA_METADATA_HOSTS.include?(uri.host.to_s.downcase)
        return false unless ENTRA_TENANT_METADATA_PATH.match?(uri.path.to_s)

        !appid_present?(uri.query)
      rescue URI::Error
        false
      end

      private

      def appid_present?(query)
        return false if query.to_s.empty?

        URI.decode_www_form(query).any? { |name, value| name == 'appid' && !value.to_s.strip.empty? }
      rescue ArgumentError
        false
      end

      # The whole gem, not idp_metadata_parser alone: the parser's own
      # fingerprint step needs XMLSecurity, and xml_security.rb is where the
      # expansion limit is set (see ENTITY EXPANSION above).
      def load_parser!
        require 'ruby-saml'
      end

      # See ERROR BOUNDARY / ENTITY EXPANSION in the module header.
      def parse_document(body, metadata_url)
        options     = { sso_binding: [REDIRECT_BINDING] }
        idps        = OneLogin::RubySaml::IdpMetadataParser.new.parse_to_idp_metadata_array(body, options)
        descriptors = idp_descriptors(idps)
        index       = selected_index(descriptors)

        build_result(idps[index].to_hash(options), descriptors[index], metadata_url)
      rescue OpenSSL::X509::CertificateError => ex
        raise Error.new(:unreadable_certificate, reason: ex.class.name), cause: nil
      rescue ArgumentError, REXML::ParseException => ex
        raise Error.new(:invalid_metadata, reason: ex.class.name), cause: nil
      rescue RuntimeError => ex
        raise unless rexml_expansion_error?(ex)

        raise Error.new(:invalid_metadata, reason: 'REXML entity expansion limit'), cause: nil
      end

      # The IDPSSODescriptor element behind each of the parser's objects, in
      # the same order, one per descriptor (not per entity). More than one
      # EntityDescriptor among them is a federation aggregate. Reads no text
      # or attribute value, so nothing is expanded here.
      def idp_descriptors(idps)
        descriptors = idps.map(&:idpsso_descriptor)
        raise Error.new(:invalid_metadata, reason: 'no IDPSSODescriptor') if descriptors.empty?
        raise Error.new(:aggregate_metadata) if descriptors.map(&:parent).uniq(&:object_id).size > 1

        descriptors
      end

      # Which of ONE entity's IDPSSODescriptors to read. A lone descriptor is
      # read as it is. An entity may publish one per protocol (a SAML 1.1
      # descriptor beside the SAML 2.0 one, SAML 2.0 Metadata section 2.4.3);
      # then exactly one must list SAML 2.0 in protocolSupportEnumeration,
      # and that one is read. None, or several, is not a document this form
      # can import without guessing.
      #
      # @return [Integer] index into the descriptors and the parser's objects
      def selected_index(descriptors)
        return 0 if descriptors.size == 1

        saml2 = descriptors.each_index.select do |index|
          descriptors[index].attributes['protocolSupportEnumeration'].to_s.split.include?(SAML2_PROTOCOL)
        end
        raise Error.new(:invalid_metadata, reason: 'no single SAML 2.0 IDPSSODescriptor') unless saml2.size == 1

        saml2.first
      end

      def build_result(entry, descriptor, metadata_url)
        entity_id                = entry[:idp_entity_id]
        entity_problem           = Saml.entity_id_problem(entity_id)
        sso                      = sso_service(descriptor, entry[:idp_sso_service_url])
        certificates, unreadable = signing_certificates(entry)

        problems = []
        problems << blocking('invalid_entity_id', entity_problem) if entity_problem
        problems << sso[:problem] if sso[:problem]
        problems.concat(certificate_problems(certificates, unreadable))
        problems << tenant_level_entra_problem if metadata_url && tenant_level_entra_metadata?(metadata_url)

        Result.new(
          idp_entity_id: entity_id,
          idp_sso_service_url: sso[:url],
          signing_certificates: certificates,
          name_id_formats: name_id_formats(descriptor),
          valid_until: entry[:valid_until],
          cache_duration: entry[:cache_duration],
          problems: problems,
        )
      end

      # The selected descriptor's own SingleSignOnService children decide
      # the category; the URL is the parser's (the first HTTP-Redirect
      # Location), surrounding whitespace stripped as the save path strips
      # it. A nonblank URL still has to pass Saml.sso_url_problem.
      #
      # @return [Hash] :url (String, nil) and :problem (Problem, nil)
      def sso_service(descriptor, parsed_url)
        services = REXML::XPath.match(descriptor, 'md:SingleSignOnService', NAMESPACES)
        if services.empty?
          return { url: nil, problem: blocking('no_sso_url', 'The metadata lists no single sign-on service.') }
        end

        unless services.any? { it.attributes['Binding'] == REDIRECT_BINDING }
          return {
            url: nil,
            problem: blocking(
              'unsupported_sso_binding',
              'The metadata offers single sign-on only through bindings other than HTTP-Redirect, ' \
              'which is the only binding this application uses.',
            ),
          }
        end

        url = parsed_url.to_s.strip
        if url.empty?
          return {
            url: nil,
            problem: blocking('no_sso_url', 'The metadata lists an HTTP-Redirect single sign-on service without a Location.'),
          }
        end

        problem = Saml.sso_url_problem(url)
        { url: url, problem: problem && blocking('invalid_sso_url', problem) }
      end

      # Every NameIDFormat the selected descriptor advertises: trimmed,
      # blanks dropped, duplicates removed, in document order. For display
      # beside the stored policy only: advertisement is not support, and the
      # stored name_id_format is never prefilled from it.
      def name_id_formats(descriptor)
        REXML::XPath.match(descriptor, 'md:NameIDFormat', NAMESPACES)
          .map { OneLogin::RubySaml::Utils.element_text(it).to_s.strip }
          .reject(&:empty?)
          .uniq
      end

      # idp_cert_multi[:signing] and nothing else (see the module header).
      # Each entry is the X509Certificate element text, bare base64;
      # Utils.format_cert wraps it into ONE PEM block, the form the save path
      # accepts. An entry OpenSSL::X509::Certificate.new refuses (an empty
      # element, base64 that is not a certificate) is left out and counted
      # (UNREADABLE CERTIFICATES in the module header).
      #
      # @return [Array(Array<SigningCertificate>, Integer)] the readable
      #   certificates in document order, and the number left out
      def signing_certificates(entry)
        unreadable   = 0
        certificates = Array(entry.dig(:idp_cert_multi, :signing)).filter_map do |base64|
          signing_certificate(base64.to_s)
        rescue OpenSSL::X509::CertificateError
          unreadable += 1
          nil
        end

        [certificates, unreadable]
      end

      def signing_certificate(base64)
        pem  = OneLogin::RubySaml::Utils.format_cert(base64)
        cert = OpenSSL::X509::Certificate.new(pem)
        der  = cert.to_der

        SigningCertificate.new(
          pem: pem,
          subject: cert.subject.to_utf8,
          not_before: cert.not_before,
          not_after: cert.not_after,
          fingerprint_sha256: colon_hex(OpenSSL::Digest::SHA256.digest(der)),
          thumbprint_sha1: colon_hex(OpenSSL::Digest::SHA1.digest(der)),
          problem: Saml.cert_problem(pem),
        )
      end

      # Blocking problems first, then the unreadable-entries advisory.
      def certificate_problems(certificates, unreadable)
        problems = []
        if certificates.empty? && unreadable.zero?
          problems << blocking('no_signing_certificates', 'The metadata lists no signing certificate.')
        elsif certificates.none? { it.problem.nil? }
          problems << blocking(
            'no_usable_signing_certificates',
            'None of the signing certificates in the metadata can be used ' \
            '(each is unreadable, expired, not yet valid, or not an RSA certificate).',
          )
        end
        problems << unreadable_certificates_problem if unreadable.positive?
        problems
      end

      def unreadable_certificates_problem
        Problem.new(
          code: 'unreadable_signing_certificates',
          severity: ADVISORY,
          message: 'Some signing certificates in the metadata could not be read as X.509 ' \
                   'certificates and are not listed.',
        )
      end

      def tenant_level_entra_problem
        Problem.new(
          code: 'tenant_level_entra_metadata',
          severity: ADVISORY,
          message: 'This is the tenant-level Microsoft Entra ID metadata URL. It may list the ' \
                   "tenant's signing keys rather than this application's. Use the App Federation " \
                   "Metadata Url from the application's SAML page in Entra (it ends in ?appid=...).",
        )
      end

      def blocking(code, message)
        Problem.new(code: code, severity: BLOCKING, message: message)
      end

      # "AB:CD:...", upper-case hex pairs as OpenSSL's -fingerprint prints
      # them. The Entra portal shows the same SHA-1 hex digits without the
      # separators.
      def colon_hex(digest)
        digest.unpack1('H*').upcase.scan(/../).join(':')
      end

      # REXML's expansion-limit failure, and nothing else: exactly a
      # RuntimeError (REXML::ParseException is a RuntimeError subclass and
      # is rescued separately), one of REXML_EXPANSION_MESSAGES, raised from
      # a frame inside the loaded REXML library.
      def rexml_expansion_error?(error)
        return false unless error.instance_of?(RuntimeError)
        return false unless REXML_EXPANSION_MESSAGES.include?(error.message)

        frame = error.backtrace_locations&.first
        path  = frame && (frame.absolute_path || frame.path)
        !path.nil? && path.start_with?("#{rexml_library_dir}/")
      end

      # The directory of the REXML library actually loaded (rexml/document.rb
      # and its siblings), located from a method REXML defines rather than
      # from a gem path, so a vendored or default-gem REXML is found too.
      def rexml_library_dir
        File.dirname(REXML::Document.instance_method(:record_entity_expansion).source_location.first)
      end
    end
  end
end
