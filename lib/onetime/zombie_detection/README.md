# Zombie Subscription Detection System

A comprehensive system for identifying, analyzing, and re-engaging inactive paying customers ("zombie subscriptions") to reduce preventable churn and maximize revenue retention.

## 🎯 Overview

The Zombie Detection System helps you identify customers who are paying for subscriptions but not actively using the service. This addresses a critical business problem: **distinguishing between true churn (product dissatisfaction) and zombie churn (forgotten/unused subscriptions)**.

### Why This Matters

- **7% Churn Rate Analysis**: Not all churn is equal. Zombie churn is preventable through engagement.
- **Revenue Recovery**: Identifying zombies early allows for proactive retention campaigns.
- **Product Insights**: True churn vs zombie churn reveals whether you have a product problem or an engagement problem.

## 📊 System Components

### 1. **Health Scoring System** (`health_scorer.rb`)

Calculates a 0-100 health score for each customer based on:

- **Recency (35% weight)**: How recently they logged in
- **Frequency (25% weight)**: How often they use the service
- **Volume (20% weight)**: Total usage amount
- **Engagement (20% weight)**: Breadth of feature usage

**Score Ranges:**
- 90-100: Excellent health, highly engaged
- 70-89: Good health, regular user
- 50-69: Fair health, at-risk user
- 30-49: Poor health, zombie candidate
- 0-29: Critical, likely zombie

### 2. **Anomaly Detection** (`anomaly_detector.rb`)

Identifies unusual patterns indicating zombie behavior:

- **Never Used**: Paid subscription with zero usage after 30+ days
- **Prolonged Inactivity**: No login for 60+ days
- **Minimal Usage**: Very low usage relative to subscription duration
- **Usage Drop**: Significant drop from previous activity levels
- **No Recent Logins**: Active subscription but never logged in
- **Subscription Without Engagement**: Minimal engagement across all metrics

### 3. **Churn Analysis** (`churn_calculator.rb`)

Categorizes churn into:

**Zombie Churn** (Preventable):
- Low health score at cancellation (<40)
- Minimal usage (<2 secrets/month)
- Long inactivity period (45+ days)
- Very low lifetime usage (<10 secrets)

**True Churn** (Product/Market):
- High health score at cancellation (>70)
- Active usage pattern (10+ secrets/month)
- Recently active (<7 days)

Provides revenue impact analysis and prevention scenarios.

### 4. **Re-engagement Workflows** (`re_engagement_workflow.rb`)

Automated, multi-stage email campaigns based on risk level:

**At-Risk (Health Score 50-69):**
1. Day 0: Health check-in
2. Day 7: Feature highlights
3. Day 14: Support outreach

**Zombie Candidate (Health Score 30-49):**
1. Day 0: Win-back offer
2. Day 3: Use case education
3. Day 7: Personal founder message
4. Day 14: Cancellation reminder

**Critical (Health Score <30):**
1. Day 0: Urgent intervention
2. Day 2: Special retention offer
3. Day 5: Exit survey and cancellation assistance

### 5. **Stripe Sigma Queries** (`queries/stripe_sigma_queries.sql`)

Pre-built SQL queries for Stripe dashboard analysis:

- Active subscriptions summary
- Zombie candidate detection
- MRR analysis by cohorts
- Subscription retention by plan
- Payment success rate analysis
- Revenue at risk calculations
- Customer lifetime value analysis

### 6. **Main Detector** (`detector.rb`)

Orchestrates all components:

- Scans all eligible customers
- Identifies zombies
- Calculates aggregate metrics
- Provides actionable recommendations
- Calculates revenue impact

## 🚀 API Endpoints

### Admin/Colonel Endpoints

All endpoints require colonel (admin) authentication.

#### 1. Get Full Zombie Analysis

```bash
GET /api/v2/colonel/zombies
```

**Response:**
```json
{
  "record": {
    "scan_metadata": {
      "scanned_at": 1700000000,
      "total_customers_scanned": 500
    },
    "summary": {
      "zombies_detected": 45,
      "zombie_percentage": 9.0,
      "total_mrr_at_risk": 135.00,
      "annual_revenue_at_risk": 1620.00
    },
    "risk_distribution": {
      "critical": 12,
      "high": 18,
      "medium": 15,
      "low": 0,
      "healthy": 455
    },
    "aggregate_metrics": {
      "avg_health_score": 35.5,
      "avg_anomalies_per_zombie": 3.2,
      "most_common_anomaly_types": {
        "prolonged_inactivity": 38,
        "minimal_usage": 35,
        "never_used": 12
      }
    }
  },
  "details": {
    "zombies": [...],
    "revenue_impact": {...},
    "recommendations": {...}
  }
}
```

#### 2. Get Customer Health Analysis

```bash
GET /api/v2/colonel/customer/:customer_id/health
```

**Example:**
```bash
GET /api/v2/colonel/customer/user@example.com/health
```

**Response:**
```json
{
  "record": {
    "customer_id": "user@example.com",
    "email": "user@example.com",
    "plan": "basic",
    "is_zombie": true,
    "health_score": 28,
    "risk_level": "critical"
  },
  "details": {
    "anomalies": [
      {
        "type": "prolonged_inactivity",
        "severity": "high",
        "description": "No login activity for 75 days",
        "details": {
          "days_inactive": 75,
          "last_login_at": 1693000000
        }
      }
    ],
    "health_breakdown": {
      "overall_score": 28,
      "components": {
        "recency": {
          "score": 15,
          "weight": 35,
          "weighted_score": 5.25
        },
        "frequency": {...},
        "volume": {...},
        "engagement": {...}
      },
      "interpretation": {
        "level": "critical",
        "status": "likely_zombie",
        "action": "immediate_intervention"
      }
    },
    "re_engagement_plan": {
      "workflow_type": "critical",
      "stages": [...]
    }
  }
}
```

#### 3. Get Zombies by Risk Level

```bash
GET /api/v2/colonel/zombies/:risk_level
```

**Valid risk levels:** `critical`, `high`, `medium`, `low`, `healthy`

**Example:**
```bash
GET /api/v2/colonel/zombies/critical
```

**Response:**
```json
{
  "record": {
    "risk_level": "critical",
    "customer_count": 12
  },
  "details": {
    "customers": [
      {
        "customer_id": "zombie1@example.com",
        "email": "zombie1@example.com",
        "plan": "basic",
        "health_score": 22,
        "anomaly_count": 4,
        "has_re_engagement_plan": true
      },
      ...
    ],
    "full_details": [...]
  }
}
```

## 💻 Usage Examples

### Ruby/CLI Usage

```ruby
require 'onetime/zombie_detection/detector'

# Initialize detector
detector = Onetime::ZombieDetection::Detector.new(
  min_subscription_age_days: 30,
  health_score_threshold: 70,
  paid_only: true
)

# Scan all customers
results = detector.scan_all_customers

puts "Found #{results[:zombies_detected]} zombie subscriptions"
puts "Revenue at risk: $#{results[:revenue_impact][:total_mrr_at_risk]}/month"

# Analyze specific customer
customer = V2::Customer.load('user@example.com')
analysis = detector.analyze_customer(customer)

if analysis[:is_zombie]
  puts "Customer is a zombie with health score: #{analysis[:health_score]}"
  puts "Anomalies detected: #{analysis[:anomalies].length}"

  # Get re-engagement plan
  plan = analysis[:re_engagement_plan]
  puts "Re-engagement workflow: #{plan[:workflow_type]}"
  puts "Total stages: #{plan[:total_stages]}"
end

# Get customers by risk level
critical_customers = detector.get_customers_by_risk('critical')
puts "Critical risk customers: #{critical_customers.length}"

# Calculate revenue impact
revenue_impact = detector.calculate_revenue_impact(results[:zombies])
puts "Conservative prevention (50%): $#{revenue_impact[:prevention_scenarios][:conservative_50pct]}/year"
puts "Optimistic prevention (75%): $#{revenue_impact[:prevention_scenarios][:optimistic_75pct]}/year"

# Get recommendations
recommendations = detector.generate_recommendations(results)
recommendations[:recommendations].each do |rec|
  puts "[#{rec[:priority].upcase}] #{rec[:action]}"
end
```

### Stripe Sigma Analysis

1. Log into Stripe Dashboard → Reports → Query data (Sigma)
2. Copy queries from `queries/stripe_sigma_queries.sql`
3. Run Query #2 (Zombie Candidate Detection) and export as CSV
4. Match customer emails with application data to correlate billing with usage

### Re-engagement Campaign Implementation

```ruby
require 'onetime/zombie_detection/re_engagement_workflow'

# For a zombie customer
workflow = Onetime::ZombieDetection::ReEngagementWorkflow.new(
  customer,
  health_score: 35,
  risk_level: 'zombie_candidate'
)

# Get complete workflow plan
plan = workflow.plan

# Send first email
next_action = workflow.next_action(days_in_workflow: 0)
email = next_action[:email]

send_email(
  to: email[:customer_id],
  subject: email[:subject],
  body: email[:body]
)

# Schedule future emails
plan[:stages].each do |stage|
  schedule_email(
    customer: customer,
    template: stage[:template],
    send_at: Time.now + (stage[:day] * 86400)
  )
end
```

### Churn Analysis

```ruby
require 'onetime/zombie_detection/churn_calculator'

calculator = Onetime::ZombieDetection::ChurnCalculator.new(90) # 90-day analysis period

# Analyze cancelled customer
cancelled_customer = V2::Customer.load('churned@example.com')
analysis = calculator.analyze_customer_churn(
  cancelled_customer,
  cancellation_date: Time.now.to_i
)

puts "Churn Type: #{analysis[:churn_type]}"
puts "Category: #{analysis[:churn_category]}"
puts "Preventable: #{analysis[:preventable]}"
puts "Confidence: #{analysis[:confidence]}"

# Aggregate analysis across multiple customers
cancelled_customers = [...]  # Array of churn analyses
aggregate = calculator.aggregate_churn_analysis(cancelled_customers)

puts "Zombie Churn Rate: #{aggregate[:zombie_churn][:percentage]}%"
puts "True Churn Rate: #{aggregate[:true_churn][:percentage]}%"
puts "Preventable Revenue: $#{aggregate[:zombie_churn][:total_preventable_revenue]}/month"

# Revenue impact projection
impact = calculator.calculate_zombie_prevention_impact(
  current_churn_rate: 7.0,        # 7% monthly churn
  zombie_percentage: 60.0,         # 60% of churn is zombie
  avg_monthly_revenue: 3.00,       # $3/customer/month
  total_customers: 1000            # 1000 active customers
)

puts "Current monthly zombie churn: #{impact[:current_state][:monthly_zombie_churn]} customers"
puts "Monthly revenue lost to zombies: $#{impact[:current_state][:monthly_revenue_lost_to_zombies]}"
puts "\nPrevention Scenarios:"
puts "50% prevention: $#{impact[:prevention_scenarios][:conservative_50pct]}/year saved"
puts "75% prevention: $#{impact[:prevention_scenarios][:optimistic_75pct]}/year saved"
puts "90% prevention: $#{impact[:prevention_scenarios][:ideal_90pct]}/year saved"
```

## 📈 Metrics & KPIs

### Primary Metrics

1. **Zombie Detection Rate**: % of paid customers identified as zombies
2. **Health Score Distribution**: Distribution across score ranges
3. **Revenue at Risk**: MRR from zombie subscriptions
4. **Preventable Churn Rate**: % of total churn that's zombie churn

### Success Metrics

Track after implementing re-engagement:

1. **Zombie Reactivation Rate**: % of zombies who increase usage
2. **Voluntary Downgrades**: % who downgrade vs cancel (revenue retention)
3. **Prevented Churn**: Zombies saved from cancellation
4. **Revenue Recovered**: MRR saved through engagement campaigns

### Example Dashboard

```
Zombie Detection Dashboard (Last 30 Days)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Active Paid Customers:     1,245
Zombies Detected:          112 (9.0%)
Revenue at Risk:           $336/month ($4,032/year)

Risk Distribution:
  Critical (0-29):         23 customers  $69/mo
  High (30-49):            47 customers  $141/mo
  Medium (50-69):          42 customers  $126/mo
  Low (70-89):             98 customers  (healthy)
  Excellent (90-100):      1,035 customers (healthy)

Re-engagement Campaign Status:
  Emails Sent:             67
  Reactivated:             12 (17.9%)
  Awaiting Response:       31
  Opted Out:               24

Churn Analysis (Last 90 Days):
  Total Churned:           84 customers
  Zombie Churn:            51 (60.7%)
  True Churn:              33 (39.3%)

Preventable Revenue:       $153/month ($1,836/year)
```

## 🔧 Configuration

### Detection Thresholds

Customize in `anomaly_detector.rb`:

```ruby
THRESHOLDS = {
  min_subscription_age_days: 30,      # Minimum age to analyze
  max_inactivity_days: 60,            # Zombie threshold
  min_usage_threshold: 5,             # Minimum usage level
  zombie_score_threshold: 70          # Health score cutoff
}
```

### Health Score Weights

Adjust in `health_scorer.rb`:

```ruby
WEIGHTS = {
  recency: 35,      # Recent activity importance
  frequency: 25,    # Usage frequency importance
  volume: 20,       # Total usage importance
  engagement: 20    # Feature breadth importance
}
```

## 🚨 Common Issues & Solutions

### Issue: Too Many False Positives

**Solution:** Adjust thresholds:
- Increase `min_subscription_age_days` to 60 or 90
- Lower `zombie_score_threshold` to 50 or 60
- Increase `min_usage_threshold`

### Issue: Missing Zombies

**Solution:** Relax detection criteria:
- Decrease `max_inactivity_days` to 45
- Increase `zombie_score_threshold` to 80
- Add custom anomaly detection rules

### Issue: Re-engagement Emails Not Converting

**Solution:**
- A/B test email templates
- Adjust workflow timing (shorter/longer delays)
- Add personalization tokens
- Include specific value propositions

## 📚 Architecture

```
lib/onetime/zombie_detection/
├── detector.rb                    # Main orchestrator
├── health_scorer.rb              # 0-100 health score calculation
├── anomaly_detector.rb           # Pattern detection algorithms
├── churn_calculator.rb           # True vs zombie churn analysis
├── re_engagement_workflow.rb     # Email campaign workflows
├── queries/
│   └── stripe_sigma_queries.sql  # Stripe data analysis queries
└── README.md                      # This file

apps/api/v2/logic/colonel/
├── get_zombie_analysis.rb        # Full scan endpoint
├── get_customer_health.rb        # Single customer analysis
└── get_zombies_by_risk.rb        # Filter by risk level

apps/api/v2/controllers/
└── colonel.rb                     # Route handlers

tests/unit/
└── zombie_detection_test.rb      # Unit tests
```

## 🎯 Roadmap

### Implemented ✅

- Health scoring system
- Anomaly detection algorithms
- Churn categorization (zombie vs true)
- Re-engagement workflow design
- Stripe Sigma queries
- Admin API endpoints
- Revenue impact calculations

### Future Enhancements 🔮

1. **Automated Campaign Execution**
   - Integrate with email service provider
   - Automatic campaign scheduling
   - A/B test management

2. **Machine Learning Enhancement**
   - Predict zombie risk before it happens
   - Optimize health score weights automatically
   - Personalized re-engagement timing

3. **Real-time Monitoring**
   - Dashboard for live zombie tracking
   - Slack/email alerts for critical risk customers
   - Health score trending over time

4. **Advanced Segmentation**
   - Zombie personas (never-used vs dropped-off)
   - Industry/use-case specific scoring
   - Cohort-based analysis

5. **Integration Expansion**
   - Intercom/Customer.io integration
   - Mixpanel/Amplitude tracking
   - ChartMogul revenue analytics

## 📞 Support

For questions or issues:
1. Check this README
2. Review code comments in individual modules
3. Check test files for usage examples
4. Review API endpoint responses for data structure

## 📄 License

Part of the One-Time Secret application.
