ARG RUBY_IMAGE_TAG=3.4.13-bookworm@sha256:a3d6cdfcefbf681f482be2ad848207f42193745d35695abe3a56327f45bdb515
FROM docker.io/library/ruby:${RUBY_IMAGE_TAG}

RUN apt-get update && \
    apt-get install -y --no-install-recommends libpq-dev libsqlite3-dev sudo && \
    rm -rf /var/lib/apt/lists/* && \
    groupadd --gid 1000 vscode && \
    useradd --uid 1000 --gid vscode --create-home --shell /bin/bash vscode && \
    printf '%s\n' 'vscode ALL=(root) NOPASSWD:ALL' > /etc/sudoers.d/vscode && \
    chmod 0440 /etc/sudoers.d/vscode

USER vscode
