# apps/api/colonel/logic/colonel/export_colonel_audit_events.rb
#
# frozen_string_literal: true

require_relative '../base'
require 'onetime/colonel_audit_reader'

module ColonelAPI
  module Logic
    module Colonel
      # Export Audit Events
      #
      # @api Serialises the operator audit trail as a DOWNLOAD
      #   (GET /api/colonel/audit/export). Same two trails, same merge, same
      #   newest-first order and the SAME FIELD ALLOWLIST as
      #   {ListColonelAuditEvents} — both go through
      #   {Onetime::ColonelAuditReader}, which is the point of that module.
      #   Supports `format=csv` (default) and `format=ndjson`, plus the same
      #   `actor` / `verb` filters and a `limit`. Requires colonel role.
      #
      # READ-ONLY: exporting the log must never write an audit event
      # (CONTRACT 4), exactly as listing it must not.
      #
      # ## Why this is not a normal `response=json` colonel route
      #
      # Otto's Logic-class handler never hands the Logic instance the Rack
      # response, and its JSON response handler always `JSON.generate`s the
      # body — so a CSV or NDJSON download cannot come out of the usual
      # `response=json` route shape at all. {.render} is the `Klass.method`
      # route form, which Otto documents as the handler for endpoints needing
      # request-level control (precedent in this repo:
      # `GET /ask Internal::ACME::AskHandler.call`). It is a thin adapter: it
      # runs the standard Logic lifecycle and writes the bytes this class
      # already computed.
      #
      # ## No SCHEMAS constant, on purpose
      #
      # The other colonel logic classes declare `SCHEMAS = { response: ... }`
      # to bind a Zod shape for the wire contract. This endpoint's body is
      # text/csv or application/x-ndjson — not a JSON envelope — so there is no
      # JSON response for a Zod schema to describe, and declaring one would
      # point the schema-scanner at a shape nothing validates. Same reasoning
      # as {Onetime::ColonelAuditEvent}'s own no-SCHEMA note. The CONTENT is
      # still contract-bound: {Onetime::ColonelAuditReader::FIELDS} is the
      # allowlist the JSON list endpoint emits, and
      # src/schemas/api/internal/responses/colonel-audit.ts is where that shape
      # is typed for the frontend.
      class ExportColonelAuditEvents < ColonelAPI::Logic::Base
        Reader = Onetime::ColonelAuditReader

        # Same ceiling the list endpoint reads under: the whole store. Both
        # trails are trimmed on every write, so an export is bounded by
        # construction, never by traffic.
        MAX_LIMIT = Reader::MAX_COMBINED

        attr_reader :export_format,
          :limit,
          :actor_filter,
          :verb_filter,
          :events,
          :body,
          :content_type,
          :filename

        def process_params
          @export_format = Reader.normalize_format(params['format'])
          if @export_format.nil?
            raise_form_error(
              "Unsupported export format. Use one of: #{Reader::FORMATS.join(', ')}",
              field: :format,
            )
          end

          # An omitted or out-of-range limit means "everything retained", which
          # is what an export is usually for. Clamped to MAX_LIMIT so a huge
          # value cannot ask for more than the store holds.
          @limit        = (params['limit'] || MAX_LIMIT).to_i
          @limit        = MAX_LIMIT if @limit <= 0 || @limit > MAX_LIMIT

          @actor_filter = sanitize_plain_text(params['actor'], max_length: 255) if params['actor']
          @verb_filter  = sanitize_plain_text(params['verb'], max_length: 100) if params['verb']
        end

        def raise_concerns
          verify_one_of_roles!(colonel: true)
        end

        # @return [String] the serialised body (also available as {#body}).
        def process
          @events       = Reader.recent(limit: limit, actor: actor_filter, verb: verb_filter)
          @body         = Reader.serialize(events, format: export_format)
          @content_type = Reader.content_type(export_format)
          @filename     = Reader.filename(export_format)

          @body
        end

        # HTTP adapter for the `Klass.method` route form — see the class docs
        # for why this endpoint cannot use the Logic-class handler.
        #
        # Does no work of its own: lifecycle, then headers, then bytes. Role is
        # enforced twice over, as everywhere in this app — `role=colonel` at the
        # Otto routing layer and `verify_one_of_roles!` in #raise_concerns.
        #
        # Errors propagate: Otto's registered handlers map Onetime::FormError to
        # 422 and Onetime::Forbidden to 403, so a bad `format` or a non-colonel
        # caller gets the same JSON error shape as every other colonel route.
        #
        # @param req [Rack::Request]
        # @param res [Rack::Response]
        def self.render(req, res)
          logic = new(
            req.env['otto.strategy_result'],
            req.params,
            req.env['otto.locale'] || 'en',
          )
          logic.raise_concerns
          logic.process

          res['content-type']        = logic.content_type
          res['content-disposition'] = %(attachment; filename="#{logic.filename}")
          # An audit export is a point-in-time snapshot of a mutable trail and
          # is operator-only; never let a proxy or browser keep a copy.
          res['cache-control']       = 'no-store'
          res.write(logic.body)
        end
      end
    end
  end
end
