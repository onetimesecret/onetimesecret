## Staging database

Rotate the **deploy** password after the release.

- Host: `db.staging.internal`
- Password: `c0rrect-h0rse-battery`

```bash
# Check the pending migrations
psql -U deploy -c "SELECT version FROM schema_migrations;"
```

> Steps are in the [runbook](https://docs.example.com/runbooks/db).
