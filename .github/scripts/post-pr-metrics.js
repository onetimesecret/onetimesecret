/**
 * Post CI performance metrics as a PR comment.
 *
 * This script formats tier timing data and posts/updates a PR comment
 * with the CI performance metrics summary.
 *
 * Usage (in GitHub Actions with actions/github-script@v7):
 *   const script = require('./.github/scripts/post-pr-metrics.js');
 *   await script({ github, context, core, tierData });
 *
 * @param {Object} options
 * @param {Object} options.github - GitHub API client from actions/github-script
 * @param {Object} options.context - Action context from actions/github-script
 * @param {Object} options.core - Core utilities from actions/github-script
 * @param {Object} options.tierData - Tier timing data with seconds and targets
 */
module.exports = async function postPrMetrics({ github, context, core, tierData }) {
  const tiers = [
    {
      name: 'Tier 1',
      jobs: 'Lint & Build',
      seconds: tierData.tier1Seconds,
      target: tierData.tier1Target || 60,
    },
    {
      name: 'Tier 2',
      jobs: 'Unit Tests',
      seconds: tierData.tier2Seconds,
      target: tierData.tier2Target || 120,
    },
    {
      name: 'Tier 3',
      jobs: 'Integration Tests',
      seconds: tierData.tier3Seconds,
      target: tierData.tier3Target || 210,
    },
    {
      name: 'Tier 4',
      jobs: 'Container Validation',
      seconds: tierData.tier4Seconds,
      target: tierData.tier4Target || 400,
    },
  ];

  /**
   * Format duration in seconds to human-readable string.
   * @param {string|number} secs - Duration in seconds
   * @returns {string} Formatted duration (e.g., "2m 30s")
   */
  function formatDuration(secs) {
    if (!secs || secs === 'N/A') return 'N/A';
    const s = parseInt(secs, 10);
    if (isNaN(s)) return 'N/A';
    if (s >= 60) {
      const m = Math.floor(s / 60);
      const r = s % 60;
      return `${m}m ${r}s`;
    }
    return `${s}s`;
  }

  /**
   * Get status icon based on actual vs target time.
   * @param {string|number} secs - Actual duration in seconds
   * @param {number} target - Target duration in seconds
   * @returns {string} Status icon emoji
   */
  function statusIcon(secs, target) {
    if (!secs || secs === 'N/A') return '❓';
    const s = parseInt(secs, 10);
    if (isNaN(s)) return '❓';
    const warning = target + Math.floor(target * 0.2); // 20% buffer
    if (s <= target) return '✅';
    if (s <= warning) return '⚠️';
    return '❌';
  }

  // Build tier rows for the table
  const tierRows = tiers
    .map(
      (t) =>
        `| ${t.name} | ${t.jobs} | ${formatDuration(t.seconds)} | <${t.target}s | ${statusIcon(t.seconds, t.target)} |`
    )
    .join('\n');

  const runUrl = `https://github.com/${context.repo.owner}/${context.repo.repo}/actions/runs/${context.runId}`;

  const comment = `## 📊 CI Performance Metrics

| Tier | Jobs | Actual | Target | Status |
|------|------|--------|--------|--------|
${tierRows}

<details>
<summary>Tier Details</summary>

- **Tier 1 - Lint & Build**: Ruby Lint, TypeScript Lint, i18n Validation, Build Frontend Assets
- **Tier 2 - Unit Tests**: Ruby Unit Tests, TypeScript Unit Tests
- **Tier 3 - Integration Tests**: Ruby Integration (Simple, Full-SQLite, Full-PostgreSQL, Disabled modes)
- **Tier 4 - Container Validation**: Docker build and health check
- **Tier 5 - CI Metrics**: Performance validation and reporting

Times are cumulative from workflow start.
</details>

🔗 [View full workflow run](${runUrl})
`;

  // Find existing bot comment with this header
  const { data: comments } = await github.rest.issues.listComments({
    owner: context.repo.owner,
    repo: context.repo.repo,
    issue_number: context.issue.number,
  });

  const botComment = comments.find(
    (c) => c.user.type === 'Bot' && c.body.includes('📊 CI Performance Metrics')
  );

  if (botComment) {
    await github.rest.issues.updateComment({
      owner: context.repo.owner,
      repo: context.repo.repo,
      comment_id: botComment.id,
      body: comment,
    });
    core.info(`Updated existing PR comment: ${botComment.html_url}`);
  } else {
    const { data: newComment } = await github.rest.issues.createComment({
      owner: context.repo.owner,
      repo: context.repo.repo,
      issue_number: context.issue.number,
      body: comment,
    });
    core.info(`Created new PR comment: ${newComment.html_url}`);
  }
};
