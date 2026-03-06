##
# DOCKER BAKE - OTS BUILD ORCHESTRATION
#
# Usage:
#   docker buildx bake -f docker/bake.hcl              # builds default (main)
#   docker buildx bake -f docker/bake.hcl all           # builds all targets
#   docker buildx bake -f docker/bake.hcl ci            # builds CI targets
#   docker buildx bake -f docker/bake.hcl --print       # dry-run, inspect config
#
# Override variables:
#   docker buildx bake -f docker/bake.hcl \
#     --set '*.args.VERSION=1.0.0' \
#     --set '*.args.COMMIT_HASH=abc1234' \
#     ci
#
# Tagging:
#   VERSION    → clean semver for build args and OCI labels (never a Docker tag)
#   IMAGE_TAG  → v-prefixed Docker tag for releases; empty skips version tag
#   EXTRA_TAGS → comma-separated additional tags (latest, next, nightly, etc.)
#

# ---------------------------------------------------------------------------
# Variables
# ---------------------------------------------------------------------------

variable "REGISTRY" {
  default = "ghcr.io/onetimesecret"
}

variable "DOCKERHUB_REPO" {
  default = "onetimesecret/onetimesecret"
}

variable "VERSION" {
  default = "dev"
}

variable "COMMIT_HASH" {
  default = "dev"
}

# Docker image tag for versioned releases (e.g. "v0.24.0-rc15").
# Empty for non-tag builds (nightly, branch push, manual dispatch) — only EXTRA_TAGS apply.
variable "IMAGE_TAG" {
  default = ""
}

# Comma-separated list of additional tags to apply (e.g. "latest,edge,nightly")
variable "EXTRA_TAGS" {
  default = ""
}

# "public" or "custom"
variable "REGISTRY_MODE" {
  default = "public"
}

variable "CUSTOM_REGISTRY" {
  default = ""
}

variable "PLATFORMS" {
  default = "linux/amd64"
}

# ---------------------------------------------------------------------------
# Functions
# ---------------------------------------------------------------------------

function "tags" {
  params = [suffix]
  # IMAGE_TAG (v-prefixed) → versioned Docker tag; empty → only EXTRA_TAGS
  # VERSION (clean semver) → build args and OCI labels only, never used as a Docker tag
  result = (
    equal(REGISTRY_MODE, "custom") && notequal(CUSTOM_REGISTRY, "") ? concat(
      notequal(IMAGE_TAG, "") ? ["${CUSTOM_REGISTRY}/onetimesecret/onetimesecret${suffix}:${IMAGE_TAG}"] : [],
      [for t in compact(split(",", EXTRA_TAGS)) :
        "${CUSTOM_REGISTRY}/onetimesecret/onetimesecret${suffix}:${trimspace(t)}"
      ]
    ) : concat(
      notequal(IMAGE_TAG, "") ? [
        "${REGISTRY}/onetimesecret${suffix}:${IMAGE_TAG}",
        "${DOCKERHUB_REPO}${suffix}:${IMAGE_TAG}",
      ] : [],
      flatten([
        [for t in compact(split(",", EXTRA_TAGS)) :
          "${REGISTRY}/onetimesecret${suffix}:${trimspace(t)}"
        ],
        [for t in compact(split(",", EXTRA_TAGS)) :
          "${DOCKERHUB_REPO}${suffix}:${trimspace(t)}"
        ],
      ])
    )
  )
}

# ---------------------------------------------------------------------------
# Groups
# ---------------------------------------------------------------------------

group "default" {
  targets = ["main"]
}

group "all" {
  targets = ["main", "s6", "lite", "caddy"]
}

group "ci" {
  targets = ["main", "s6", "lite"]
}

# ---------------------------------------------------------------------------
# Targets
# ---------------------------------------------------------------------------

# Abstract target: shared args and labels for all app images
target "_common" {
  args = {
    VERSION     = VERSION
    COMMIT_HASH = COMMIT_HASH
  }
  labels = {
    "org.opencontainers.image.source"  = "https://github.com/onetimesecret/onetimesecret"
    "org.opencontainers.image.version" = VERSION
    "org.opencontainers.image.licenses" = "MIT"
  }
}

# Shared base image (build toolchain + Node + Ruby + appuser)
# Not pushed to registry — consumed by other targets via contexts
target "base" {
  dockerfile = "docker/base.dockerfile"
  context    = "."
  platforms  = split(",", PLATFORMS)
}

# Main production image (single-process, entrypoint.sh)
target "main" {
  inherits   = ["_common"]
  dockerfile = "Dockerfile"
  context    = "."
  target     = "final"
  contexts   = {
    base = "target:base"
  }
  tags      = tags("")
  platforms = split(",", PLATFORMS)
  labels = {
    "org.opencontainers.image.title"       = "Onetime Secret"
    "org.opencontainers.image.description"  = "Keep passwords out of your inboxes and chat logs with links that work only one time."
  }
}

# S6 multi-process supervised image
target "s6" {
  inherits   = ["_common"]
  dockerfile = "Dockerfile"
  context    = "."
  target     = "final-s6"
  contexts   = {
    base = "target:base"
  }
  tags      = tags("-s6")
  platforms = split(",", PLATFORMS)
  labels = {
    "org.opencontainers.image.title"       = "Onetime Secret (S6)"
    "org.opencontainers.image.description"  = "Keep passwords out of your inboxes and chat logs with links that work only one time. Multi-process supervised container."
  }
}

# Lite all-in-one image (app + Redis, ephemeral)
target "lite" {
  inherits   = ["_common"]
  dockerfile = "docker/variants/lite.dockerfile"
  context    = "."
  contexts   = {
    main = "target:main"
  }
  tags      = tags("-lite")
  platforms = split(",", PLATFORMS)
  labels = {
    "org.opencontainers.image.title"       = "Onetime Secret (Lite)"
    "org.opencontainers.image.description"  = "Self-contained Onetime Secret with embedded Redis. Ephemeral by design."
  }
}

# Caddy TLS proxy (version-agnostic)
target "caddy" {
  dockerfile = "docker/variants/caddy.dockerfile"
  context    = "."
  tags       = tags("-caddy")
  platforms  = split(",", PLATFORMS)
  labels = {
    "org.opencontainers.image.title"       = "Onetime Secret (Caddy)"
    "org.opencontainers.image.description"  = "Caddy reverse proxy with automatic TLS for Onetime Secret."
  }
}
