# lib/onetime/utils/diagnostics_ref.rb
#
# frozen_string_literal: true

require 'openssl'

module Onetime
  module Utils
    # DiagnosticsRef - opaque, stable actor and organization references for the
    # third-party diagnostics backend (Sentry).
    #
    # ---------------------------------------------------------------------------
    # WHY THIS EXISTS
    # ---------------------------------------------------------------------------
    # This is DIAGNOSTICS, not analytics and not metrics. The refs exist so that
    # a defect can be diagnosed; they are not there to measure usage, count
    # events for reporting, or profile anyone's behaviour. Every widening of
    # what they disclose has to be justified against THAT purpose, and a
    # justification that reads "it would be interesting to know" is a refusal.
    #
    # Error reports are far more useful when the same account maps to the same
    # reference across events ("this crash hits one account, not fifty"). Sending
    # an email address, a customer objid, an extid or an IP to an observability
    # backend to get that is not acceptable, so we send a keyed, one-way
    # reference instead: correlation without disclosure. Same posture, same
    # rationale as Onetime::Security::RequestContext (ADR-022) — this is that
    # idea applied to the actor rather than the network.
    #
    # ---------------------------------------------------------------------------
    # THE CORRELATION SUBJECT IS THE RECORD, NOT THE HUMAN
    # ---------------------------------------------------------------------------
    # An actor ref derives from the customer EXTID — the server-minted external
    # identifier — and never from the email. That is not a concession; it is the
    # more correct subject:
    #
    #   * an extid is stable across an email change (change_email mutates the
    #     email in place and keeps the record), so an email pre-image would SPLIT
    #     one account into two Sentry users the moment somebody changed address;
    #   * an email is reassignable, so an email pre-image would CONFLATE two
    #     different people after an address reassignment or a
    #     delete-and-recreate. An extid cannot.
    #
    # A returning user who deleted and re-signed-up therefore counts as a new
    # subject. Under "the subject is the record" that is the right answer.
    #
    # Two security properties follow, and neither is immunity:
    #
    #   * PRE-IMAGE ENTROPY. Under key compromise, an email pre-image is
    #     re-identifiable offline against cheap public address lists. An extid
    #     pre-image moves that attack to "leaked key PLUS an auxiliary extid
    #     dataset". Extids are not secret — they appear in bootstrap payloads,
    #     API responses and logs, which is their job — but they are
    #     non-enumerable and not dictionary-shaped.
    #   * ERASURE. An email ref re-links a data subject across deletion and
    #     re-signup inside the retention window. An extid ref does not.
    #
    # NO RESIDENCY DISCRIMINATOR. Extids are minted per install from per-install
    # objids, so separately provisioned regional customer records do not
    # correlate across regions BY DEFAULT — there is nothing to mix in to
    # achieve it. The residual case (a cloned datastore plus a copied
    # ACCOUNT_ID_SECRET reporting into one Sentry project) is operator
    # self-misconfiguration and is accepted, rather than reintroducing a
    # residency apparatus to defend against it.
    #
    # The full argument, the rejected alternatives and the accepted costs are in
    # docs/specs/diagnostics/actor-ref-preimage-debate-decision.md. Do not
    # re-litigate the email pre-image here.
    #
    # ---------------------------------------------------------------------------
    # KEYING: ACCOUNT_ID_SECRET, DELIBERATELY COUPLED
    # ---------------------------------------------------------------------------
    # One secret keys both namespaces: ACCOUNT_ID_SECRET, read from ENV only.
    #
    #   * Read from ENV, never from Rodauth's configured value. When
    #     ACCOUNT_ID_SECRET is unset outside production Rodauth substitutes a
    #     fixed placeholder literal, which would make every dev install on earth
    #     derive identical refs.
    #   * The raw secret VALUE is consumed as an HMAC key. This is NOT Rodauth's
    #     account-id obfuscation cipher — that is an Integer<->13-char bijection
    #     over the accounts PK, which cannot take an extid.
    #   * Not configured -> nil, and the caller emits nothing.
    #
    # The purpose prefix namespaces the two ref families but does not enable
    # independent rotation: refs are only as strong as ACCOUNT_ID_SECRET, and
    # rotating that secret ROTATES EVERY REF. That coupling is an accepted
    # operator decision rather than an oversight — a dedicated
    # DIAGNOSTICS_REF_SECRET would buy robustness in a compromise scenario whose
    # marginal exposure is already small, at zero diagnostic gain. Under the
    # 14-day Sentry retention the post-rotation discontinuity ages out on its
    # own and is a non-event.
    #
    # FEDERATION_SECRET is NOT used here. Onetime::Utils::EmailHash still owns
    # it for federation; diagnostics deliberately does not touch it.
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
    # Shipping it verbatim to Sentry would hand the diagnostics surface a live
    # join key into billing records and our own datastore index. So this module
    # derives DISTINCT values under explicit, versioned purpose prefixes:
    #
    #   actor: HMAC(secret, "onetime:sentry:v2:actor"        || 0x00 || extid)
    #   org:   HMAC(secret, "onetime:sentry:v2:organization" || 0x00 || objid)
    #
    # The NUL-separated elements are the domain separation. Two consequences the
    # tests pin by execution, not assertion:
    #   1. actor_ref(x) != EmailHash.compute(x); and
    #   2. organization_ref(x) != actor_ref(x) for the identical input string
    #      under identical keying — the purpose prefix is the whole of the
    #      separation between the two namespaces.
    #
    # Refs are truncated to REF_LENGTH hex chars — deliberately HALF the width of
    # a federation email hash, so the two are never confusable by shape either.
    #
    # ---------------------------------------------------------------------------
    # BOUNDARY ATTRIBUTION LOSS (bought knowingly)
    # ---------------------------------------------------------------------------
    # Some capture sites hold no extid: account creation before the customer
    # record exists, email-only credential flows, and datastore-outage rescues
    # that hold only an email. Those events are still captured and still group
    # by the ordinary grouping rules — what is unanswerable for that class is
    # actor cardinality ("one account or many?"). That is the price of the
    # pre-image choice and it was paid on purpose; a true identity need on the
    # auth surface resolves at support time by asking the user.
    #
    # ---------------------------------------------------------------------------
    # ORGANIZATION REFERENCE: DEFERRED FRONTEND CONSUMER
    # ---------------------------------------------------------------------------
    # #organization_ref is emitted on the Colonel organization-detail response,
    # but it is not an active Sentry correlation feature. The current frontend
    # response schema discards the field, and no frontend code attaches it to a
    # Sentry event. Do not document or rely on organization correlation until a
    # strict response contract and a narrowly scoped consumer land together.
    #
    # This remains a per-resource value, not a per-session value. It must never
    # be added to the bootstrap `diagnostics_ref` block: that block is exactly
    # {actor_ref} and the frontend parses it as a Zod strictObject. A second key
    # would make the client discard the entire actor block.
    #
    # ---------------------------------------------------------------------------
    # FAILURE TOLERANCE
    # ---------------------------------------------------------------------------
    # ACCOUNT_ID_SECRET is only required in production. Unconfigured is the
    # NORMAL state on a developer box, so an unconfigured deployment must render
    # pages exactly as before.
    #
    # No public method therefore propagates a StandardError: each answers nil
    # instead (false for #available?), and the WHOLE derivation is wrapped so a
    # surprise from OpenSSL or from config access cannot escape into a render
    # path. DiagnosticsSerializer runs on every authenticated render of all
    # three web shells, so an escaping exception means a 500 page AND a
    # self-inflicted Sentry event; diagnostics code taking the site down is the
    # one outcome worth engineering against.
    #
    # Failures are logged at debug level with the exception CLASS only; never
    # the value, never the key.
    #
    # Fail-soft is NOT the same as fail-open. Where a failure could change WHICH
    # reference a subject gets rather than whether it gets one, the answer is
    # nil — a gap in diagnostics reference — never a substitute value.
    #
    # @see Onetime::Security::RequestContext (the network-side analogue)
    # @see Onetime::Utils::EmailHash (federation reference — deliberately NOT this)
    module DiagnosticsRef
      extend self

      # Versioned purpose prefix. Changing the value re-keys actor refs only.
      #
      # v1 mixed in a data-residency element and, for actors, a normalized EMAIL
      # pre-image. v2 is a two-element message over the server-minted extid
      # (actor) or objid (organization). The bump makes the accepted re-key
      # discontinuity legible: refs derived before this change do not match refs
      # derived after it.
      ACTOR_INFO = 'onetime:sentry:v2:actor'

      # Versioned purpose prefix for ORGANIZATION refs. Distinct from
      # ACTOR_INFO, which is the whole of the domain separation between the two
      # namespaces: the same literal string handed to both entry points must not
      # digest to the same value, or an operator holding one ref could test it
      # against the other surface. Pinned by execution in the tryouts and in
      # spec, not merely asserted here.
      ORGANIZATION_INFO = 'onetime:sentry:v2:organization'

      # Separator between derivation elements. A byte that cannot occur in an
      # extid or an objid, so no element can be shifted into a neighbour's
      # position by a crafted value.
      SEPARATOR = "\x00"

      # Hex chars retained (64 bits). Ample to group events by account, and half
      # the width of EmailHash::HASH_LENGTH so refs are visibly not email hashes.
      REF_LENGTH = 16

      # Opaque actor reference derived from the customer's external identifier.
      #
      # NOT NORMALIZED — no case folding, no unicode normalization. An extid is
      # a server-minted canonical token that no human types, so there is nothing
      # to reconcile, and folding case could map two distinct records onto one
      # ref. See #pre_image for the encoding guard that survives from the email
      # era.
      #
      # @param extid [String, nil] customer extid (e.g. "ur<base36>").
      # @return [String, nil] REF_LENGTH hex chars, or nil when the extid is
      #   blank or unusable, no secret is configured, or derivation failed.
      def actor_ref(extid)
        digest_ref(ACTOR_INFO, keying) { pre_image(extid) }
      end

      # Opaque organization reference derived from the organization's objid.
      #
      # Same keying and the same fail-closed conditions as #actor_ref — both
      # route through #keying and #digest_ref, so there is one place where "is
      # this key usable?" is decided and the two cannot drift apart.
      #
      # @param identifier [String, nil] organization objid.
      # @return [String, nil] REF_LENGTH hex chars, or nil when the identifier
      #   is blank or unusable, no secret is configured, or derivation failed.
      def organization_ref(identifier)
        digest_ref(ORGANIZATION_INFO, keying) { pre_image(identifier) }
      end

      # Convenience bundle for the bootstrap payload.
      #
      # Returns nil — not a hash of nils — when there is nothing to say, so a
      # caller can omit the `diagnostics_ref` block entirely for anonymous
      # sessions and unconfigured deployments alike.
      #
      # EXACTLY ONE KEY. The frontend parses this as a Zod strictObject; a
      # second key makes the parse fail and the client drops the whole block.
      #
      # @param extid [String, nil] customer extid.
      # @return [Hash{String=>String}, nil] string-keyed, JSON-ready.
      def actor(extid)
        secret = keying
        return nil if secret.nil?

        ref = digest_ref(ACTOR_INFO, secret) { pre_image(extid) }
        return nil if ref.nil?

        { 'actor_ref' => ref }
      end

      # True when a secret is available and refs can be derived.
      #
      # @return [Boolean]
      def available?
        !keying.nil?
      end

      # The HMAC key, or nil when none is usable.
      #
      # ENV only — see the ACCOUNT_ID_SECRET note in the module docstring.
      # Raise-free: a surprise from the environment read costs a ref, never a
      # render.
      #
      # @return [String, nil] the secret. Never logged, never emitted.
      def keying
        secret = ENV.fetch('ACCOUNT_ID_SECRET', nil)
        return nil if secret.to_s.empty?

        secret
      rescue StandardError => ex
        OT.ld "[diagnostics-ref] secret lookup failed: #{ex.class}" if defined?(OT)
        nil
      end

      private

      # Pre-image for both namespaces, safe for arbitrary stored bytes.
      #
      # Extids and objids are ASCII by construction, so the encoding guard is
      # defence rather than a live recovery path — but it is kept, because
      # String#strip RAISES on an invalid byte sequence even in UTF-8:
      #
      #   "a\xFFur".strip  ->  Encoding::CompatibilityError
      #
      # (executed, not assumed). digest_ref's rescue would swallow that, so the
      # guard is not what keeps a render alive; what it buys is determinism. An
      # unusable identifier takes the SAME '' -> nil route as a blank one
      # instead of depending on a rescue, and ASCII bytes carrying a binary
      # encoding tag are re-tagged and still correlate with themselves rather
      # than being dropped.
      #
      # Surrounding whitespace is trimmed only so a padded value cannot split
      # one record into two refs, and the trim is what the blank check runs
      # against. Nothing else is normalized: case folding could collapse two
      # distinct identifiers onto one ref, which is the opposite of the property
      # these refs exist to provide.
      #
      # @param identifier [String, nil]
      # @return [String] trimmed identifier, or '' when unusable.
      def pre_image(identifier)
        raw = identifier.to_s
        raw = raw.dup.force_encoding(Encoding::UTF_8) unless raw.encoding == Encoding::UTF_8
        return '' unless raw.valid_encoding?

        raw.strip
      end

      # Keyed, purpose-separated, truncated digest. NEVER raises.
      #
      # The pre-image is produced by the block so that the encoding guard runs
      # inside this method's rescue rather than at the call site.
      #
      # @param info [String] versioned purpose prefix (ACTOR_INFO or
      #   ORGANIZATION_INFO). This element is the only thing separating the two
      #   ref namespaces, so it must never be passed a caller-supplied value.
      # @param secret [String, nil] the caller's keying resolution.
      # @yieldreturn [String, nil] the pre-image.
      # @return [String, nil]
      def digest_ref(info, secret)
        return nil if secret.to_s.empty?

        value = yield.to_s
        return nil if value.empty?

        message = [info, value].join(SEPARATOR)
        OpenSSL::HMAC.hexdigest('SHA256', secret, message)[0, REF_LENGTH]
      rescue StandardError => ex
        # Class only: the message could carry the pre-image or the key.
        OT.ld "[diagnostics-ref] derivation failed: #{ex.class}" if defined?(OT)
        nil
      end
    end
  end
end
