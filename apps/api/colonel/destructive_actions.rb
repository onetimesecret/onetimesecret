# apps/api/colonel/destructive_actions.rb
#
# frozen_string_literal: true

module ColonelAPI
  # Which colonel verbs are destructive, and how hard they are gated (#4326).
  #
  # TIER1 — irreversible / credential-revoking / privilege-granting. Requires
  #   server-side confirmation (#4326), a live elevation window (#4327), the tight
  #   rate-limit bucket (#4329) and the network=admin_if_configured annotation
  #   (#4332).
  # TIER2 — reversible but removes a defence, denies service, or grants
  #   privilege. Confirmation only.
  # TIER3_REVIEWED — mutating verbs deliberately left un-gated. This list is
  #   REQUIRED, not optional: spec/unit/colonel/destructive_actions_spec.rb parses
  #   routes.txt and fails when a mutating handler appears in none of the three
  #   lists, so a new destructive route cannot ship un-triaged.
  #
  # Values are the UNQUALIFIED logic class names under ColonelAPI::Logic::Colonel.
  module DestructiveActions
    TIER1 = %w[
      DeleteSecret ChangeUserEmail SetUserRole PurgeUser
      TransferDomain DeleteDomainConfig RemoveCustomDomain
      TransferOrganizationOwnership SetMembershipRole RemoveMembership
      DeleteOrganization
      DeleteSession RevokeAllCustomerSessions RevokeCustomerSession
      PurgeDlq
    ].freeze

    TIER2 = %w[
      UnverifyUser SuspendUser
      RepairDomain OverrideDomainVerification UpsertDomainConfig
      ManageEntitlementOverride AddMembership ManageMembershipEntitlementOverride
      ReplayDlq ResetRateLimit
      ImpersonateUser
    ].freeze

    # Reviewed 2026-09-01 for epic #4323 and deliberately un-gated. One reason
    # each; re-review when a listed class gains new capability.
    TIER3_REVIEWED = {
      'GetElevationStatus' => 'read-only status of the caller\'s own step-up window',
      'ElevateSession' => 'step-up itself: carries its own throttle and audit events (#4327)',
      'DropElevation' => 'strictly de-escalating: ends the caller\'s own window',
      'SetEntitlementPreview' => 'session-scoped preview, no durable write',
      'UpdateUserPlan' => 'billing state, reversible, own reconciliation',
      'CreateCheckoutLink' => 'additive; produces a link, changes nothing',
      'VerifyUser' => 'restorative arm of the verification pair',
      'UnsuspendUser' => 'restorative arm of the suspension pair',
      'CreateCustomDomain' => 'additive; ownership still requires DNS proof',
      'VerifyCustomDomain' => 'runs the DNS check; does not bypass it',
      'EnsureDomainConfigs' => 'idempotent backfill of missing config rows',
      'CreateOrganizationCheckoutLink' => 'additive; produces a link',
      'InvestigateOrganization' => 'read-shaped diagnostic written as POST',
      'ReconcileOrganization' => 'convergence to authoritative state',
      'UpdateOrganizationPlan' => 'billing state, reversible',
      'SetBanner' => 'cosmetic site notice',
      'ClearBanner' => 'cosmetic site notice',
      'SendTestEmail' => 'sends one message to an operator address',
      'AddEmailSuppression' =>
        'suppresses OUR sending to an address; residual risk: the shipped model has no ' \
        'per-category scope, so a suppressed address also loses OTS-originated ' \
        'account-recovery mail (password reset, verification) until RemoveEmailSuppression clears it',
      'RemoveEmailSuppression' => 'restorative arm of the suppression pair',
      'IngestEmailDeliverabilityEvents' =>
        'suppresses bounced/complained/imported addresses (changes send behavior), but is an ' \
        'operator cron/CLI batch firehose so per-request gating is impractical; ' \
        'reversible via RemoveEmailSuppression',
      'SyncEmailDeliverability' => 'convergence to provider state',
    }.freeze

    ALL = (TIER1 + TIER2).freeze

    extend self

    def tier1?(klass) = TIER1.include?(short_name(klass))
    def tier2?(klass) = TIER2.include?(short_name(klass))
    def gated?(klass) = ALL.include?(short_name(klass))
    def classified?(klass) = gated?(klass) || TIER3_REVIEWED.key?(short_name(klass))

    def short_name(klass)
      (klass.is_a?(Class) ? klass.name : klass.to_s).split('::').last
    end
  end
end
