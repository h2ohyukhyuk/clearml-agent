# ClearML Agent for a Linux Training Host

Run one ClearML Agent with Docker Compose. The agent watches a ClearML queue and launches separate training containers through the host Docker socket. Deploy ClearML Server separately; this project does not run its API, web UI, file server, or databases. You do not need to install or initialize `clearml-agent` on the host.

## Requirements

- Linux with Docker Engine and the Docker Compose plugin.
- A reachable ClearML Server and API credentials created in its web UI.
- An existing dataset directory and agent cache directory on the training host.
- For GPU training: an NVIDIA driver and NVIDIA Container Toolkit configured for Docker.
- A training image available to the host Docker daemon, either built locally or pulled from a registry.

The agent image installs `clearml-agent==3.0.3`, Git, and the Docker CLI. The training image is separate.

## Files

```text
compose.yaml                           Agent service
.env_bak                               Configuration template to publish on GitHub
.env                                   Local configuration and credentials (ignored by Git)
start.sh                               Start or rebuild the agent
cache/                                 Persistent agent caches (ignored by Git)
dockers/agent/                         Agent Dockerfile and entrypoint
dockers/torch:2.9.1-py3.12-cu128/       Local training-image build files
```

## Configuration

Create your local configuration from the template after cloning the repository:

```bash
cp .env_bak .env
chmod 600 .env
```

Edit `.env` with the server addresses, credentials, and paths for your machine. Publish only `.env_bak` as the configuration template; keep `.env` out of Git. The template must contain no real API keys or Git credentials.

Use the following values as a starting point:

```dotenv
CLEARML_API_HOST=http://localhost:8008
CLEARML_WEB_HOST=http://localhost:8080
CLEARML_FILES_HOST=http://localhost:8081
CLEARML_API_ACCESS_KEY=
CLEARML_API_SECRET_KEY=
AGENT_HOST_DIR=/home/j/projects_mldl/clearml-agent
DATA_HOST_DIR=/home/j/database
DATA_CONTAINER_DIR=/home/j/database
AGENT_WORKER_ID=training-worker-1
AGENT_QUEUE=default
WORKER_GPUS=0,1
TRAINING_IMAGE=clearml-local/torch:2.9.1-py3.12-cu128
CLEARML_AGENT_GIT_USER=
CLEARML_AGENT_GIT_PASS=
CLEARML_AGENT_GIT_HOST=github.com
```

| Variable | Meaning and configuration |
| --- | --- |
| `CLEARML_API_HOST` | ClearML API URL, normally port `8008`. Used for task retrieval and status updates. |
| `CLEARML_WEB_HOST` | ClearML web UI URL, normally port `8080`. |
| `CLEARML_FILES_HOST` | ClearML file server URL, normally port `8081`, used for artifact and file transfers. |
| `CLEARML_API_ACCESS_KEY` | Access key generated in the ClearML web UI. Required; the entrypoint rejects an empty value. |
| `CLEARML_API_SECRET_KEY` | Matching secret key. Required; the entrypoint rejects an empty value. Keep it private. |
| `AGENT_HOST_DIR` | Absolute path to this project on the Docker host. Its `cache/` directory is mounted at `/root/.clearml` in the agent and configured for training-container cache mounts. Update it when moving the project. |
| `DATA_HOST_DIR` | Existing absolute dataset directory on the Docker host. Mounted read-only into both the agent and training containers. |
| `DATA_CONTAINER_DIR` | Absolute destination for that dataset mount inside containers. Training code and task arguments must use this path. It can differ from `DATA_HOST_DIR`. |
| `AGENT_WORKER_ID` | Worker identifier displayed in Workers & Queues. Defaults to `training-worker-1`; use a distinct ID for each worker. Also used in training-container labels. |
| `AGENT_QUEUE` | Queue the agent watches. Defaults to `default`; the agent creates it if missing. Tasks from any project can run here when submitted to this queue. |
| `WORKER_GPUS` | Host GPU indices exposed to training containers: `0` for one GPU or `0,1` for two. Set `cpu` for CPU-only execution. Exposing two GPUs does not automatically enable distributed training or run two tasks in parallel; the training code must configure multi-GPU use. Compose defaults to `cpu` if unset or empty. |
| `TRAINING_IMAGE` | Default Docker image for task execution. Defaults to `clearml-local/torch:2.9.1-py3.12-cu128`. A task can specify its own image. Local images must exist on every training host that uses them. |
| `CLEARML_AGENT_GIT_USER` | Git username for authenticated HTTPS repository access. Leave empty for public repositories. For GitHub, use your GitHub username. |
| `CLEARML_AGENT_GIT_PASS` | HTTPS Git credential, such as a GitHub personal access token (PAT). For private GitHub repositories, grant the token access to the required repositories with Contents read permission. Leave empty when authentication is unnecessary. |
| `CLEARML_AGENT_GIT_HOST` | Hostname to which Git credentials apply. Defaults to `github.com`; set your Git server hostname when using another service. |

Both the agent and its training containers use Linux host networking. `localhost` therefore refers to the training host: the supplied URLs work only when ClearML Server is reachable there on those ports. For a separate management host, replace all three URLs with addresses reachable from the training host. A server bound only to `127.0.0.1` cannot accept remote workers. Configure the server's advertised file URL, authentication, firewall, and TLS as appropriate for remote access.

The dataset mount is read-only. Put generated outputs in a writable location, and prepare datasets on the host if the training code would otherwise download them into the dataset mount. The agent does not validate dataset names or internal file structure. For example, a task can use `/home/j/database/mnist/MNIST/raw` when that directory exists under the configured mount.

Keep `.env` out of Git. Do not put tokens in Dockerfiles, image layers, repository URLs, or task arguments. Docker socket access gives the agent administrative control over the host Docker daemon.

## Start

1. Copy `.env_bak` to `.env` as shown above. Set the server URLs and API keys in `.env`, then adjust host paths, GPUs, and the image for your machine.
2. Create the cache directory and verify that the dataset directory already exists:

   ```bash
   cd /home/j/projects_mldl/clearml-agent
   mkdir -p cache
   test -d /home/j/database
   ```

   Use your configured paths if they differ. Compose disables automatic creation of bind-mount source directories.

3. If using the included local training-image sources, build the image once:

   ```bash
   cd '/home/j/projects_mldl/clearml-agent/dockers/torch:2.9.1-py3.12-cu128'
   bash build.sh
   ```

   Skip this if the image is already available. On another host, build it again or transfer/pull it. ClearML Server does not store or distribute Docker images. The current `.gitignore` excludes the local training Dockerfile and build scripts, so a fresh GitHub checkout needs those sources separately or an accessible replacement image.

4. Start the agent:

   ```bash
   cd /home/j/projects_mldl/clearml-agent
   sudo docker compose up -d --build
   sudo docker compose logs --tail 100 -f agent
   sudo docker compose ps
   ```

   Omit `sudo` if your user has Docker access. Alternatively, run `bash start.sh` as a user with Docker access. Check for `training-worker-1` (or your configured ID) under **Workers & Queues** in ClearML. Submit tasks to the configured queue to execute them. GPU-enabled tasks must also select CUDA in their own training settings.

## Apply changes

Wait for running tasks to finish, or stop them and confirm termination, before changing the worker configuration:

```bash
sudo docker compose up -d --build
```

## Stop

First stop active tasks in ClearML and confirm they have exited. Then run:

```bash
sudo docker compose down --timeout 120
```

Training containers are created separately and are not Compose services. `compose down` does not guarantee that they stop. After a failure, inspect containers for the configured worker ID:

```bash
sudo docker ps -a --filter label=clearml.worker=training-worker-1
```

Check their associated tasks and stop/remove only the containers that need cleanup. Agent caches remain in `AGENT_HOST_DIR/cache`.

## Multiple workers

Multiple hosts can watch the same queue. To run multiple copies on one host, give each deployment a separate Compose project name, worker ID, and cache directory. The Compose file sets `name: clearml-worker`; override it with `docker compose -p <unique-name> ...` for each deployment. Assign GPUs appropriately for the workloads.

## GitHub publication

Commit `.env_bak` with empty credential fields as the configuration template. Never commit `.env`. The current ignore rules exclude `.env`, `cache/`, the local training Dockerfile/build scripts, and `dockers/agent/Dockerfile`. Include the agent Dockerfile before publishing a runnable checkout. Decide whether to publish the training-image sources or document an accessible image instead. Review the files to be committed and keep credentials and runtime caches out of the repository.

## References

- [ClearML Agent execution environments](https://clear.ml/docs/latest/docs/clearml_agent/clearml_agent_execution_env/)
- [ClearML Agent Docker sources](https://github.com/clearml/clearml-agent/tree/master/docker/agent)
