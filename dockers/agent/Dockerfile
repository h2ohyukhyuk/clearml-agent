FROM docker:29.8.2-cli AS dockercli
FROM python:3.12-slim-bookworm
RUN apt-get update \
    && apt-get install -y --no-install-recommends git ca-certificates \
    && rm -rf /var/lib/apt/lists/*
COPY --from=dockercli /usr/local/bin/docker /usr/local/bin/docker
RUN python -m pip install --no-cache-dir clearml-agent==3.0.3
COPY entrypoint.sh /usr/local/bin/agent-entrypoint
RUN chmod +x /usr/local/bin/agent-entrypoint
ENTRYPOINT ["/usr/local/bin/agent-entrypoint"]
