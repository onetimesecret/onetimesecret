# lib/onetime/utils/telemetry_ref.rb
#
# frozen_string_literal: true

require 'openssl'

require_relative 'strings'

module Onetime
  module Utils
    # TelemetryRef - opaque, stable actor and organization references for
    # third-party telemetry (Sentry).
    #
    # ---------------------------------------------------------------------------
    # WHY THIS EXISTS
    # ---------------------------------------------------------------------------
    # Error reports are far more useful when the same human maps to the same
    # identity across events ("this crash hits one account, not fifty"). Sending
    # an email address, a customer objid, an extid or an IP to an observability
    # backend to get that is not acceptable, so we send a keyed, one-way
    # reference instead: correlation without disclosure. Same posture, same
    # rationale as Onetime::Security::RequestContext (ADR-022) — this is that
    # idea applied to the actor rather than the network.
    #
    # ---------------------------------------------------------------------------
    # WHY NOT REUSE EmailHash.compute
    # ---------------------------------------------------------------------------
    # Onetime::Utils::EmailHash produces the FEDERATION email hash, and that
    # exact value is simultaneously:
    #
    #   * a queryable Redis index (Organization.email_hash + :email_hash_index),
    #     and
    #   * a field written into Stripe customer metadata.
    #
    # Shipping it verbatim to Sentry would hand the telemetry surface a live
    # join key into billing records and our own datastore index. So this module
    # derives a DISTINCT value under an explicit, versioned purpose prefix and a
    # residency element:
    #
    #   actor: HMAC(secret, "onetime:sentry:v1:actor" || 0x00
    #                       || residency_scope || 0x00 || normalized_email)
    #   org:   HMAC(secret, "onetime:sentry:v1:organization" || 0x00
    #                       || residency_scope || 0x00 || org_objid)
    #
    # The NUL-separated elements are the domain separation. Three consequences
    # that the tests pin:
    #   1. actor_ref(email) != EmailHash.compute(email), even when both are keyed
    #      with the same FEDERATION_SECRET;
    #   2. actor_ref(x) under residency "eu" != actor_ref(x) under "us"; and
    #   3. organization_ref(x) != actor_ref(x) for the identical input string,
    #      under identical keying and residency — the purpose prefix is what
    #      separates the two namespaces.
    # The `v1` element lets us re-key telemetry identity later without touching
    # federation identity.
    #
    # Refs are truncated to REF_LENGTH hex chars — deliberately HALF the width of
    # a federation email hash, so the two are never confusable by shape either.
    #
    # ---------------------------------------------------------------------------
    # WHY THERE IS AN ORGANIZATION REF, AND WHAT CONSUMES IT
    # ---------------------------------------------------------------------------
    # An earlier revision added #organization_ref, then deleted it, because it
    # had no consumer: nothing ever put an organization value onto a Sentry
    # event, so there was nothing to resolve FROM, and the derivation cost
    # personal-data budget for a lookup an operator already had org_id and extid
    # for on the same authenticated endpoint. That reasoning was correct about
    # THAT shape of feature. It is re-added here with the consumer supplied.
    #
    # The consumer is the client-side one. Sentry parameterizes the route to
    # /api/colonel/organizations/:org_id and the real id is deliberately never
    # sent, so an operator reading an event today cannot distinguish "one
    # organization is broken" from "every organization is broken" — which is
    # precisely the question the motivating defect raised (a schema parse that
    # blanked the colonel detail page). An opaque ref, attached as a TAG on
    # events from enrolled internal/admin schemas, answers exactly that question
    # and nothing else: two events carrying the same ref concern one
    # organization, and the ref cannot be looked up by anyone holding it.
    #
    # This is a per-RESOURCE ref, not a per-session one. It rides the colonel
    # response record, NOT the bootstrap telemetry block — that block is exactly
    # {actor_ref, actor_scope} and is parsed by a Zod strictObject, so a third
    # key there drops the whole block on the floor.
    #
    # Note the constraint that decides the shape: the motivating case is a
    # response that FAILED validation, so at tag time there is no parsed record
    # to read a ref out of. It has to be recoverable from the RAW payload and
    # shape-validated there, for explicitly enrolled schemas only.
    #
    # ---------------------------------------------------------------------------
    # RESIDENCY SCOPE (why refs deliberately do NOT correlate across regions)
    # ---------------------------------------------------------------------------
    # An earlier revision of this module keyed actor refs off FEDERATION_SECRET
    # alone and sold "one identity per person across regions" as a feature. That
    # is a defect, not a feature, and it is fixed here.
    #
    # The browser SDK tags every event with `jurisdiction`
    # (src/plugins/core/enableDiagnostics.ts) and the Ruby SDK does the same
    # (Onetime::Initializers::SetupDiagnostics). Regional instances share one
    # FEDERATION_SECRET by design and report into ONE telemetry backend. A
    # region-independent ref therefore emits the identical user id from the EU
    # instance and the US instance, distinguished only by that tag — which is a
    # ready-made join key proving that one data subject is present in both. A
    # keyed pseudonym is still personal data (GDPR Recital 26), so that join is
    # exactly the inference the jurisdictional-residency architecture exists to
    # prevent, and no amount of tagging discipline elsewhere undoes it.
    #
    # Against that, cross-region correlation buys nothing operationally, and it
    # is worth stating plainly rather than hedging: there is NO legitimate
    # operational use for it here. Error triage is per-instance — a stack trace
    # raised in the EU instance is debugged against the EU instance's code,
    # config, and datastore. "Is this the same human as the one erroring in the
    # US?" is a product-analytics question, not a debugging one, and it is not a
    # question this data is allowed to answer. So the residency scope is mixed
    # into the derivation UNCONDITIONALLY and there is no opt-out knob — an
    # opt-out would exist only to reconstruct the hazard.
    #
    # The residency scope resolves in this order:
    #
    #   1. TELEMETRY_REF_REGION — explicit operator pin. Use this when
    #      residency boundaries do not line up with the regions feature: two
    #      installs that share FEDERATION_SECRET, both with regions disabled,
    #      but serving different jurisdictions. Any short stable label works
    #      ('eu', 'us', 'ca-central'); it is never emitted, only mixed in.
    #
    #   2. features.regions.current_jurisdiction (JURISDICTION) — the same
    #      value the Sentry `jurisdiction` tag is derived from, so the
    #      separation lines up with what an operator sees in the UI.
    #
    #   3. Nothing declared -> UNRESOLVED (nil), and the shared key is refused.
    #      See the next section; this is the case that used to fail open.
    #
    # ---------------------------------------------------------------------------
    # AN UNDECLARED RESIDENCY REFUSES THE SHARED SECRET (the default is safe)
    # ---------------------------------------------------------------------------
    # An earlier revision of this fix mixed a constant — RESIDENCY_UNSCOPED —
    # into the pre-image whenever nothing was declared. That defaulted straight
    # back into the hazard it documented: two installs sharing FEDERATION_SECRET
    # and declaring no residency derived IDENTICAL refs into one backend, which
    # is exactly the cross-region join above. The mechanism only ever engaged if
    # somebody thought to turn it on.
    #
    # That gets the population backwards. FEDERATION_SECRET is shared BECAUSE
    # instances are regional, so "declared nothing" is the population most at
    # risk, not the one that is safe — and a residency guarantee that has to be
    # switched on is not a guarantee. The safe state must be the one an operator
    # gets for free.
    #
    # So an unresolved residency does not widen the ref; it withdraws the key.
    # #keying declines FEDERATION_SECRET and falls through to ACCOUNT_ID_SECRET,
    # yielding scope 'deployment'. That is:
    #
    #   * strictly safer — per-install correlation is all error triage needs;
    #   * self-limiting — it can only ever narrow correlation, never widen it;
    #   * honest — the emitted actor_scope label narrows with it, so an operator
    #     reading a Sentry event is never told a ref is comparable further than
    #     it actually is.
    #
    # An operator who genuinely wants federated correlation within one
    # jurisdiction gets it by declaring that jurisdiction. There is no path to
    # cross-install correlation that requires configuring nothing.
    #
    # RESIDENCY_UNSCOPED survives only as the literal pre-image element used
    # under deployment keying, so the element count in the pre-image never
    # varies. It no longer grants correlation to anyone. One caveat code cannot
    # enforce: an operator who copies ACCOUNT_ID_SECRET between installs
    # rebuilds cross-install correlation under a 'deployment' label. That secret
    # is generated per install and documented as un-shareable; sharing it is a
    # configuration error with consequences well beyond telemetry.
    #
    # ---------------------------------------------------------------------------
    # ONE RESIDENCY RESOLUTION PER DERIVATION
    # ---------------------------------------------------------------------------
    # Residency is read ONCE per derivation and then threaded. #keying resolves
    # it and returns it inside a Keying value alongside the secret it selected
    # and the label that secret implies; #digest_ref and #actor consume that one
    # value and never re-resolve.
    #
    # This is not tidiness. An earlier revision resolved residency THREE times
    # per emitted bundle — in #keying to choose the secret, again in #digest_ref
    # to build the pre-image, a third time via #scope to build the label — from
    # unsynchronized reads of OT.conf. Any change between those reads produced
    # three defects at once. A jurisdiction edited between reads was enough; so
    # was an OT.conf that went FALSY rather than raising, which the raise-based
    # guard below does not catch because nothing raises:
    #
    #   * one human in one process derived TWO different refs — the actor split
    #     that fail-closed residency handling exists to prevent;
    #   * two installs in DIFFERENT jurisdictions sharing FEDERATION_SECRET
    #     derived the IDENTICAL ref, because both substituted RESIDENCY_UNSCOPED
    #     into a pre-image still keyed with the shared secret — the cross-region
    #     join, reconstructed by a race;
    #   * the label LIED DOWNWARD, reading 'deployment' over a federation-keyed
    #     ref, inverting the honesty property claimed two sections up.
    #
    # Threading one value makes the first two unrepresentable. The third is now
    # ENFORCED rather than asserted: #digest_ref emits nothing at all when it is
    # handed FEDERATION_SECRET keying with no residency, so the constant can
    # never be substituted under the shared key.
    #
    # Stated exactly, so the comment does not outrun the code. Guaranteed: the
    # residency mixed into a ref and the scope label emitted beside it come from
    # ONE read of the config, and a 'federated' ref always carries a resolved
    # residency. NOT guaranteed: that two derivations minutes apart agree — an
    # operator who changes the declared jurisdiction has re-keyed telemetry
    # identity, and that splits the actor by design.
    #
    # ---------------------------------------------------------------------------
    # SECRET SELECTION ORDER (and what the scope label means)
    # ---------------------------------------------------------------------------
    #   1. FEDERATION_SECRET  -> scope 'federated'
    #      ONLY when a residency scope resolves. Correlation then holds across
    #      installs that share the secret AND resolve to the SAME residency
    #      scope. It does NOT hold across jurisdictions; see above. With no
    #      residency declared this option is skipped entirely.
    #
    #   2. ACCOUNT_ID_SECRET  -> scope 'deployment'
    #      Per-deployment. Correlation holds within this install only.
    #      NOTE: we consume the raw secret VALUE as an HMAC key here. We do NOT
    #      use Rodauth's account-id obfuscation cipher — that is an
    #      Integer<->13-char bijection over the accounts PK, it cannot take an
    #      email, and the integer PK is not reachable from an Otto request.
    #      Read from ENV only, never from Rodauth's configured value: when
    #      ACCOUNT_ID_SECRET is unset outside production Rodauth substitutes a
    #      fixed placeholder literal, which would make every dev install on
    #      earth derive identical refs.
    #
    #   3. Neither configured -> nil, and the caller emits nothing.
    #
    # The scope label travels with the ref so an operator reading a Sentry event
    # knows how far the id is comparable. It is a property of the KEY, not of
    # the account. The label values are a closed enum on the client
    # (ACTOR_SCOPES in src/schemas/contracts/bootstrap.ts) — adding a value here
    # without adding it there makes the strict parse fail and drops the whole
    # telemetry block.
    #
    # ---------------------------------------------------------------------------
    # FAILURE TOLERANCE
    # ---------------------------------------------------------------------------
    # Neither secret is configured by default: FEDERATION_SECRET is commented out
    # in .env.example and .env.reference, and ACCOUNT_ID_SECRET is only required
    # in production. That is the NORMAL state on a developer box, so an
    # unconfigured deployment must render pages exactly as before.
    #
    # Every public method therefore returns nil rather than raising, and the
    # WHOLE derivation — normalization included — is wrapped so a surprise from
    # OpenSSL, config access, or a badly encoded stored email cannot escape into
    # a render path. TelemetrySerializer runs on every authenticated render of
    # all three web shells, so an escaping exception means a 500 page AND a
    # self-inflicted Sentry event; telemetry code taking the site down is the
    # one outcome worth engineering against. Encoding is the live hazard there:
    # a stored email tagged ASCII-8BIT, or holding an invalid byte, makes
    # String#unicode_normalize raise Encoding::CompatibilityError or
    # ArgumentError. See #normalized_email.
    #
    # Failures are logged at debug level with the exception CLASS only; never
    # the value, never the key.
    #
    # Fail-soft is NOT the same as fail-open. Where a failure could change WHICH
    # identity a human gets rather than whether they get one, the answer is nil
    # — a gap in telemetry identity — never a substitute value. See
    # #resolve_residency for the case that motivated the distinction.
    #
    # @see Onetime::Security::RequestContext (the network-side analogue)
    # @see Onetime::Utils::EmailHash (federation identity — deliberately NOT this)
    module TelemetryRef
      extend self

      # Canonical email normalization (NFC + case folding + strip), shared with
      # OT::Utils rather than copied. EmailHash keeps a parallel private copy
      # because it loads before Utils during boot; this module has no such
      # constraint, so it reuses the canonical implementation and cannot drift.
      extend Onetime::Utils::Strings

      # Versioned purpose prefix. Changing the value re-keys actor refs only.
      ACTOR_INFO = 'onetime:sentry:v1:actor'

      # Versioned purpose prefix for ORGANIZATION refs. Distinct from
      # ACTOR_INFO, which is the whole of the domain separation between the two
      # namespaces: the same literal string handed to both entry points must not
      # digest to the same value, or an operator holding one ref could test it
      # against the other surface. Pinned by execution in the tryouts and in
      # spec, not merely asserted here.
      ORGANIZATION_INFO = 'onetime:sentry:v1:organization'

      # Separator between derivation elements. A byte that cannot occur in an
      # email, a jurisdiction id or an objid, so no element can be shifted into
      # a neighbour's position by a crafted value.
      SEPARATOR = "\x00"

      # Pre-image element used when no residency resolves. Literal rather than
      # empty string so the element count in the pre-image never varies.
      #
      # It is NOT a residency scope and grants no correlation. Two independent
      # mechanisms keep it off the shared key: #keying declines
      # FEDERATION_SECRET when no residency resolves, and #digest_ref refuses to
      # emit anything at all if it is nonetheless handed federated keying with
      # no residency. So this element only ever reaches a pre-image under a
      # per-deployment key.
      RESIDENCY_UNSCOPED = 'unscoped'

      # Explicit operator pin for the residency scope. See the module docstring.
      RESIDENCY_ENV = 'TELEMETRY_REF_REGION'

      # Hex chars retained (64 bits). Ample to group events by actor, and half
      # the width of EmailHash::HASH_LENGTH so refs are visibly not email hashes.
      REF_LENGTH = 16

      # Correlation scope labels — a property of which secret keyed the ref.
      SCOPE_FEDERATED  = 'federated'
      SCOPE_DEPLOYMENT = 'deployment'

      # One derivation's keying decision, resolved together and threaded as a
      # unit: the HMAC key, the label that key implies, and the residency read
      # that SELECTED that key. Bundling them is the mechanism — a caller cannot
      # pair a ref with a label sourced from a different read of the config,
      # because there is only one read to source either from.
      #
      # @!attribute [r] secret   [String] HMAC key. Never logged, never emitted.
      # @!attribute [r] scope    [String] SCOPE_FEDERATED or SCOPE_DEPLOYMENT.
      # @!attribute [r] residency [String, nil] resolved residency label; nil
      #   only ever accompanies SCOPE_DEPLOYMENT.
      Keying = Data.define(:secret, :scope, :residency)

      # Opaque actor reference derived from the account's normalized email.
      #
      # @param email [String, nil] account email, any casing/whitespace, any
      #   encoding (including a mis-tagged or corrupt one).
      # @return [String, nil] REF_LENGTH hex chars, or nil when the email is
      #   blank or unusable, no secret is configured, or derivation failed.
      def actor_ref(email)
        # The block is evaluated INSIDE digest_ref's rescue. Normalizing out
        # here would put unicode_normalize outside the guard, which is how a
        # non-UTF-8 stored email turns into a 500 on every authenticated render.
        digest_ref(ACTOR_INFO, keying) { normalized_email(email) }
      end

      # Opaque organization reference derived from the organization's objid.
      #
      # Same keying, same residency threading and the same fail-closed
      # conditions as #actor_ref — both route through #keying and #digest_ref,
      # so there is one place where "is this key usable?" is decided and the two
      # cannot drift apart. It returns nil under exactly the conditions
      # #actor_ref returns nil for a usable email.
      #
      # NOT NORMALIZED, unlike an email, and that is deliberate. Emails are
      # normalized because a human types the same address five ways; an objid is
      # a server-minted canonical token that no human types, so there is nothing
      # to reconcile. Case folding it would be actively wrong: objid alphabets
      # are case-sensitive, so folding could map two distinct organizations onto
      # one ref — the opposite of the property the ref exists to provide.
      # Surrounding whitespace is trimmed only so a padded value cannot split
      # one organization into two refs, and the trim is what the blank check
      # runs against.
      #
      # @param identifier [String, nil] organization objid.
      # @return [String, nil] REF_LENGTH hex chars, or nil when the identifier
      #   is blank or unusable, no secret is configured, or derivation failed.
      def organization_ref(identifier)
        digest_ref(ORGANIZATION_INFO, keying) { organization_pre_image(identifier) }
      end

      # Which correlation scope the configured secret provides.
      #
      # @return [String, nil] SCOPE_FEDERATED, SCOPE_DEPLOYMENT, or nil when
      #   neither secret is configured.
      def scope
        keying&.scope
      end

      # Convenience bundle for the bootstrap payload.
      #
      # Returns nil — not a hash of nils — when there is nothing to say, so a
      # caller can omit the telemetry block entirely for anonymous sessions and
      # unconfigured deployments alike.
      #
      # ONE keying resolution serves both fields. The ref and the label it is
      # emitted with therefore always describe the same read of the config;
      # calling #actor_ref and #scope separately would reintroduce the split
      # this bundle exists to close.
      #
      # @param email [String, nil] account email.
      # @return [Hash{String=>String}, nil] string-keyed, JSON-ready.
      def actor(email)
        key = keying
        return nil if key.nil?

        ref = digest_ref(ACTOR_INFO, key) { normalized_email(email) }
        return nil if ref.nil?

        { 'actor_ref' => ref, 'actor_scope' => key.scope }
      end

      # True when a secret is available and refs can be derived.
      #
      # @return [Boolean]
      def available?
        !keying.nil?
      end

      # The HMAC key, the scope label it implies, and the residency read that
      # selected it — resolved together, in that one order, and returned as a
      # unit. This is the ONLY place a derivation resolves residency.
      #
      # @return [Keying, nil] nil when no secret is usable.
      def keying
        residency  = resolve_residency
        federation = federation_secret

        # FEDERATION_SECRET is shared across regional instances BY DESIGN, so
        # keying an actor ref with it while no residency scope is declared is
        # precisely the cross-region join this module exists to prevent. An
        # undeclared residency therefore DECLINES the shared key instead of
        # widening the ref, and we fall through to the per-deployment one.
        if residency && !federation.to_s.empty?
          return Keying.new(secret: federation, scope: SCOPE_FEDERATED, residency: residency)
        end

        # ENV only — see the ACCOUNT_ID_SECRET note in the module docstring.
        account = ENV.fetch('ACCOUNT_ID_SECRET', nil)
        unless account.to_s.empty?
          # residency may be present here too (declared, but no federation
          # secret configured); it is carried so the pre-image element and the
          # label still come from the same read.
          return Keying.new(secret: account, scope: SCOPE_DEPLOYMENT, residency: residency)
        end

        nil
      rescue StandardError => ex
        OT.ld "[telemetry-ref] secret lookup failed: #{ex.class}" if defined?(OT)
        nil
      end

      # The data-residency scope this deployment declares, if any.
      #
      # Public because it is a deployment property an operator may reasonably
      # want to assert on in a boot check; it is never emitted to telemetry.
      # The nil answer is load-bearing rather than cosmetic — it is what makes
      # #keying refuse FEDERATION_SECRET and drop to deployment scope.
      #
      # Raise-free for introspection. The derivation path deliberately does NOT
      # come through here: #keying calls the raising #resolve_residency — once —
      # so a config fault costs a ref rather than handing back a different one.
      #
      # @return [String, nil] lowercase label, never blank; nil when the
      #   deployment declares no residency or the config read failed.
      def residency_scope
        resolve_residency
      rescue StandardError => ex
        OT.ld "[telemetry-ref] residency lookup failed: #{ex.class}" if defined?(OT)
        nil
      end

      private

      # Residency resolution. RAISES on a failed config read — deliberately.
      #
      # An earlier revision rescued to RESIDENCY_UNSCOPED here and claimed the
      # fallback "can only ever widen correlation". That was wrong in the way
      # that matters. A transient OT.conf failure on some renders and not others
      # made ONE human derive TWO different refs, splitting one Sentry actor in
      # two — which destroys "is this one user or fifty?", the single question a
      # pseudonymous id exists to answer — while silently re-widening
      # correlation for the duration of the fault.
      #
      # Failing closed instead: the raise propagates into the rescue in #keying,
      # which answers nil, so a fault costs a GAP in telemetry identity for as
      # long as it lasts. A gap is honest and self-healing. A second identity
      # for the same human is neither.
      #
      # Raising is only half the guard, and the missing half was a live defect:
      # a falsy OT.conf resolves to nil WITHOUT raising. That is why residency
      # is resolved exactly once per derivation and threaded (see the Keying
      # value and #digest_ref) rather than re-read and defaulted.
      #
      # @return [String, nil] declared label, or nil when nothing is declared.
      def resolve_residency
        pinned = ENV.fetch(RESIDENCY_ENV, nil).to_s.strip
        return pinned.downcase unless pinned.empty?

        declared = current_jurisdiction.to_s.strip
        declared.empty? ? nil : declared.downcase
      end

      # The same source SetupDiagnostics derives the Sentry `jurisdiction` tag
      # from, so the residency boundary matches what operators see on events.
      #
      # @return [String, nil]
      def current_jurisdiction
        return nil unless defined?(OT) && OT.respond_to?(:conf) && OT.conf

        OT.conf.dig('features', 'regions', 'current_jurisdiction')
      end

      # FEDERATION_SECRET from the environment, falling back to site config —
      # the same resolution order EmailHash#fetch_secret uses, minus the raise.
      #
      # @return [String, nil]
      def federation_secret
        secret = ENV.fetch('FEDERATION_SECRET', nil)
        return secret unless secret.to_s.empty?

        return nil unless defined?(OT) && OT.respond_to?(:conf) && OT.conf

        OT.conf.dig('site', 'federation_secret')
      end

      # Normalized email pre-image, safe for arbitrary stored bytes.
      #
      # OT::Utils.normalize_email calls String#unicode_normalize, which raises
      # on any receiver that is not valid UTF-8. Emails reach us from the
      # datastore, from SSO providers and from legacy rows, so all three of
      # these are reachable in production:
      #
      #   "a\xFF@b.com"                                -> CompatibilityError
      #   "alice@example.com".force_encoding('BINARY') -> CompatibilityError
      #   "\xC3(@b.com"                                -> ArgumentError
      #
      # The middle case is the common and recoverable one: correct UTF-8 bytes
      # carrying the wrong encoding tag. Re-tagging recovers it and yields
      # byte-identical output to the properly tagged string, so a mis-tagged
      # row still correlates with itself instead of silently losing its ref.
      # Genuinely invalid bytes yield '', which digest_ref turns into nil.
      #
      # @param email [String, nil]
      # @return [String] normalized address, or '' when unusable.
      def normalized_email(email)
        raw = email.to_s
        raw = raw.dup.force_encoding(Encoding::UTF_8) unless raw.encoding == Encoding::UTF_8
        return '' unless raw.valid_encoding?

        normalize_email(raw)
      end

      # Organization pre-image, safe for arbitrary stored bytes.
      #
      # No unicode_normalize here — see #organization_ref for why an objid is
      # not normalized like an email. The encoding guard is kept anyway, because
      # dropping unicode_normalize does NOT make this path encoding-safe:
      #
      #   "a\xFForg".strip  ->  Encoding::CompatibilityError
      #
      # (executed, not assumed — String#strip raises on an invalid byte sequence
      # even in UTF-8). digest_ref's rescue would swallow that, so the guard is
      # not what keeps a render alive; what it buys is determinism. An unusable
      # identifier takes the SAME '' -> nil route as a blank one instead of
      # depending on a rescue, and ASCII bytes carrying a binary encoding tag
      # are re-tagged and still correlate with themselves rather than being
      # dropped.
      #
      # @param identifier [String, nil]
      # @return [String] trimmed identifier, or '' when unusable.
      def organization_pre_image(identifier)
        raw = identifier.to_s
        raw = raw.dup.force_encoding(Encoding::UTF_8) unless raw.encoding == Encoding::UTF_8
        return '' unless raw.valid_encoding?

        raw.strip
      end

      # Keyed, purpose- and residency-separated, truncated digest. NEVER raises.
      #
      # The pre-image is produced by the block so that normalization runs inside
      # this method's rescue rather than at the call site.
      #
      # Residency is NOT re-resolved here. It arrives inside `key`, from the
      # single resolution #keying performed when it chose the secret, so the
      # pre-image element and the emitted label cannot disagree.
      #
      # @param info [String] versioned purpose prefix (ACTOR_INFO or
      #   ORGANIZATION_INFO). This element is the only thing separating the two
      #   ref namespaces, so it must never be passed a caller-supplied value.
      # @param key [Keying, nil] the caller's single keying resolution.
      # @yieldreturn [String, nil] the pre-image.
      # @return [String, nil]
      def digest_ref(info, key)
        return nil if key.nil? || key.secret.to_s.empty?

        residency = key.residency.to_s

        # The honesty invariant, enforced rather than asserted. Substituting
        # RESIDENCY_UNSCOPED under FEDERATION_SECRET is exactly the cross-region
        # join: every install sharing that secret would derive the same ref.
        # #keying cannot produce this pairing today; the check is here so that a
        # future edit which makes it producible fails closed instead of silently
        # widening correlation.
        return nil if key.scope == SCOPE_FEDERATED && residency.empty?

        value = yield.to_s
        return nil if value.empty?

        # RESIDENCY_UNSCOPED therefore only ever reaches the pre-image under
        # deployment keying, where it grants no cross-install correlation.
        element = residency.empty? ? RESIDENCY_UNSCOPED : residency
        message = [info, element, value].join(SEPARATOR)
        OpenSSL::HMAC.hexdigest('SHA256', key.secret, message)[0, REF_LENGTH]
      rescue StandardError => ex
        # Class only: the message could carry the pre-image or the key.
        OT.ld "[telemetry-ref] derivation failed: #{ex.class}" if defined?(OT)
        nil
      end
    end
  end
end
