#!/usr/bin/env bash
# Move queue_config.rb and queue_declarator.rb into queues/ subdirectory
# and update all require references across the codebase.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

echo "=== Step 1: Move files ==="
git mv lib/onetime/jobs/queue_config.rb lib/onetime/jobs/queues/config.rb
git mv lib/onetime/jobs/queue_declarator.rb lib/onetime/jobs/queues/declarator.rb

echo "=== Step 2: Update file header comments ==="
sed -i '' 's|# lib/onetime/jobs/queue_config.rb|# lib/onetime/jobs/queues/config.rb|' lib/onetime/jobs/queues/config.rb
sed -i '' 's|# lib/onetime/jobs/queue_declarator.rb|# lib/onetime/jobs/queues/declarator.rb|' lib/onetime/jobs/queues/declarator.rb

echo "=== Step 3: Update internal require in declarator.rb ==="
# declarator.rb required 'queue_config' (same dir) -> now requires 'config' (same dir)
sed -i '' "s|require_relative 'queue_config'|require_relative 'config'|" lib/onetime/jobs/queues/declarator.rb

echo "=== Step 4: Update require_relative references in lib/ ==="

# From lib/onetime/initializers/ (one dir up from jobs/)
sed -i '' "s|require_relative '../jobs/queue_config'|require_relative '../jobs/queues/config'|" lib/onetime/initializers/setup_rabbitmq.rb
sed -i '' "s|require_relative '../jobs/queue_declarator'|require_relative '../jobs/queues/declarator'|" lib/onetime/initializers/setup_rabbitmq.rb

# From lib/onetime/jobs/publisher.rb (same dir as jobs/)
sed -i '' "s|require_relative 'queue_config'|require_relative 'queues/config'|" lib/onetime/jobs/publisher.rb

# From lib/onetime/jobs/scheduled/ (one dir up to jobs/)
sed -i '' "s|require_relative '../queue_config'|require_relative '../queues/config'|" lib/onetime/jobs/scheduled/dlq_monitor_job.rb

# From lib/onetime/jobs/workers/ (one dir up to jobs/)
for f in lib/onetime/jobs/workers/notification_worker.rb \
         lib/onetime/jobs/workers/billing_worker.rb \
         lib/onetime/jobs/workers/transient_worker.rb \
         lib/onetime/jobs/workers/email_worker.rb; do
  sed -i '' "s|require_relative '../queue_config'|require_relative '../queues/config'|" "$f"
  sed -i '' "s|require_relative '../queue_declarator'|require_relative '../queues/declarator'|" "$f"
done

# From lib/onetime/cli/ (relative paths vary)
sed -i '' "s|require_relative '../jobs/queue_config'|require_relative '../jobs/queues/config'|" lib/onetime/cli/status_command.rb
sed -i '' "s|require_relative '../jobs/queue_config'|require_relative '../jobs/queues/config'|" lib/onetime/cli/worker_command.rb
sed -i '' "s|require_relative '../jobs/queue_declarator'|require_relative '../jobs/queues/declarator'|" lib/onetime/cli/worker_command.rb

# From lib/onetime/cli/queue/ (two dirs up)
for f in lib/onetime/cli/queue/status_command.rb \
         lib/onetime/cli/queue/reset_command.rb \
         lib/onetime/cli/queue/dlq_command.rb \
         lib/onetime/cli/queue/ping_command.rb \
         lib/onetime/cli/queue/init_command.rb; do
  sed -i '' "s|require_relative '../../jobs/queue_config'|require_relative '../../jobs/queues/config'|" "$f"
  sed -i '' "s|require_relative '../../jobs/queue_declarator'|require_relative '../../jobs/queues/declarator'|" "$f"
done

echo "=== Step 5: Update require references in spec/ ==="
# These use require (not require_relative) with load-path style
for f in spec/integration/all/jobs/workers/notification_worker_spec.rb \
         spec/integration/all/jobs/workers/billing_worker_spec.rb \
         spec/integration/all/jobs/workers/sneakers_harness_spec.rb \
         spec/integration/all/jobs/workers/base_worker_spec.rb \
         spec/integration/all/jobs/workers/email_worker_spec.rb \
         spec/integration/all/jobs/dlq_routing_spec.rb \
         spec/integration/all/jobs/rabbitmq_publishing_spec.rb \
         spec/unit/onetime/initializers/setup_rabbitmq_spec.rb \
         spec/unit/onetime/jobs/queue_config_spec.rb \
         spec/unit/onetime/jobs/workers/sneakers_configuration_spec.rb; do
  [ -f "$f" ] && sed -i '' "s|require 'onetime/jobs/queue_config'|require 'onetime/jobs/queues/config'|" "$f"
done

echo "=== Done ==="
echo "Verify with: git diff --stat && grep -r 'queue_config\|queue_declarator' lib/ spec/ --include='*.rb' | grep -v 'QueueConfig\|queue_config_spec'"
