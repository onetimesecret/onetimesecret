# lib/onetime/refinements/stripe_refinements.rb

require 'stripe' # ensures Stripe namespace is loaded

module Onetime::StripeRefinements
  refine Stripe::Subscription do
    extend Familia::Features::SafeDump::ModelClassMethods

    # Safe fields for Stripe Subscription object
    set_safe_dump_fields [
      { identifier: ->(obj) { obj.id } },
      :id,
      :status,
      :current_period_start,
      :current_period_end,
      :cancel_at_period_end,
      :canceled_at,
      :created,
      :days_until_due,
      :trial_start,
      :trial_end,
      :livemode,

      { items: lambda { |sub|
        sub.items.data.map do |item|
          {
            price_id: item.price.id,
            price_nickname: item.price.nickname,
            quantity: item.quantity,
          }
        end
      } },

      { current_period_remaining: lambda { |sub|
        (Time.at(sub.current_period_end) - Familia.now).to_i
      } },

      { on_trial: lambda { |sub|
        sub.trial_end && Familia.now < Time.at(sub.trial_end)
      } },

      { plan: lambda { |sub|
        if sub.plan
  {
    id: sub.plan.id,
    nickname: sub.plan.nickname,
    amount: sub.plan.amount,
    interval: sub.plan.interval,
    interval_count: sub.plan.interval_count,
  }
end
      } },
    ]
  end

  refine Stripe::Customer do
    @safe_dump_fields    = []
    @safe_dump_field_map = {}
    extend Familia::Features::SafeDump::ModelClassMethods

    def safe_dump
      self.class.safe_dump_field_map.transform_values do |callable|
        transformed_value = callable.call(self)

        # If the value is a ancestor of SafeDump we can call safe_dump
        # on it, otherwise we'll just return the value as-is.
        if transformed_value.is_a?(SafeDump)
          transformed_value.safe_dump
        else
          transformed_value
        end
      end
    end

    # Safe fields for Stripe Customer object
    @safe_dump_fields = [
      { identifier: ->(obj) { obj.id } },
      :id,
      :email,
      :name,
      :phone,
      :created,
      :livemode,
      :tax_exempt,
      :preferred_locales,
      :currency,

      { address: lambda { |cust|
        if cust.address
  {
    city: cust.address.city,
    country: cust.address.country,
    line1: cust.address.line1,
    line2: cust.address.line2,
    postal_code: cust.address.postal_code,
    state: cust.address.state,
  }
end
      } },

      { has_payment_method: lambda { |cust|
        !cust.default_source.nil?
      } },

      { metadata: lambda { |cust|
        # Only include safe metadata fields
        safe_metadata_identifiers = [:public_note, :preferred_language]
        cust.metadata_list.select { |k, _| safe_metadata_identifiers.include?(k.to_sym) }
      } },
    ]
  end
end
