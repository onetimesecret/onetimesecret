
module Onetime
  class App
    module Views

      module CreateSecretElements
        def default_expiration
          option_count = expiration_options.size
          self[:authenticated] ? (option_count)/2 : option_count-1
        end
        def expiration_options
          if @expiration_options.nil?
            selected = (!sess || !sess.authenticated?) ? 7.days : 7.days
            disabled = (!sess || !sess.authenticated?) ? 7.days : plan.options[:ttl]
            @expiration_options = []
            if self[:authenticated]
              if plan.options[:ttl] > 30.days
                @expiration_options.push *[
                  { :value => 90.days, :name => "3 months"},
                  { :value => 60.days, :name => "2 months"}
                ]
              end
              if plan.options[:ttl] >= 30.days
                @expiration_options << { :value => 30.days, :name => "30 days"}
              end
              if plan.options[:ttl] >= 14.days
                @expiration_options << { :value => 14.days, :name => "14 days"}
              end
            end
            @expiration_options.push *[
              { :value => 7.days, :name => "7 days", :default => true},
              { :value => 3.days, :name => "3 days"},
              { :value => 1.day, :name => "1 day"},
              { :value => 12.hours, :name => "12 hours"},
              { :value => 4.hours, :name => "4 hours"},
              { :value => 1.hour, :name => "1 hour"},
              { :value => 30.minutes, :name => "30 minutes"},
              { :value => 5.minutes, :name => "5 minutes"}
            ]
          end
          @expiration_options
        end
      end


    end
  end
end
