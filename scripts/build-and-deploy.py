#!/usr/bin/env python3

"""
Git post-receive hook: Build and push OCI images with Podman.

Runs as a Gitolite hook. Derives image name from the repo.

Install:
    pip install GitPython
    podman login <registry>
    mkdir -p /opt/builds && chown <hook-user>:<hook-user> /opt/builds

Config:
    Repos that contain a .oci-build.json at their root get built on push.
    Repos without this file are silently skipped.

    Legacy .oci-build.json (plain podman build per variant):
    {
        "registry": "registry.example.com",
        "image_name": "myorg/myapp",
        "platforms": ["linux/amd64"],
        "variants": [
            {"suffix": "", "dockerfile": "Dockerfile", "target": ""},
            {"suffix": "-lite", "dockerfile": "docker/variants/lite.dockerfile", "target": ""},
            {"suffix": "-s6", "dockerfile": "Dockerfile", "target": "final-s6"}
        ]
    }

    Bake-aware .oci-build.json (shared base + build contexts):
    {
        "registry": "registry.example.com",
        "image_name": "myorg/myapp",
        "platforms": ["linux/amd64"],
        "base": {"dockerfile": "docker/base.dockerfile"},
        "variants": [
            {"suffix": "", "dockerfile": "Dockerfile", "target": "final"},
            {"suffix": "-s6", "dockerfile": "Dockerfile", "target": "final-s6"},
            {"suffix": "-lite", "dockerfile": "docker/variants/lite.dockerfile",
             "contexts": {"main": ""}}
        ]
    }

    When "base" is present:
      - The base image is built first (local only, not pushed)
      - All variants receive --build-context base=container-image://...
      - Variants with "contexts" also receive contexts from previously
        built variants (keyed by suffix, "" = main)
      - Variants are built in array order; declare dependencies before
        dependents

    Gitolite per-repo options (oci.registry, oci.image-name) override
    .oci-build.json values when present.

Usage:
    git remote add build git@buildhost:myapp
    git push build main
    git push build v1.0.0
"""

from __future__ import annotations

import json
import logging
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

from git import Repo
from git.exc import GitCommandError

# ─── Logging ─────────────────────────────────────────────────────────────────

logging.basicConfig(
    level=logging.INFO,
    format="→ %(message)s",
)
log = logging.getLogger("post-receive")


# ─── Configuration ───────────────────────────────────────────────────────────


def _gitolite_option(repo: Repo, key: str) -> str | None:
    """Read a gitolite per-repo option from git config.

    Gitolite stores 'option X = Y' as 'gitolite-options.X = Y'
    in the repo's git config.
    """
    try:
        return repo.git.config(f"gitolite-options.{key}").strip()
    except GitCommandError:
        return None


@dataclass
class BuildConfig:
    """Build configuration, loaded from build.json or derived from repo path."""

    registry: str
    image_name: str
    platforms: list[str]
    work_dir: Path
    variants: list[dict]
    base: dict | None = None

    @classmethod
    def load(cls, repo: Repo, rev: str) -> BuildConfig | None:
        """
        Load .oci-build.json from the pushed revision's tree.

        Returns None if the file doesn't exist (repo has no builds configured).
        Uses git-show to read the file directly from the object store —
        no checkout needed to decide whether to build.

        Gitolite per-repo options (oci.registry, oci.image-name) override
        values from .oci-build.json when present, keeping private
        infrastructure details out of the application repository.
        """
        repo_name = Path(repo.common_dir).name.removesuffix(".git")

        try:
            raw_json = repo.git.show(f"{rev}:.oci-build.json")
        except GitCommandError:
            return None  # file doesn't exist in this revision

        log.info("Found .oci-build.json in %s (%s)", repo_name, rev[:7])
        raw = json.loads(raw_json)

        # Gitolite options override .oci-build.json values
        registry = (
            _gitolite_option(repo, "oci.registry") or raw["registry"]
        )
        image_name = (
            _gitolite_option(repo, "oci.image-name")
            or raw.get("image_name", repo_name)
        )

        return cls(
            registry=registry,
            image_name=image_name,
            platforms=raw.get("platforms", ["linux/amd64"]),
            work_dir=Path(
                raw.get("work_dir", f"/opt/builds/{repo_name}-checkout")
            ),
            variants=raw.get(
                "variants",
                [
                    {"suffix": "", "dockerfile": "Dockerfile", "target": ""},
                ],
            ),
            base=raw.get("base"),
        )

    @property
    def image_base(self) -> str:
        return f"{self.registry}/{self.image_name}"

    @property
    def is_multi_platform(self) -> bool:
        return len(self.platforms) > 1

    @property
    def has_base(self) -> bool:
        return self.base is not None


# ─── Models ──────────────────────────────────────────────────────────────────


@dataclass
class PushRef:
    """A single ref update received by the post-receive hook."""

    old_rev: str
    new_rev: str
    refname: str

    @property
    def short_sha(self) -> str:
        return self.new_rev[:7]

    @property
    def is_delete(self) -> bool:
        return self.new_rev == "0" * 40

    @property
    def is_tag(self) -> bool:
        return self.refname.startswith("refs/tags/")

    @property
    def tag(self) -> str:
        return self.refname.removeprefix("refs/tags/")

    @property
    def branch(self) -> str:
        return self.refname.removeprefix("refs/heads/").replace("/", "-")

    @property
    def is_release(self) -> bool:
        return (
            self.is_tag and self.tag.startswith("v") and "-rc" not in self.tag
        )

    @property
    def is_rc(self) -> bool:
        return self.is_tag and "-rc" in self.tag

    def image_tags(self, base: str, suffix: str = "") -> list[str]:
        """
        Compute image tags:
            Release (v1.0.0)    → {version}, latest
            RC (v1.0.0-rc1)     → {version}, next
            Branch push         → {branch}, edge
        All pushes also get the short SHA tag.
        """
        full_base = f"{base}{suffix}"
        tags = [f"{full_base}:{self.short_sha}"]

        if self.is_release:
            tags += [f"{full_base}:{self.tag}", f"{full_base}:latest"]
        elif self.is_rc:
            tags += [f"{full_base}:{self.tag}", f"{full_base}:next"]
        else:
            tags += [f"{full_base}:{self.branch}", f"{full_base}:edge"]

        return tags


@dataclass
class BuildResult:
    """Outcome of a single variant build."""

    variant: str
    tags: list[str]
    success: bool
    error: str = ""


# ─── Podman interface ────────────────────────────────────────────────────────


def podman(*args: str) -> subprocess.CompletedProcess:
    """Run a podman command, logging and raising on failure.

    Redirects stdout to stderr so build output reaches the push
    client (git shows stderr as 'remote:' lines in the terminal).
    """
    cmd = ["podman", *args]
    log.info("  %s", " ".join(cmd))
    return subprocess.run(cmd, stdout=sys.stderr, check=True)


def build_context_args(build_contexts: dict[str, str]) -> list[str]:
    """Convert a {name: image} dict to --build-context CLI flags."""
    args = []
    for name, image in build_contexts.items():
        args += ["--build-context", f"{name}=container-image://{image}"]
    return args


def build_single_platform(
    config: BuildConfig,
    work_dir: Path,
    dockerfile: str,
    target: str,
    tags: list[str],
    build_args: dict[str, str],
    build_contexts: dict[str, str] | None = None,
) -> None:
    """Build for one platform and push all tags."""
    cmd = [
        "build",
        "--file",
        dockerfile,
        "--platform",
        config.platforms[0],
    ]
    for key, val in build_args.items():
        cmd += ["--build-arg", f"{key}={val}"]
    if target:
        cmd += ["--target", target]
    if build_contexts:
        cmd += build_context_args(build_contexts)
    for tag in tags:
        cmd += ["--tag", tag]
    cmd.append(str(work_dir))

    podman(*cmd)
    for tag in tags:
        podman("push", tag)


def build_multi_platform(
    config: BuildConfig,
    work_dir: Path,
    dockerfile: str,
    target: str,
    tags: list[str],
    build_args: dict[str, str],
    build_contexts: dict[str, str] | None = None,
) -> None:
    """Build a multi-arch manifest and push all tags."""
    manifest = tags[0]
    podman("manifest", "create", manifest)

    try:
        cmd = [
            "build",
            "--file",
            dockerfile,
            "--manifest",
            manifest,
        ]
        for key, val in build_args.items():
            cmd += ["--build-arg", f"{key}={val}"]
        if target:
            cmd += ["--target", target]
        if build_contexts:
            cmd += build_context_args(build_contexts)

        for platform in config.platforms:
            podman(*cmd, "--platform", platform, str(work_dir))

        for tag in tags:
            if tag != manifest:
                podman("tag", manifest, tag)
            podman("manifest", "push", "--all", tag, f"docker://{tag}")
    finally:
        podman("manifest", "rm", manifest)


# ─── Build orchestration ────────────────────────────────────────────────────


def checkout(repo: Repo, rev: str, dest: Path) -> None:
    """
    Export a revision from the bare repo into a working directory.

    Uses git-archive rather than checkout — avoids index contention
    in bare repos if two pushes arrive concurrently.

    Pipes git-archive directly to tar as raw bytes, avoiding any
    text encoding of the binary tar stream.
    """
    dest.mkdir(parents=True, exist_ok=True)
    git_archive = subprocess.Popen(
        ["git", "archive", "--format=tar", rev],
        stdout=subprocess.PIPE,
        cwd=repo.common_dir,
    )
    assert git_archive.stdout is not None
    subprocess.run(
        ["tar", "xf", "-", "-C", str(dest)],
        stdin=git_archive.stdout,
        check=True,
    )
    git_archive.stdout.close()
    rc = git_archive.wait()
    if rc != 0:
        raise subprocess.CalledProcessError(rc, "git archive")


def read_build_args(work_dir: Path, short_sha: str) -> dict[str, str]:
    """
    Collect build arguments from the working tree.

    Reads VERSION from package.json if present; always includes COMMIT_HASH.
    Projects without package.json simply skip the VERSION arg.
    """
    args = {"COMMIT_HASH": short_sha}

    pkg_path = work_dir / "package.json"
    if pkg_path.exists():
        version = json.loads(pkg_path.read_text()).get("version")
        if version:
            args["VERSION"] = version

    # Stamp commit hash file for Dockerfiles that COPY it
    (work_dir / ".commit_hash.txt").write_text(short_sha)

    return args


def build_base(
    config: BuildConfig, work_dir: Path, short_sha: str
) -> str:
    """
    Build the shared base image (local only, not pushed).

    Returns the local image name for use as a build context.
    """
    assert config.base is not None
    local_tag = f"ots-base:{short_sha}"
    dockerfile = config.base["dockerfile"]

    log.info("Building base image (%s)", dockerfile)

    cmd = [
        "build",
        "--file",
        dockerfile,
        "--platform",
        config.platforms[0],
        "--tag",
        local_tag,
        str(work_dir),
    ]
    podman(*cmd)
    return local_tag


def resolve_contexts(
    variant: dict,
    base_image: str | None,
    built_images: dict[str, str],
) -> dict[str, str] | None:
    """
    Resolve build contexts for a variant.

    Returns None if no contexts needed (legacy mode).
    Otherwise returns a dict of {context_name: local_image}.
    """
    contexts: dict[str, str] = {}

    # Inject base into all variants when base is configured
    if base_image:
        contexts["base"] = base_image

    # Inject inter-variant contexts (e.g. lite depends on main)
    variant_contexts = variant.get("contexts", {})
    for context_name, dep_suffix in variant_contexts.items():
        if dep_suffix not in built_images:
            raise RuntimeError(
                f"Variant '{variant.get('suffix', '')}' depends on "
                f"context '{context_name}' (suffix '{dep_suffix}') "
                f"which hasn't been built yet. "
                f"Check variant ordering in .oci-build.json."
            )
        contexts[context_name] = built_images[dep_suffix]

    return contexts or None


def build_variant(
    config: BuildConfig,
    ref: PushRef,
    work_dir: Path,
    variant: dict,
    build_contexts: dict[str, str] | None = None,
) -> BuildResult:
    """Build and push one image variant."""
    suffix = variant["suffix"]
    label = suffix or "main"
    tags = ref.image_tags(config.image_base, suffix)
    build_args = read_build_args(work_dir, ref.short_sha)

    log.info("Building %s (%d tags)", label, len(tags))

    build_fn = (
        build_multi_platform
        if config.is_multi_platform
        else build_single_platform
    )
    build_fn(
        config=config,
        work_dir=work_dir,
        dockerfile=variant["dockerfile"],
        target=variant.get("target", ""),
        tags=tags,
        build_args=build_args,
        build_contexts=build_contexts,
    )

    return BuildResult(variant=label, tags=tags, success=True)


# ─── Hook entrypoint ────────────────────────────────────────────────────────


def main() -> None:
    repo_path = Path.cwd()  # post-receive runs in the bare repo dir
    repo = Repo(repo_path)
    results: list[BuildResult] = []

    for line in sys.stdin:
        parts = line.strip().split()
        if len(parts) != 3:
            continue

        ref = PushRef(*parts)

        if ref.is_delete:
            continue

        # Check if this revision has a build config
        config = BuildConfig.load(repo, ref.new_rev)
        if config is None:
            log.info("No .oci-build.json, skipping...")
            continue  # no .oci-build.json, skip silently

        log.info("Push received: %s (%s)", ref.refname, ref.short_sha)
        log.info("Registry: %s  Image: %s", config.registry, config.image_name)

        if config.has_base:
            log.info("Mode: bake-aware (shared base + build contexts)")
        else:
            log.info("Mode: legacy (direct podman build per variant)")

        checkout(repo, ref.new_rev, config.work_dir)

        # Build shared base image if configured (local only, not pushed)
        base_image: str | None = None
        try:
            if config.has_base:
                try:
                    base_image = build_base(config, config.work_dir, ref.short_sha)
                    log.info("  Base image: %s", base_image)
                except subprocess.CalledProcessError as exc:
                    log.error("Base build failed: %s", exc)
                    results.append(
                        BuildResult(variant="base", tags=[], success=False, error=str(exc))
                    )
                    sys.exit(1)

            # Track built images by suffix for inter-variant context resolution
            built_images: dict[str, str] = {}

            for variant in config.variants:
                try:
                    build_contexts = resolve_contexts(
                        variant, base_image, built_images
                    )
                    result = build_variant(
                        config, ref, config.work_dir, variant,
                        build_contexts=build_contexts,
                    )
                    results.append(result)

                    # Record first tag for this suffix so dependents can reference it
                    suffix = variant["suffix"]
                    built_images[suffix] = result.tags[0]

                    log.info("  Pushed: %s", ", ".join(result.tags))
                except subprocess.CalledProcessError as exc:
                    label = variant["suffix"] or "main"
                    log.error("Build failed for %s: %s", label, exc)
                    results.append(
                        BuildResult(
                            variant=label,
                            tags=[],
                            success=False,
                            error=str(exc),
                        )
                    )
                    sys.exit(1)
        finally:
            # Clean up local base image
            if base_image:
                try:
                    podman("rmi", base_image)
                except subprocess.CalledProcessError:
                    log.warning("Failed to remove base image: %s", base_image)

    if results:
        log.info("─" * 50)
        for r in results:
            status = "ok" if r.success else f"FAILED: {r.error}"
            log.info("  %-8s %s", r.variant, status)
        log.info(
            "Done (%d/%d succeeded)",
            sum(r.success for r in results),
            len(results),
        )


if __name__ == "__main__":
    main()
