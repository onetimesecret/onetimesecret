require 'onetime'

module Onetime
  module ZombieDetection
    ##
    # ReEngagementWorkflow - Automated workflows for re-engaging zombie customers
    #
    # This class implements multi-stage re-engagement campaigns based on:
    # - Customer health score
    # - Risk level
    # - Time since last activity
    # - Historical engagement patterns
    #
    # Workflows follow best practices:
    # - Gradual escalation (gentle → urgent)
    # - Value-focused messaging
    # - Clear calls-to-action
    # - Respectful exit paths (easy cancellation)
    #
    class ReEngagementWorkflow
      # Workflow stages and timing
      WORKFLOWS = {
        at_risk: {
          stages: [
            { day: 0, type: 'health_check', template: 'at_risk_check_in' },
            { day: 7, type: 'value_reminder', template: 'feature_highlights' },
            { day: 14, type: 'help_offer', template: 'support_outreach' }
          ],
          description: 'For customers showing early warning signs (health score 50-69)'
        },
        zombie_candidate: {
          stages: [
            { day: 0, type: 'win_back', template: 'win_back_offer' },
            { day: 3, type: 'use_case_education', template: 'use_case_examples' },
            { day: 7, type: 'personal_outreach', template: 'founder_message' },
            { day: 14, type: 'final_reminder', template: 'cancellation_reminder' }
          ],
          description: 'For likely zombies (health score 30-49)'
        },
        critical: {
          stages: [
            { day: 0, type: 'urgent_intervention', template: 'immediate_action_needed' },
            { day: 2, type: 'special_offer', template: 'exclusive_retention_offer' },
            { day: 5, type: 'exit_survey', template: 'cancellation_assistance' }
          ],
          description: 'For confirmed zombies (health score < 30)'
        }
      }.freeze

      ##
      # Email templates for different engagement stages
      #
      TEMPLATES = {
        at_risk_check_in: {
          subject: "We noticed you haven't been using One-Time Secret recently",
          body: <<~EMAIL
            Hi {{customer_name}},

            We noticed it's been a while since you last used One-Time Secret. We wanted to check in and see if everything is working well for you.

            Your {{plan_name}} subscription gives you:
            • {{max_secrets}} secrets per month
            • {{ttl}} TTL for secrets
            • Priority support

            Is there anything we can help you with? We're here to ensure you're getting the most value from your subscription.

            Quick links:
            • Create a secret: {{app_url}}/private
            • View your dashboard: {{app_url}}/account
            • Need help? Reply to this email

            Best regards,
            The One-Time Secret Team
          EMAIL
        },

        feature_highlights: {
          subject: "5 powerful One-Time Secret features you might have missed",
          body: <<~EMAIL
            Hi {{customer_name}},

            As a {{plan_name}} subscriber, you have access to powerful features that can streamline your secure sharing workflow:

            1. **Email Delivery**: Send secrets directly to recipients via email
            2. **Custom TTL**: Set expiration times from 5 minutes to 7 days
            3. **Burn on Read**: Secrets automatically destroyed after viewing
            4. **Share Multiple Secrets**: Create and manage multiple secrets simultaneously
            5. **API Access**: Integrate with your tools and workflows

            Try creating a secret now: {{app_url}}/private

            Need ideas for how to use these features? Check out our use case guide:
            {{app_url}}/docs/use-cases

            Best regards,
            The One-Time Secret Team
          EMAIL
        },

        support_outreach: {
          subject: "How can we help you get more from One-Time Secret?",
          body: <<~EMAIL
            Hi {{customer_name}},

            We're reaching out because we want to make sure you're getting the full value from your One-Time Secret subscription.

            We've noticed you haven't been active recently. Common reasons include:
            • Not sure how to integrate it into your workflow
            • Missing a feature you need
            • Technical difficulties
            • Simply forgot about the subscription

            Whatever the reason, we're here to help! Reply to this email and we'll:
            • Provide personalized use case suggestions
            • Help troubleshoot any issues
            • Discuss features you might need
            • Or assist with cancellation if that's what you prefer

            Your satisfaction is our priority.

            Best regards,
            The One-Time Secret Team

            P.S. If you'd like to cancel, you can do so instantly at: {{app_url}}/account
          EMAIL
        },

        win_back_offer: {
          subject: "We miss you! Here's something special...",
          body: <<~EMAIL
            Hi {{customer_name}},

            We noticed you haven't been using One-Time Secret lately, and we miss having you as an active user!

            Before you decide to cancel, we'd like to offer you:
            • 1 month free (applied to your next billing cycle)
            • Priority support for setup and integration questions
            • A personalized onboarding call to maximize your usage

            We believe One-Time Secret can add real value to your security workflow, and we want to prove it to you.

            Interested? Just reply to this email with "Yes" and we'll set everything up.

            Not interested? We understand. You can cancel anytime at: {{app_url}}/account

            Best regards,
            The One-Time Secret Team
          EMAIL
        },

        use_case_examples: {
          subject: "3 ways teams use One-Time Secret every day",
          body: <<~EMAIL
            Hi {{customer_name}},

            Here's how other teams are using One-Time Secret as part of their daily workflow:

            **DevOps Teams:**
            "We use it to share production credentials during incident response. No more passwords in Slack!"
            - Share database passwords during deployments
            - Distribute API keys to team members
            - Send emergency access credentials

            **Customer Support:**
            "Perfect for sending password resets and temporary access codes to customers."
            - One-time login links
            - Temporary access credentials
            - Secure file sharing

            **Remote Teams:**
            "We share sensitive client data without worrying about it lingering in email or chat."
            - Client passwords and credentials
            - Contract signing links
            - Confidential documents

            Could One-Time Secret fit into your workflow like this?

            Try it now: {{app_url}}/private

            Best regards,
            The One-Time Secret Team
          EMAIL
        },

        founder_message: {
          subject: "A personal note from the One-Time Secret founder",
          body: <<~EMAIL
            Hi {{customer_name}},

            I'm Delano, founder of One-Time Secret. I wanted to reach out personally because I noticed you haven't been using the service lately.

            I built One-Time Secret to solve a real problem: sharing sensitive information securely without leaving a trail. Every subscription helps us keep the service running and improve it for everyone.

            I'd love to hear your feedback:
            • What made you sign up originally?
            • What's preventing you from using it now?
            • What would make it more valuable for you?

            Your input directly shapes our roadmap. Reply to this email—I read every response personally.

            If One-Time Secret isn't the right fit, I completely understand. You can cancel anytime at {{app_url}}/account, no hard feelings.

            Thanks for giving us a try.

            Delano
            Founder, One-Time Secret
          EMAIL
        },

        cancellation_reminder: {
          subject: "Your subscription will renew soon - is that what you want?",
          body: <<~EMAIL
            Hi {{customer_name}},

            This is a friendly reminder that your One-Time Secret subscription will automatically renew on {{renewal_date}}.

            We noticed you haven't been using the service recently. We want to make sure you're aware of the upcoming charge so there are no surprises.

            Your options:
            1. **Keep your subscription** - We'll continue to be here when you need us: {{app_url}}/account
            2. **Cancel now** - No hard feelings, cancel instantly at: {{app_url}}/account
            3. **Talk to us** - Reply to this email if you have questions or concerns

            We only want subscribers who get value from the service. If that's not you right now, we completely understand.

            Best regards,
            The One-Time Secret Team

            P.S. If you cancel and change your mind later, you can always re-subscribe!
          EMAIL
        },

        immediate_action_needed: {
          subject: "Important: Your One-Time Secret subscription",
          body: <<~EMAIL
            Hi {{customer_name}},

            We've noticed your One-Time Secret account has had no activity for {{days_inactive}} days, but your subscription is still active.

            **Your subscription will renew on {{renewal_date}} for {{amount}}.**

            We want to make absolutely sure this is intentional. If you're not using the service, you might want to:

            → Cancel your subscription now: {{app_url}}/account

            If you've been meaning to use it but haven't gotten around to it:
            • We can help you get started: reply to this email
            • Check out quick start guide: {{app_url}}/docs
            • Create your first secret: {{app_url}}/private

            Please take a moment to review your subscription status.

            Best regards,
            The One-Time Secret Team
          EMAIL
        },

        exclusive_retention_offer: {
          subject: "Last chance: 50% off for the next 3 months",
          body: <<~EMAIL
            Hi {{customer_name}},

            We really don't want to see you go. As a final offer, we'd like to give you:

            **50% off your subscription for the next 3 months**

            This gives you time to:
            • Integrate One-Time Secret into your workflow
            • Try all the premium features
            • See if it's the right fit for you

            To accept this offer, simply reply "YES" to this email and we'll apply the discount immediately.

            Not interested? We understand. Cancel anytime at: {{app_url}}/account

            This offer expires in 48 hours.

            Best regards,
            The One-Time Secret Team
          EMAIL
        },

        cancellation_assistance: {
          subject: "We're here to help with your cancellation",
          body: <<~EMAIL
            Hi {{customer_name}},

            We noticed you haven't engaged with our previous messages, which tells us One-Time Secret might not be the right fit for you right now.

            We want to make cancellation as easy as possible:

            **One-click cancellation:** {{app_url}}/account

            Before you go, we'd love your feedback (totally optional):
            • What made you sign up originally?
            • Why didn't it work out?
            • What could we improve?

            Your feedback helps us build a better product.

            If you decide to cancel:
            • No cancellation fees
            • Access until the end of your billing period
            • Easy to re-activate if you change your mind

            Thank you for trying One-Time Secret.

            Best regards,
            The One-Time Secret Team
          EMAIL
        }
      }.freeze

      attr_reader :customer, :health_score, :risk_level

      ##
      # Initialize workflow for a customer
      #
      # @param customer [V2::Customer] The customer to engage
      # @param health_score [Integer] Customer health score (0-100)
      # @param risk_level [String] Risk level: at_risk, zombie_candidate, critical
      #
      def initialize(customer, health_score, risk_level)
        @customer = customer
        @health_score = health_score
        @risk_level = risk_level.to_sym
      end

      ##
      # Get the appropriate workflow for this customer
      #
      # @return [Hash] Workflow definition
      #
      def workflow
        WORKFLOWS[@risk_level] || WORKFLOWS[:at_risk]
      end

      ##
      # Get all stages for this workflow
      #
      # @return [Array<Hash>] Workflow stages
      #
      def stages
        workflow[:stages]
      end

      ##
      # Generate the next action to take for this customer
      #
      # @param days_in_workflow [Integer] Days since workflow started (default: 0)
      # @return [Hash] Next action details
      #
      def next_action(days_in_workflow = 0)
        next_stage = stages.find { |stage| stage[:day] >= days_in_workflow }

        return { action: 'complete', message: 'Workflow complete' } unless next_stage

        {
          action: 'send_email',
          stage: next_stage[:type],
          template_name: next_stage[:template],
          days_until_send: next_stage[:day] - days_in_workflow,
          email: generate_email(next_stage[:template])
        }
      end

      ##
      # Generate email content from template
      #
      # @param template_name [String, Symbol] Template identifier
      # @return [Hash] Email subject and body with variables interpolated
      #
      def generate_email(template_name)
        template = TEMPLATES[template_name.to_sym]
        return nil unless template

        variables = build_template_variables

        {
          subject: interpolate(template[:subject], variables),
          body: interpolate(template[:body], variables),
          template: template_name.to_s,
          customer_id: customer.custid
        }
      end

      ##
      # Get complete workflow plan for customer
      #
      # @return [Hash] Complete workflow schedule
      #
      def plan
        {
          customer_id: customer.custid,
          email: customer.email,
          health_score: health_score,
          risk_level: @risk_level.to_s,
          workflow_type: @risk_level.to_s,
          workflow_description: workflow[:description],
          total_stages: stages.length,
          stages: stages.map { |stage|
            {
              day: stage[:day],
              type: stage[:type],
              template: stage[:template],
              email_preview: generate_email(stage[:template])
            }
          }
        }
      end

      private

      ##
      # Build variables for template interpolation
      #
      def build_template_variables
        plan_info = get_plan_info

        {
          customer_name: customer.email.split('@').first.capitalize,
          customer_email: customer.email,
          plan_name: plan_info[:name],
          max_secrets: plan_info[:max_secrets],
          ttl: plan_info[:ttl],
          app_url: 'https://onetimesecret.com',
          renewal_date: calculate_renewal_date,
          amount: plan_info[:amount],
          days_inactive: days_since_activity
        }
      end

      ##
      # Interpolate template variables
      #
      def interpolate(text, variables)
        result = text.dup
        variables.each do |key, value|
          result.gsub!("{{#{key}}}", value.to_s)
        end
        result
      end

      ##
      # Get plan information
      #
      def get_plan_info
        case customer.planid.to_s
        when 'basic'
          { name: 'Basic', max_secrets: '250', ttl: '7 days', amount: '$3/month' }
        when 'identity'
          { name: 'Identity', max_secrets: 'Unlimited', ttl: '30 days', amount: '$12/month' }
        else
          { name: 'Free', max_secrets: '10', ttl: '7 days', amount: '$0' }
        end
      end

      ##
      # Calculate next renewal date (estimated)
      #
      def calculate_renewal_date
        # This would ideally come from Stripe subscription data
        # For now, estimate based on monthly billing
        (Time.now + (30 * 86400)).strftime('%B %d, %Y')
      end

      ##
      # Calculate days since last activity
      #
      def days_since_activity
        last_login = customer.last_login.to_i
        return 999 if last_login == 0

        ((Time.now.to_i - last_login) / 86400.0).round
      end
    end
  end
end
