# lib/onetime/rsfc/view.rb

require_relative 'context'
require_relative 'parser'
require_relative 'rhales'
require_relative 'hydrator'
require_relative '../refinements/require_refinements'

using Onetime::Ruequire

module Onetime
  module RSFC
    # Base view class for RSFC template rendering
    #
    # Replaces Mustache-based views with RSFC template processing.
    # Maintains compatibility with existing helper modules while providing
    # new RSFC-specific functionality.
    class View
      class RenderError < StandardError; end
      class TemplateNotFoundError < RenderError; end

      attr_reader :req, :sess, :cust, :locale, :rsfc_context, :business_data

      def initialize(req, sess = nil, cust = nil, locale_override = nil, business_data: {})
        @req           = req
        @sess          = sess
        @cust          = cust
        @locale        = locale_override
        @business_data = business_data

        # Create RSFC context
        @rsfc_context = Context.for_view(req, sess, cust, locale, **business_data)
      end

      # Render RSFC template
      def render(template_name = nil)
        template_name ||= self.class.default_template_name

        # Load template parser
        parser = load_template(template_name)

        # Render template content
        template_html = render_template_section(parser)

        # Generate data hydration HTML
        hydration_html = generate_hydration(parser)

        # Combine template and hydration
        inject_hydration_into_template(template_html, hydration_html)
      rescue StandardError => ex
        raise RenderError, "Failed to render template '#{template_name}': #{ex.message}"
      end

      # Render only the template section (without data hydration)
      def render_template_only(template_name = nil)
        template_name ||= self.class.default_template_name
        parser          = load_template(template_name)
        render_template_section(parser)
      end

      # Generate only the data hydration HTML
      def render_hydration_only(template_name = nil)
        template_name ||= self.class.default_template_name
        parser          = load_template(template_name)
        generate_hydration(parser)
      end

      # Get processed data as hash (for API endpoints or testing)
      def data_hash(template_name = nil)
        template_name ||= self.class.default_template_name
        parser          = load_template(template_name)
        Hydrator.generate_data_hash(parser, @rsfc_context)
      end

      private

      # Load and parse template
      def load_template(template_name)
        template_path = resolve_template_path(template_name)

        unless File.exist?(template_path)
          raise TemplateNotFoundError, "Template not found: #{template_path}"
        end

        # Use refinement to load .rue file
        require template_path
      end

      # Resolve template path
      def resolve_template_path(template_name)
        # First try templates/web directory
        web_path = File.join(templates_root, 'web', "#{template_name}.rue")
        return web_path if File.exist?(web_path)

        # Then try templates directory
        templates_path = File.join(templates_root, "#{template_name}.rue")
        return templates_path if File.exist?(templates_path)

        # Return first path for error message
        web_path
      end

      # Get templates root directory
      def templates_root
        boot_root = if defined?(OT) && OT.respond_to?(:boot_root)
                      OT.boot_root
                    else
                      File.expand_path('../../..', __dir__)
                    end
        File.join(boot_root, 'templates')
      end

      # Render template section with Rhales
      def render_template_section(parser)
        template_content = parser.section('template')
        return '' unless template_content

        # Create partial resolver
        partial_resolver = create_partial_resolver

        # Render with Rhales
        Rhales.render(template_content, @rsfc_context, partial_resolver: partial_resolver)
      end

      # Create partial resolver for {{> partial}} inclusions
      def create_partial_resolver
        templates_dir = File.join(templates_root, 'web')

        proc do |partial_name|
          partial_path = File.join(templates_dir, "#{partial_name}.rue")

          if File.exist?(partial_path)
            # Parse partial and return template section
            partial_parser = require(partial_path)
            partial_parser.section('template')
          else
            nil
          end
        end
      end

      # Generate data hydration HTML
      def generate_hydration(parser)
        Hydrator.generate(parser, @rsfc_context)
      end

      # Inject hydration HTML into template
      def inject_hydration_into_template(template_html, hydration_html)
        # Try to inject before closing </body> tag
        if template_html.include?('</body>')
          template_html.sub('</body>', "#{hydration_html}\n</body>")
        # Otherwise append to end
        else
          "#{template_html}\n#{hydration_html}"
        end
      end

      class << self
        # Get default template name based on class name
        def default_template_name
          # Convert ClassName to class_name
          name.split('::').last
            .gsub(/([A-Z])/, '_\1')
            .downcase
            .sub(/^_/, '')
            .sub(/_view$/, '')
        end

        # Render template with business data
        def render_with_data(req, sess, cust, locale, template_name: nil, **business_data)
          view = new(req, sess, cust, locale, business_data: business_data)
          view.render(template_name)
        end

        # Create view instance with business data
        def with_data(req, sess, cust, locale, **business_data)
          new(req, sess, cust, locale, business_data: business_data)
        end
      end
    end
  end
end
