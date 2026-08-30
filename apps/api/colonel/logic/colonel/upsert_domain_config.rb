# apps/api/colonel/logic/colonel/upsert_domain_config.rb
#
# frozen_string_literal: true

require_relative '../base'
require_relative 'domain_resolver'
require 'onetime/operations/domains/upsert_domain_config'

module ColonelAPI
  module Logic
    module Colonel
      # Upsert one editable per-domain config record (Colonel).
      #
      # @api PUT /api/colonel/domains/:extid/configs/:kind — create-if-missing
      #   (model defaults + provided fields) else partial update (only fields
      #   present in params are applied). Backs the admin "Domain
      #   configuration" edit modal (v0.26.2 outage class).
      #
      # Editable kinds only (signin/signup/homepage/api/incoming). sso/mailer
      # are 422: their create paths enforce credential/from_address validation
      # and they remain managed in workspace domain settings. Unknown kinds
      # are 404. Writable fields and their coercions live in
      # {Onetime::CustomDomain::ConfigRegistry} — unknown fields are silently
      # ignored, invalid enum/boolean values are 422 form errors.
      #
      # Thin adapter over {Onetime::Operations::Domains::UpsertDomainConfig} —
      # the audited single implementation (CONTRACT 4: exactly one
      # ColonelAuditEvent per successful mutation, field NAMES only in detail).
      #
      # Security invariant (epic #20): BOTH the router (role=colonel) AND this
      # logic (verify_one_of_roles!(colonel: true)) enforce the colonel role.
      class UpsertDomainConfig < ColonelAPI::Logic::Base
        include DomainResolver

        SCHEMAS = { response: 'colonelDomainConfigUpsert' }.freeze

        attr_reader :extid, :kind, :custom_domain, :attrs, :result

        def process_params
          @extid = sanitize_identifier(params['extid'])
          @kind  = sanitize_identifier(params['kind']).to_s.downcase
        end

        def raise_concerns
          verify_one_of_roles!(colonel: true)

          raise_form_error('Domain ID is required', field: :extid) if extid.to_s.empty?

          @custom_domain = resolve_custom_domain(extid)
          raise_not_found('Domain not found') unless custom_domain

          raise_not_found('Unknown config kind') unless registry.kind?(kind)

          unless registry.editable?(kind)
            raise_form_error(
              "#{kind} config is not editable via the colonel API; managed in workspace domain settings",
              field: :kind,
            )
          end

          @attrs = validated_attrs
        end

        def process
          @result = Onetime::Operations::Domains::UpsertDomainConfig.new(
            domain: custom_domain,
            kind: kind,
            attrs: attrs,
            actor: cust.extid, # acting colonel's PUBLIC id (never an objid)
          ).call

          OT.info "[UpsertDomainConfig] #{custom_domain.display_domain} kind=#{kind} " \
                  "outcome=#{result.status} changed=#{result.changed.join(',')}"

          success_data
        rescue OT::FormError, Onetime::RecordNotFound
          raise
        rescue Onetime::Problem => ex
          # Model-level validation surfaced from the op (e.g.
          # allowed_signup_domains PublicSuffix rejection) → 422 form error.
          raise_form_error(ex.message)
        end

        def success_data
          {
            record: domain_record,
            details: {
              kind: kind,
              outcome: result.status.to_s,
              config: registry.serialize(kind, result.config),
            },
          }
        end

        private

        def registry
          Onetime::CustomDomain::ConfigRegistry
        end

        def domain_record
          {
            domain_id: custom_domain.domainid,
            extid: custom_domain.extid,
            display_domain: custom_domain.display_domain,
          }
        end

        # Coerce every PROVIDED writable field for the kind; unknown fields are
        # silently ignored (only spec'd fields are inspected). Invalid values
        # are 422 form errors tagged with the offending field.
        def validated_attrs
          registry.field_specs(kind).each_with_object({}) do |(field, _spec), acc|
            next unless params.key?(field)

            begin
              acc[field] = registry.coerce_field!(kind, field, params[field])
            rescue Onetime::Problem => ex
              raise_form_error(ex.message, field: field.to_sym)
            end
          end
        end
      end
    end
  end
end
