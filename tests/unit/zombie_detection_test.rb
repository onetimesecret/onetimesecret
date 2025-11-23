require_relative '../test_helper'
require_relative '../../lib/onetime/zombie_detection/health_scorer'
require_relative '../../lib/onetime/zombie_detection/anomaly_detector'
require_relative '../../lib/onetime/zombie_detection/churn_calculator'
require_relative '../../lib/onetime/zombie_detection/re_engagement_workflow'

class ZombieDetectionTest < Minitest::Test
  include TestHelper

  def setup
    @customer_data = {
      custid: 'test@example.com',
      email: 'test@example.com',
      planid: 'basic',
      created: Time.now.to_i - (60 * 86400),  # 60 days ago
      last_login: Time.now.to_i - (45 * 86400),  # 45 days ago
      secrets_created: 3,
      secrets_shared: 1,
      secrets_burned: 1,
      emails_sent: 2,
      stripe_subscription_id: 'sub_12345'
    }

    @mock_customer = Minitest::Mock.new
    @customer_data.each do |key, value|
      @mock_customer.expect(key, value)
    end
  end

  # HealthScorer Tests
  def test_health_scorer_initialization
    scorer = Onetime::ZombieDetection::HealthScorer.new(@mock_customer)
    assert_instance_of Onetime::ZombieDetection::HealthScorer, scorer
  end

  def test_health_score_calculation_for_zombie
    # Mock a zombie customer - no usage, long inactive
    zombie_customer = create_mock_customer(
      secrets_created: 0,
      last_login: Time.now.to_i - (90 * 86400),  # 90 days inactive
      planid: 'basic'
    )

    scorer = Onetime::ZombieDetection::HealthScorer.new(zombie_customer)
    score = scorer.calculate

    assert score < 50, "Zombie customer should have health score < 50, got #{score}"
  end

  def test_health_score_calculation_for_healthy_customer
    # Mock a healthy customer - good usage, recent login
    healthy_customer = create_mock_customer(
      secrets_created: 100,
      last_login: Time.now.to_i - (2 * 86400),  # 2 days ago
      created: Time.now.to_i - (60 * 86400),  # 60 days old
      planid: 'identity'
    )

    scorer = Onetime::ZombieDetection::HealthScorer.new(healthy_customer)
    score = scorer.calculate

    assert score > 70, "Healthy customer should have health score > 70, got #{score}"
  end

  def test_health_score_breakdown
    scorer = Onetime::ZombieDetection::HealthScorer.new(@mock_customer)
    breakdown = scorer.breakdown

    assert_includes breakdown, :overall_score
    assert_includes breakdown, :components
    assert_includes breakdown, :metrics
    assert_includes breakdown, :interpretation

    assert_equal 4, breakdown[:components].keys.length
    assert_includes breakdown[:components], :recency
    assert_includes breakdown[:components], :frequency
    assert_includes breakdown[:components], :volume
    assert_includes breakdown[:components], :engagement
  end

  # AnomalyDetector Tests
  def test_anomaly_detector_initialization
    detector = Onetime::ZombieDetection::AnomalyDetector.new(@mock_customer)
    assert_instance_of Onetime::ZombieDetection::AnomalyDetector, detector
  end

  def test_anomaly_detection_for_zombie
    zombie_customer = create_mock_customer(
      secrets_created: 0,
      last_login: Time.now.to_i - (90 * 86400),
      created: Time.now.to_i - (60 * 86400),
      planid: 'basic'
    )

    detector = Onetime::ZombieDetection::AnomalyDetector.new(zombie_customer)
    result = detector.detect

    assert result[:is_zombie], "Should detect as zombie"
    assert result[:anomalies].length > 0, "Should have anomalies"
    assert_includes ['critical', 'high'], result[:risk_level]
  end

  def test_anomaly_detection_includes_all_fields
    detector = Onetime::ZombieDetection::AnomalyDetector.new(@mock_customer)
    result = detector.detect

    assert_includes result, :customer_id
    assert_includes result, :email
    assert_includes result, :is_zombie
    assert_includes result, :anomalies
    assert_includes result, :metrics
    assert_includes result, :health_score
    assert_includes result, :risk_level
  end

  # ChurnCalculator Tests
  def test_churn_calculator_initialization
    calculator = Onetime::ZombieDetection::ChurnCalculator.new(90)
    assert_instance_of Onetime::ZombieDetection::ChurnCalculator, calculator
    assert_equal 90, calculator.analysis_period_days
  end

  def test_churn_categorization_zombie
    zombie_customer = create_mock_customer(
      secrets_created: 1,
      last_login: Time.now.to_i - (90 * 86400),
      created: Time.now.to_i - (120 * 86400),
      planid: 'basic'
    )

    calculator = Onetime::ZombieDetection::ChurnCalculator.new
    analysis = calculator.analyze_customer_churn(zombie_customer)

    assert_equal 'zombie', analysis[:churn_category]
    assert analysis[:preventable], "Zombie churn should be preventable"
  end

  def test_churn_categorization_true_churn
    # Active user who decided to cancel
    active_customer = create_mock_customer(
      secrets_created: 200,
      last_login: Time.now.to_i - (2 * 86400),
      created: Time.now.to_i - (180 * 86400),
      planid: 'identity'
    )

    calculator = Onetime::ZombieDetection::ChurnCalculator.new
    analysis = calculator.analyze_customer_churn(active_customer)

    assert_equal 'true', analysis[:churn_category]
    refute analysis[:preventable], "True churn is not preventable"
  end

  def test_churn_revenue_impact_calculation
    zombie_customer = create_mock_customer(
      secrets_created: 1,
      created: Time.now.to_i - (90 * 86400),
      planid: 'basic'
    )

    calculator = Onetime::ZombieDetection::ChurnCalculator.new
    analysis = calculator.analyze_customer_churn(zombie_customer)

    assert_includes analysis, :estimated_revenue_impact
    assert_includes analysis[:estimated_revenue_impact], :monthly_value
    assert_includes analysis[:estimated_revenue_impact], :total_lifetime_revenue
  end

  # ReEngagementWorkflow Tests
  def test_re_engagement_workflow_initialization
    workflow = Onetime::ZombieDetection::ReEngagementWorkflow.new(
      @mock_customer, 45, 'zombie_candidate'
    )
    assert_instance_of Onetime::ZombieDetection::ReEngagementWorkflow, workflow
  end

  def test_re_engagement_workflow_stages
    workflow = Onetime::ZombieDetection::ReEngagementWorkflow.new(
      @mock_customer, 45, 'zombie_candidate'
    )

    stages = workflow.stages
    assert stages.length > 0, "Should have workflow stages"

    stages.each do |stage|
      assert_includes stage, :day
      assert_includes stage, :type
      assert_includes stage, :template
    end
  end

  def test_re_engagement_email_generation
    workflow = Onetime::ZombieDetection::ReEngagementWorkflow.new(
      @mock_customer, 45, 'zombie_candidate'
    )

    email = workflow.generate_email('win_back_offer')

    assert_includes email, :subject
    assert_includes email, :body
    assert_includes email, :template
    refute_empty email[:subject]
    refute_empty email[:body]
  end

  def test_re_engagement_workflow_plan
    workflow = Onetime::ZombieDetection::ReEngagementWorkflow.new(
      @mock_customer, 45, 'critical'
    )

    plan = workflow.plan

    assert_includes plan, :customer_id
    assert_includes plan, :health_score
    assert_includes plan, :risk_level
    assert_includes plan, :stages
    assert plan[:stages].length > 0
  end

  def test_different_workflows_for_risk_levels
    risk_levels = ['at_risk', 'zombie_candidate', 'critical']

    risk_levels.each do |risk_level|
      workflow = Onetime::ZombieDetection::ReEngagementWorkflow.new(
        @mock_customer, 50, risk_level
      )

      assert_equal risk_level, workflow.plan[:risk_level]
      assert workflow.stages.length > 0
    end
  end

  private

  def create_mock_customer(attributes = {})
    defaults = {
      custid: 'test@example.com',
      email: 'test@example.com',
      planid: 'anonymous',
      created: Time.now.to_i - (30 * 86400),
      last_login: Time.now.to_i - (7 * 86400),
      secrets_created: 10,
      secrets_shared: 5,
      secrets_burned: 3,
      emails_sent: 4,
      stripe_subscription_id: ''
    }

    data = defaults.merge(attributes)
    mock = Minitest::Mock.new

    data.each do |key, value|
      mock.expect(key, value)
    end

    mock
  end
end
