.. A new scriv changelog fragment.

Changed
-------

- **Frontend Architecture**: Restructured Vue application from flat `views/` and `components/` directories to domain-driven `apps/` structure with five interaction modes: Secret (transactional flows), Workspace (management), Session (authentication), Kernel (admin), and Billing (commerce). This migration moves ~116 files, creates 15 new files, and removes 18 redundant files. PR #2114


AI Assistance
-------------

- Claude Code assisted with planning the migration strategy, generating the migration manifest, and updating import paths across the codebase.
