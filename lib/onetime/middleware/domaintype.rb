module Onetime
  class DomainType
    def initialize(app)
      @app = app
    end

    def call(env)
      # Use the host detected by DetectHost middleware
      host = env['rack.detected_host']

      unless host
        # Fallback in case DetectHost hasn't run
        OT.ld "Warning: DetectHost middleware should run before DomainType"
        req = Rack::Request.new(env)
        host = req.host.to_s.downcase
      end

      # Set default domain type
      env['ots.domaintype'] = :primary
      env['ots.domain'] = host

      if OT.conf[:site][:domains][:enabled]
        default_domain = OT.conf[:site][:domains][:default]

        if default_domain && !default_domain.empty?
          env['ots.domaintype'] = :default if host == default_domain
        end

        # Handle cluster configuration if present
        if cluster_config = OT.conf[:site][:domains][:cluster]
          case cluster_config[:type]
          when 'approximated'
            if host != cluster_config[:cluster_host]
              env['ots.domaintype'] = :custom
              env['ots.custom_domain'] = host
            end
          end
        end

        # Handle regional routing if enabled
        if OT.conf[:site][:regions][:enabled]
          OT.conf[:site][:regions][:jurisdictions].each do |jurisdiction|
            next unless host == jurisdiction[:domain]
            env['ots.domaintype'] = :regional
            env['ots.region'] = jurisdiction[:identifier]
            break
          end
        end
      end

      @app.call(env)
    end
  end
end
