#!/usr/bin/env bash
# scripts/regroup-tryouts-by-prefix.sh
#
# One-off, already applied on top of c72cb44ff8. Kept as the record of the
# move; a second run stops at the preconditions because the sources are gone.
#
# Group tryouts that share a filename prefix into a directory named after it.
#
#   try/unit/models/custom_domain_api_config_try.rb
#     -> try/unit/models/custom_domain/api_config_try.rb
#
# Base files (<prefix>_try.rb) stay where they are, the same way
# lib/onetime/models/organization.rb sits next to lib/onetime/models/organization/.
#
# Steps: git mv, deepen '../' path literals in moved files by one level,
# rewrite old paths in every tracked file (headers, cross-refs, docs), verify.
# Leaves changes uncommitted.
#
# The perl programs read $ENV{...} and $. themselves.
# shellcheck disable=SC2016
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

pairs() {
  grep -vE '^[[:space:]]*(#|$)' <<'TABLE'
# -> try/unit/models/custom_domain/
try/unit/models/custom_domain_api_config_try.rb                                try/unit/models/custom_domain/api_config_try.rb
try/unit/models/custom_domain_auth_default_off_try.rb                          try/unit/models/custom_domain/auth_default_off_try.rb
try/unit/models/custom_domain_auth_killswitch_try.rb                           try/unit/models/custom_domain/auth_killswitch_try.rb
try/unit/models/custom_domain_boolean_fields_try.rb                            try/unit/models/custom_domain/boolean_fields_try.rb
try/unit/models/custom_domain_claim_orphan_branches_try.rb                     try/unit/models/custom_domain/claim_orphan_branches_try.rb
try/unit/models/custom_domain_claim_orphan_try.rb                              try/unit/models/custom_domain/claim_orphan_try.rb
try/unit/models/custom_domain_config_boolean_encoding_try.rb                   try/unit/models/custom_domain/config_boolean_encoding_try.rb
try/unit/models/custom_domain_config_normalize_boolean_encoding_chore_try.rb   try/unit/models/custom_domain/config_normalize_boolean_encoding_chore_try.rb
try/unit/models/custom_domain_create_rollback_try.rb                           try/unit/models/custom_domain/create_rollback_try.rb
try/unit/models/custom_domain_destroy_cascade_try.rb                           try/unit/models/custom_domain/destroy_cascade_try.rb
try/unit/models/custom_domain_duplicate_handling_try.rb                        try/unit/models/custom_domain/duplicate_handling_try.rb
try/unit/models/custom_domain_familia_v2_try.rb                                try/unit/models/custom_domain/familia_v2_try.rb
try/unit/models/custom_domain_homepage_config_race_try.rb                      try/unit/models/custom_domain/homepage_config_race_try.rb
try/unit/models/custom_domain_homepage_config_try.rb                           try/unit/models/custom_domain/homepage_config_try.rb
try/unit/models/custom_domain_icon_safe_dump_try.rb                            try/unit/models/custom_domain/icon_safe_dump_try.rb
try/unit/models/custom_domain_instances_owners_try.rb                          try/unit/models/custom_domain/instances_owners_try.rb
try/unit/models/custom_domain_load_contract_try.rb                             try/unit/models/custom_domain/load_contract_try.rb
try/unit/models/custom_domain_load_error_handling_try.rb                       try/unit/models/custom_domain/load_error_handling_try.rb
try/unit/models/custom_domain_mail_fields_try.rb                               try/unit/models/custom_domain/mail_fields_try.rb
try/unit/models/custom_domain_mailer_config_try.rb                             try/unit/models/custom_domain/mailer_config_try.rb
try/unit/models/custom_domain_migration_minimal_try.rb                         try/unit/models/custom_domain/migration_minimal_try.rb
try/unit/models/custom_domain_migration_setup_try.rb                           try/unit/models/custom_domain/migration_setup_try.rb
try/unit/models/custom_domain_migration_try.rb                                 try/unit/models/custom_domain/migration_try.rb
try/unit/models/custom_domain_navigation_try.rb                                try/unit/models/custom_domain/navigation_try.rb
try/unit/models/custom_domain_owners_destroy_proof_try.rb                      try/unit/models/custom_domain/owners_destroy_proof_try.rb
try/unit/models/custom_domain_rename_index_try.rb                              try/unit/models/custom_domain/rename_index_try.rb
try/unit/models/custom_domain_resolve_domain_id_try.rb                         try/unit/models/custom_domain/resolve_domain_id_try.rb
try/unit/models/custom_domain_signin_config_class_methods_try.rb               try/unit/models/custom_domain/signin_config_class_methods_try.rb
try/unit/models/custom_domain_signin_config_non_nullable_try.rb                try/unit/models/custom_domain/signin_config_non_nullable_try.rb
try/unit/models/custom_domain_signup_config_non_nullable_try.rb                try/unit/models/custom_domain/signup_config_non_nullable_try.rb
try/unit/models/custom_domain_signup_config_try.rb                             try/unit/models/custom_domain/signup_config_try.rb
try/unit/models/custom_domain_sso_config_saml_try.rb                           try/unit/models/custom_domain/sso_config_saml_try.rb
try/unit/models/custom_domain_sso_config_try.rb                                try/unit/models/custom_domain/sso_config_try.rb

# -> try/unit/models/organization_membership/
try/unit/models/organization_membership_accept_participation_try.rb            try/unit/models/organization_membership/accept_participation_try.rb
try/unit/models/organization_membership_cleanup_try.rb                         try/unit/models/organization_membership/cleanup_try.rb
try/unit/models/organization_membership_domain_scope_try.rb                    try/unit/models/organization_membership/domain_scope_try.rb
try/unit/models/organization_membership_ensure_try.rb                          try/unit/models/organization_membership/ensure_try.rb
try/unit/models/organization_membership_entitlements_try.rb                    try/unit/models/organization_membership/entitlements_try.rb
try/unit/models/organization_membership_index_lifecycle_try.rb                 try/unit/models/organization_membership/index_lifecycle_try.rb
try/unit/models/organization_membership_provisioning_source_try.rb             try/unit/models/organization_membership/provisioning_source_try.rb
try/unit/models/organization_membership_race_safety_try.rb                     try/unit/models/organization_membership/race_safety_try.rb
try/unit/models/organization_membership_removal_try.rb                         try/unit/models/organization_membership/removal_try.rb
try/unit/models/organization_membership_through_try.rb                         try/unit/models/organization_membership/through_try.rb

# -> try/unit/models/organization/
try/unit/models/organization_billing_try.rb                                    try/unit/models/organization/billing_try.rb
try/unit/models/organization_entitlements_try.rb                               try/unit/models/organization/entitlements_try.rb
try/unit/models/organization_familia_v2_try.rb                                 try/unit/models/organization/familia_v2_try.rb
try/unit/models/organization_federation_try.rb                                 try/unit/models/organization/federation_try.rb
try/unit/models/organization_invitation_try.rb                                 try/unit/models/organization/invitation_try.rb
try/unit/models/organization_member_debug_try.rb                               try/unit/models/organization/member_debug_try.rb
try/unit/models/organization_member_isolated_try.rb                            try/unit/models/organization/member_isolated_try.rb
try/unit/models/organization_pending_invitations_cleanup_try.rb                try/unit/models/organization/pending_invitations_cleanup_try.rb
try/unit/models/organization_race_condition_try.rb                             try/unit/models/organization/race_condition_try.rb

# -> try/unit/models/customer/
try/unit/models/customer_apitoken_try.rb                                       try/unit/models/customer/apitoken_try.rb
try/unit/models/customer_colonel_auto_assign_try.rb                            try/unit/models/customer/colonel_auto_assign_try.rb
try/unit/models/customer_default_org_try.rb                                    try/unit/models/customer/default_org_try.rb
try/unit/models/customer_email_normalization_try.rb                            try/unit/models/customer/email_normalization_try.rb
try/unit/models/customer_field_serialization_try.rb                            try/unit/models/customer/field_serialization_try.rb
try/unit/models/customer_find_by_extid_try.rb                                  try/unit/models/customer/find_by_extid_try.rb
try/unit/models/customer_lookup_try.rb                                         try/unit/models/customer/lookup_try.rb
try/unit/models/customer_pending_plan_intent_try.rb                            try/unit/models/customer/pending_plan_intent_try.rb

# -> try/unit/models/receipt/
try/unit/models/receipt_expiration_tracking_try.rb                             try/unit/models/receipt/expiration_tracking_try.rb
try/unit/models/receipt_participations_try.rb                                  try/unit/models/receipt/participations_try.rb
try/unit/models/receipt_phantom_domain_try.rb                                  try/unit/models/receipt/phantom_domain_try.rb
try/unit/models/receipt_phantom_entries_try.rb                                 try/unit/models/receipt/phantom_entries_try.rb
try/unit/models/receipt_safe_dump_try.rb                                       try/unit/models/receipt/safe_dump_try.rb
try/unit/models/receipt_state_terminology_try.rb                               try/unit/models/receipt/state_terminology_try.rb
try/unit/models/receipt_ttl_resurrection_race_try.rb                           try/unit/models/receipt/ttl_resurrection_race_try.rb

# -> try/unit/models/secret/
try/unit/models/secret_active_counter_try.rb                                   try/unit/models/secret/active_counter_try.rb
try/unit/models/secret_double_reveal_race_try.rb                               try/unit/models/secret/double_reveal_race_try.rb
try/unit/models/secret_numeric_field_types_try.rb                              try/unit/models/secret/numeric_field_types_try.rb
try/unit/models/secret_reveal_rollback_try.rb                                  try/unit/models/secret/reveal_rollback_try.rb
try/unit/models/secret_state_terminology_try.rb                                try/unit/models/secret/state_terminology_try.rb

# -> try/unit/mail/templates/
try/unit/mail/templates_base_try.rb                                            try/unit/mail/templates/base_try.rb
try/unit/mail/templates_brand_color_rendered_try.rb                            try/unit/mail/templates/brand_color_rendered_try.rb
try/unit/mail/templates_brand_color_try.rb                                     try/unit/mail/templates/brand_color_try.rb
try/unit/mail/templates_email_change_confirmation_try.rb                       try/unit/mail/templates/email_change_confirmation_try.rb
try/unit/mail/templates_email_change_requested_try.rb                          try/unit/mail/templates/email_change_requested_try.rb
try/unit/mail/templates_email_changed_try.rb                                   try/unit/mail/templates/email_changed_try.rb
try/unit/mail/templates_expiration_warning_try.rb                              try/unit/mail/templates/expiration_warning_try.rb
try/unit/mail/templates_incoming_secret_try.rb                                 try/unit/mail/templates/incoming_secret_try.rb
try/unit/mail/templates_member_removed_try.rb                                  try/unit/mail/templates/member_removed_try.rb
try/unit/mail/templates_mfa_disabled_try.rb                                    try/unit/mail/templates/mfa_disabled_try.rb
try/unit/mail/templates_mfa_enabled_try.rb                                     try/unit/mail/templates/mfa_enabled_try.rb
try/unit/mail/templates_new_login_alert_try.rb                                 try/unit/mail/templates/new_login_alert_try.rb
try/unit/mail/templates_organization_deleted_try.rb                            try/unit/mail/templates/organization_deleted_try.rb
try/unit/mail/templates_password_changed_try.rb                                try/unit/mail/templates/password_changed_try.rb
try/unit/mail/templates_password_request_try.rb                                try/unit/mail/templates/password_request_try.rb
try/unit/mail/templates_role_changed_try.rb                                    try/unit/mail/templates/role_changed_try.rb
try/unit/mail/templates_secret_link_try.rb                                     try/unit/mail/templates/secret_link_try.rb
try/unit/mail/templates_secret_revealed_try.rb                                 try/unit/mail/templates/secret_revealed_try.rb
try/unit/mail/templates_show_logo_try.rb                                       try/unit/mail/templates/show_logo_try.rb
try/unit/mail/templates_subscription_changed_try.rb                            try/unit/mail/templates/subscription_changed_try.rb
try/unit/mail/templates_text_support_email_try.rb                              try/unit/mail/templates/text_support_email_try.rb
try/unit/mail/templates_trial_expiring_try.rb                                  try/unit/mail/templates/trial_expiring_try.rb
try/unit/mail/templates_welcome_try.rb                                         try/unit/mail/templates/welcome_try.rb

# -> try/unit/operations/verify_domain/
try/unit/operations/verify_domain_approximated_native_try.rb                   try/unit/operations/verify_domain/approximated_native_try.rb
try/unit/operations/verify_domain_caddy_on_demand_try.rb                       try/unit/operations/verify_domain/caddy_on_demand_try.rb
try/unit/operations/verify_domain_confirmation_window_try.rb                   try/unit/operations/verify_domain/confirmation_window_try.rb

# -> directories that already held sibling tryouts
try/unit/cli/billing_diagnose_try.rb                                           try/unit/cli/billing/diagnose_try.rb
try/unit/cli/customers_dates_command_try.rb                                    try/unit/cli/customers/dates_command_try.rb
try/unit/cli/customers_purge_command_try.rb                                    try/unit/cli/customers/purge_command_try.rb
try/unit/operations/email_config_summary_try.rb                                try/unit/operations/email/config_summary_try.rb
TABLE
}

# --- 0. Preconditions --------------------------------------------------------
pairs | while read -r old new; do
  [ -f "$old" ] || { echo "missing source: $old" >&2; exit 1; }
  [ ! -e "$new" ] || { echo "target exists: $new" >&2; exit 1; }
done

# --- 1. Move -----------------------------------------------------------------
pairs | while read -r old new; do
  mkdir -p "$(dirname "$new")"
  git mv "$old" "$new"
done

# --- 2. Deepen relative paths by one level -----------------------------------
# Every '../ literal in these files is a require_relative or a
# File.expand_path('../..', __dir__) argument, so a blanket rewrite is safe.
# The one File.join(__dir__, '..', ...) is billing_diagnose_try.rb's
# ONETIME_HOME fallback.
pairs | while read -r _ new; do
  perl -pi -e "s{'\.\./}{'../../}g; s{File\.join\(__dir__, '\.\.'}{File.join(__dir__, '..', '..'}g" "$new"
done

# --- 3. Rewrite references to the old paths ----------------------------------
# Covers each file's own path header, "Run: try ..." comments, and
# cross-references in lib/, apps/, spec/, src/, docs/, and other tryouts.
pairs | while read -r old new; do
  { git grep --no-color -lzF -e "$old" || true; } | OLD="$old" NEW="$new" xargs -0 -r \
    perl -pi -e 's/\Q$ENV{OLD}\E/$ENV{NEW}/g'
done

# Moved files that name a sibling by its bare old filename. The lookbehind
# skips path-qualified names, which step 3 already handled or which belong to
# a namesake elsewhere.
pairs | while read -r old new; do
  dir=$(dirname "$new")
  pairs | awk -v d="$dir" '{ n = $2; sub(/\/[^\/]*$/, "", n) } n == d { print $2 }' |
    OLD=$(basename "$old") NEW=$(basename "$new") xargs \
      perl -pi -e 's{(?<![\w/])\Q$ENV{OLD}\E}{$ENV{NEW}}g'
done

# The one reference outside the moved files by bare filename.
perl -pi -e 's{`organization_entitlements_try\.rb`}{`organization/entitlements_try.rb`}' \
  docs/specs/entitlements-and-capabilities/issue-3491-plan-entitlements-vs-role-capabilities.md

# Line 4 of the path header should be blank; this file had '#', which fails
# the header check in step 4.
perl -pi -e 's/^#$// if $. == 4' try/unit/models/custom_domain/owners_destroy_proof_try.rb

# --- 4. Verify ---------------------------------------------------------------
# No old path survives anywhere in the tree.
if pairs | awk '{print $1}' | git grep --no-color -nF -f -; then
  echo "stale references remain (above)" >&2
  exit 1
fi

# No moved file names a sibling by its old bare filename.
if pairs | awk '{print $2}' |
  xargs grep -nF -f <(pairs | awk '{ n = $1; sub(/.*\//, "", n); print n }'); then
  echo "stale sibling references remain (above)" >&2
  exit 1
fi

# Every relative require_relative / expand_path in the moved files resolves,
# and the File.join(__dir__, '..', ...) fallback still lands on the repo root.
pairs | awk '{print $2}' | ruby -e '
  bad = 0
  STDIN.each_line(chomp: true) do |f|
    File.foreach(f).with_index(1) do |line, n|
      line.scan(/(?:require_relative\s*\(?|File\.expand_path\()\s*\x27(\.\.\/[^\x27]+)\x27/) do |(rel)|
        target = File.expand_path(rel, File.dirname(f))
        next if File.exist?(target) || File.exist?("#{target}.rb")
        warn "#{f}:#{n}: unresolved #{rel}"
        bad += 1
      end
      line.scan(/File\.join\(__dir__((?:,\s*\x27\.\.\x27)+)\)/) do |(dots)|
        target = File.expand_path(File.join(File.dirname(f), *[".."] * dots.count(",")))
        next if target == Dir.pwd
        warn "#{f}:#{n}: #{target} is not the repo root"
        bad += 1
      end
    end
  end
  exit(bad.zero? ? 0 : 1)
'

# Path headers match the new locations.
pairs | awk '{print $2}' | xargs ruby scripts/update-file-headers.rb

git diff -M --stat HEAD | tail -n 1
echo "next: tests/lanes/run unit"
