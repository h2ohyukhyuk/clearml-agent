#!/usr/bin/env bash
set -euo pipefail
: "${CLEARML_API_ACCESS_KEY:?Set CLEARML_API_ACCESS_KEY in .env}"
: "${CLEARML_API_SECRET_KEY:?Set CLEARML_API_SECRET_KEY in .env}"
: "${CLEARML_API_HOST:?Set the management server API URL in .env}"
if [[ "$CLEARML_API_HOST" == *SET_SERVER_ADDRESS* ]]; then
    echo 'Set management server URLs in .env first (localhost is only for same-PC testing).' >&2
    exit 1
fi
docker info >/dev/null
# Validate the source on the learning host through the bind mounted data directory.
if [[ ! -d "$DATA_CONTAINER_DIR" ]]; then
    echo 'DATA_HOST_DIR must be an existing dataset directory on the learning host.' >&2
    exit 1
fi
# JSON encoding preserves spaces and quotes in directory names.
export CLEARML_AGENT__AGENT__EXTRA_DOCKER_ARGUMENTS="$(python - <<'PYARGS'
import json, os
print(json.dumps([
    "--network=host",
    "--volume=" + os.environ["DATA_HOST_DIR"] + ":" + os.environ["DATA_CONTAINER_DIR"] + ":ro",
]))
PYARGS
)"
# Images may also be specified per Task; the configured image is the default.
args=(daemon --foreground --queue "$AGENT_QUEUE" --create-queue --force-current-version)
if [[ "$WORKER_GPUS" == cpu ]]; then
    args+=(--cpu-only)
else
    args+=(--gpus "$WORKER_GPUS")
fi
exec clearml-agent "${args[@]}" --docker "$TRAINING_IMAGE"
