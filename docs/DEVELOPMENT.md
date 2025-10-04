# Development Guide

This guide provides tips and best practices for developing Onetime Secret.

## Debugging

To enable debug logging, set the `ONETIME_DEBUG` environment variable to `true`, `1`, or `yes`. This will provide more verbose output to help troubleshoot issues.

```bash
export ONETIME_DEBUG=true
bundle exec thin -R config.ru -p 3000 start
```

## Frontend Development

For frontend development with live reloading, you should run the application in frontend development mode. This involves running two processes in separate terminals:

1.  **Start the main server:** This runs the Ruby backend.
    ```bash
    RACK_ENV=development bundle exec thin -R config.ru -p 3000 start
    ```

2.  **Start the Vite dev server:** This serves frontend assets and enables Hot Module Replacement (HMR).
    ```bash
    pnpm run dev
    ```

Ensure your `etc/config.yaml` is configured correctly for this mode. See the [Installation Guide](../INSTALL.md) for details.

### Vite Development Server Security

For security, the Vite development server only allows connections from `localhost` by default. If you need to access the dev server from another machine on your network (e.g., a VM or a mobile device), you must explicitly configure `vite.config.ts` to allow your host.

**Example `vite.config.ts`:**

```typescript
// vite.config.ts
import { defineConfig } from 'vite';
import vue from '@vitejs/plugin-vue';

export default defineConfig({
  // ... other config
  server: {
    host: '0.0.0.0', // Listen on all network interfaces
    hmr: {
      host: 'your-local-ip-address', // Your machine's IP on the local network
    },
  },
});
```

> **Security Warning:** Never set `server.hmr.host` to a public IP or expose the Vite dev server to the internet, as this can create security vulnerabilities.

## Redis/Valkey Setup

The application supports both Redis and Valkey servers. Use environment variables to specify which server and CLI tools to use:

```bash
# Set these in your shell profile or .env file
export VALKEY_SERVER=valkey-server  # or redis-server
export VALKEY_CLI=valkey-cli        # or redis-cli
```

If not set, defaults to `valkey-server` and `valkey-cli`.

**Package.json scripts:**
```bash
pnpm run database:start     # Start server in daemon mode
pnpm run database:start:fg  # Start server in foreground
pnpm run database:stop      # Stop server
pnpm run database:status    # Check if server is running
pnpm run database:clean     # Clean database
```

## Setting up Pre-commit Hooks

We use the `pre-commit` framework to maintain code quality and consistency.

1.  **Install pre-commit:**
    ```bash
    pip install pre-commit
    ```

2.  **Install the git hooks:**
    ```bash
    pre-commit install
    ```

This will run automated checks before each commit.

## Docker-related Tips

### Container Name Already in Use

If you encounter an error like `docker: Error response from daemon: Conflict. The container name "/onetimesecret" is already in use`, it means a container with that name already exists. You can either remove the old container or start a new one with a different name.

```bash
# To remove the existing container
docker rm onetimesecret

# To start a new container with a different name
docker run --name onetimesecret-new ...
```

### Optimizing Docker Builds

To inspect the layers of a Docker image and identify opportunities for optimization, use the `docker history` command:

```bash
docker history onetimesecret --format "table {{.CreatedBy}}\t{{.Size}}"

# Or use dive for a more detailed analysis:
# brew install dive
# dive onetimesecret
```

### Docker Compose

For managing multi-container setups (e.g., the application and a separate database), we recommend using Docker Compose. We maintain a separate repository with ready-to-use configurations.

Visit our [Docker Compose repository](https://github.com/onetimesecret/docker-compose) for more information.

## Code Review Automation

We use Qodo Merge (formerly PR-Agent) for automated code reviews and compliance checks. The configuration is managed through two files:

### Configuration Files

- **`pr_agent.toml`**: Main Qodo Merge configuration with RAG context enrichment, ignore patterns, and custom labels
- **`pr_compliance_checklist.yaml`**: Custom compliance rules specific to our project

### Compliance Checks

Our custom compliance rules ensure:

1. **ErrorHandling**: Proper error handling for external API calls
2. **TestCoverage**: Tests required for new features (tryouts, RSpec, Vitest, or Playwright)
3. **RedisOperations**: Redis operations use Familia ORM patterns
4. **TypeSafety**: TypeScript code maintains type safety
5. **I18nSupport**: User-facing strings are internationalized
6. **SecurityPractices**: Security best practices are followed

### Interactive Commands

Team members can trigger on-demand analysis in PR comments:

- `/analyze --review` - Run code review
- `/analyze --test` - Generate test suggestions
- `/describe` - Update PR description
- `/improve` - Get code improvement suggestions

### Configuration Updates

When modifying Qodo Merge configuration:

1. Edit `pr_agent.toml` for general settings
2. Edit `pr_compliance_checklist.yaml` for compliance rules
3. Validate YAML syntax: `yamllint pr_compliance_checklist.yaml`
4. Test changes in a draft PR before merging

For more information, see the [Qodo Merge documentation](https://qodo-merge-docs.qodo.ai/).
