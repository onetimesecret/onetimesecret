

module Onetime
  class App
    module Views
      module Helpers
        attr_accessor :subdomain
        def add_shrimp
          '<input type="hidden" name="shrimp" value="%s" />' % [sess.add_shrimp]
        end
        def private_uri m
          '/private/%s' % m.key
        end
        def secret_uri s
          '/secret/%s' % s.key
        end
        def baseotsuri
          scheme = Onetime.conf[:site][:ssl] ? 'https://' : 'http://'
          [scheme, Onetime.conf[:site][:host]].join
        end
        def jsvar name, value
          value = case value.class.to_s
          when 'String', 'Gibbler::Digest', 'Symbol'
            "'#{Rack::Utils.escape_html(value)}'"
          when 'Array'
            value.inspect
          when 'Hash'
            "jQuery.parseJSON('#{value.to_json}')"
          when 'NilClass'
            'null'
          else
            value
          end
          { :name => name, :value => value }
        end
        def server_port
          (defined?(req) ? req.env['SERVER_PORT'] : 443).to_i
        end
        def current_subdomain
          defined?(req) ? req.env['ots.subdomain'] : subdomain
        end
        def baseuri
          scheme = Onetime.conf[:site][:ssl] ? 'https://' : 'http://'
          if current_subdomain
            fulldomain = [current_subdomain['cname'], Onetime.conf[:site][:domain]].join('.')
          else
            fulldomain = Onetime.conf[:site][:host]
          end
          uri = [scheme, fulldomain].join
          #uri << (':%d' % server_port) if ![443, 80].member?(server_port.to_i)
          uri
        end
        def gravatar(email)
          return '/img/stella.png' if email.nil? || email.empty?
          suffix = Digest::MD5.hexdigest email.to_s.downcase
          prefix = secure_request? ? 'https://secure' : 'http://www'
          [prefix, '.gravatar.com/avatar/', suffix].join
        end
        def secure_request?
          !local? || secure?
        end
        # TODO: secure ad local are already in Otto
        def secure?
          # X-Scheme is set by nginx
          # X-FORWARDED-PROTO is set by elastic load balancer
          (req.env['HTTP_X_FORWARDED_PROTO'] == 'https' || req.env['HTTP_X_SCHEME'] == "https")
        end

        def local?
          (LOCAL_HOSTS.member?(req.env['SERVER_NAME']) && (req.client_ipaddress == '127.0.0.1'))
        end
        protected

        def epochdate(e)
          t = Time.at e.to_i
          dformat t.utc
        end
        def epochtime(e)
          t = Time.at e.to_i
          tformat t.utc
        end
        def epochformat(e)
          t = Time.at e.to_i
          dtformat t.utc
        end
        def epochformat2(e)
          t = Time.at e.to_i
          dtformat2 t.utc
        end
        def epochdom(e)
          t = Time.at e.to_i
          t.utc.strftime('%b %d, %Y')
        end
        def epochtod(e)
          t = Time.at e.to_i
          t.utc.strftime('%I:%M%p').gsub(/^0/, '').downcase
        end
        def epochcsvformat(e)
          t = Time.at e.to_i
          t.utc.strftime("%Y/%m/%d %H:%M:%S")
        end
        def dtformat(t)
          t = DateTime.parse t unless t.kind_of?(Time)
          t.strftime("%Y-%m-%d@%H:%M:%S UTC")
        end
        def dtformat2(t)
          t = DateTime.parse t unless t.kind_of?(Time)
          t.strftime("%Y-%m-%d@%H:%M UTC")
        end
        def dformat(t)
          t = DateTime.parse t unless t.kind_of?(Time)
          t.strftime("%Y-%m-%d")
        end
        def tformat(t)
          t = DateTime.parse t unless t.kind_of?(Time)
          t.strftime("%H:%M:%S")
        end
        def natural_time(e)
          return if e.nil?
          val = Time.now.utc.to_i - e.to_i
          #puts val
          if val < 10
            result = 'a moment ago'
          elsif val < 40
            result = 'about ' + (val * 1.5).to_i.to_s.slice(0,1) + '0 seconds ago'
          elsif val < 60
            result = 'about a minute ago'
          elsif val < 60 * 1.3
            result = "1 minute ago"
          elsif val < 60 * 2
            result = "2 minutes ago"
          elsif val < 60 * 50
            result = "#{(val / 60).to_i} minutes ago"
          elsif val < 3600 * 1.4
            result = 'about 1 hour ago'
          elsif val < 3600 * (24 / 1.02)
            result = "about #{(val / 60 / 60 * 1.02).to_i} hours ago"
          elsif val < 3600 * 24 * 1.6
            result = Time.at(e.to_i).strftime("yesterday").downcase
          elsif val < 3600 * 24 * 7
            result = Time.at(e.to_i).strftime("on %A").downcase
          #elsif val < 3600 * 24 * 11
          #  result = Time.at(e.to_i).strftime("last %A").downcase
          else
            weeks = (val / 3600.0/24.0/7).to_i
            result = Time.at(e.to_i).strftime("#{weeks} #{'week'.plural(weeks)} ago").downcase
          end
          result
        end
      end

    end
  end
end
