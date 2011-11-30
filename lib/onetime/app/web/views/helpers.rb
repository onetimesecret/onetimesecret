

module Onetime
  class App
    module Views
      module Helpers
        def add_shrimp
          '<input type="hidden" name="shrimp" value="%s" />' % [sess.add_shrimp]
        end
        def private_uri m 
          '/private/%s' % m.key
        end
        def secret_uri s 
          '/secret/%s' % s.key
        end
        def baseuri
          scheme = Onetime.conf[:site][:ssl] ? 'https://' : 'http://'
          [scheme, Onetime.conf[:site][:host]].join
        end
        protected
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