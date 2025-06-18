# Naming Convention: Config vs Settings

## Overview

The distinction between **Config** and **Settings** provides semantic clarity based on blast radius, access control, modification mechanism, and timing. This convention resolves frontend/backend consistency issues and eliminates confusion between static Config and RuntimeConfigService classes.

## Definitions

### Config (YAML File)
High-impact parameters requiring intentional file access and deploy-time modification:
- Authentication toggles
- Database credentials
- Security settings
- API endpoints

**Characteristics:** High blast radius where errors could cause system-wide failures or security incidents.

### Settings (Database/UI)
Low-impact operational parameters accessible through UI for runtime modification:
- Timeouts
- Display preferences
- Feature flags
- Operational tweaks

**Characteristics:** Low blast radius with recoverable errors and contained impact.

## Key Distinctions

| Aspect | Config | Settings |
|--------|--------|----------|
| **Mechanism** | File system | Application UI/Database |
| **Timing** | Deploy-time | Runtime |
| **Access Control** | File-level permissions | Application-level |
| **Blast Radius** | System-wide impact | Contained impact |
| **Recovery** | Requires deployment | Immediate correction possible |

## Layered Architecture

### 1. Base Configuration Layer (Config)
Provides foundational, default, and system-critical parameters loaded from primary configuration files.

### 2. Runtime Settings Layer (Settings)
Enables overrides and additions to base configuration through:
- User-specific configurations
- Environment variables
- Command-line arguments
- Database storage

## Benefits

**Clear Defaults:** Base config establishes application defaults without user intervention.

**Safe Customization:** Users modify behavior through settings without altering core configuration, preserving update compatibility.

**Flexible Extension:** Additional layers can be introduced between base config and user settings as needed.

**Simplified Code Logic:** Application code accesses a single configuration resolver, abstracting the underlying sources.

**Enhanced Testability:** Simplified mocking and configuration injection for testing scenarios.

## Implementation Notes

This approach provides a robust configuration management system enabling both system-level defaults and user-specific customizations while maintaining a consistent access interface for application code.
