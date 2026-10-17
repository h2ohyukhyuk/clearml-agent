# ClearML Agent for a Linux Training Host

Run one ClearML Agent with Docker Compose. The agent watches a ClearML queue and launches separate training containers through the host Docker socket. Deploy ClearML Server separately; this project does not run its API, web UI, file server, or databases. You do not need to install or initialize `clearml-agent` on the host.

## Requirements

- Linux with Docker Engine and the Docker Compose plugin.
- A reachable ClearML Server and API credentials created in its web UI.
- An existing dataset directory and agent cache directory on the training host.
- For GPU training: an NVIDIA driver and NVIDIA Container Toolkit configured for Docker.
- A training image available to the host Docker daemon, either built locally or pulled from a registry.

The agent image installs `clearml-agent==3.0.3`, Git, and the Docker CLI. The training image is separate.

The `agent` service in `compose.yaml` uses `./dockers/agent` as its build context. Running `docker compose up -d --build` builds `dockers/agent/Dockerfile` into the image `clearml-local/agent:3.0.3-py3.12` and uses that image for the agent container. This container watches the queue and launches training containers through the host Docker socket. Training tasks use a separate image, such as the custom image built from `dockers/torch:2.9.1-py3.12-cu128/`.

## Agent container and training container

This project uses two separate Docker images with different roles:

| Docker sources | Image tag | Role | Build method |
| --- | --- | --- | --- |
| `dockers/agent/` | `clearml-local/agent:3.0.3-py3.12` | Runs the ClearML Agent worker service. It watches the queue, prepares tasks, and launches training containers. | Built by `docker compose up -d --build`. |
| `dockers/torch:2.9.1-py3.12-cu128/` | `clearml-local/torch:2.9.1-py3.12-cu128` | Runs the actual training code in a task's training container, with the GPUs and dataset mounts supplied by the agent. | Build separately on each training host, or distribute the built image. |

The worker service itself runs in the **agent container**. When it receives a training task, it launches a separate **training container** using the selected training image. The custom PyTorch image in `dockers/torch:2.9.1-py3.12-cu128/` is for this training container; it is not the image used to run the agent service.

Set `TRAINING_IMAGE=clearml-local/torch:2.9.1-py3.12-cu128` in `.env` to use this PyTorch image as the default for training tasks. A task can select another image through `task.set_base_docker()`. Both containers run on the training host, and the agent controls the training container through the host Docker socket. The training container is created by the agent and is not a service in this Compose file.

## Files

```text
compose.yaml                           Agent service
.env_bak                               Configuration template to publish on GitHub
.env                                   Local configuration and credentials (ignored by Git)
start.sh                               Start or rebuild the agent
cache/                                 Persistent agent caches (ignored by Git)
dockers/agent/                         Agent Dockerfile and entrypoint
dockers/torch:2.9.1-py3.12-cu128/       Training-container Dockerfile and build scripts
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

## Training Docker image

The agent launches training tasks in a separate Docker image. You can use the custom training image defined in `dockers/torch:2.9.1-py3.12-cu128/`.

For this locally built image, build it on each training server before submitting tasks:

```bash
cd '/home/j/projects_mldl/clearml-agent/dockers/torch:2.9.1-py3.12-cu128'
sudo docker build -t clearml-local/torch:2.9.1-py3.12-cu128 -f Dockerfile .
sudo docker image inspect clearml-local/torch:2.9.1-py3.12-cu128
```

Adjust the project path for your server. Set the matching tag in `.env`:

```dotenv
TRAINING_IMAGE=clearml-local/torch:2.9.1-py3.12-cu128
```

Apply the configuration with `sudo docker compose up -d --build` after existing tasks have finished or stopped. This selects the image as the agent's default training image; a task can override it with its own Docker image setting. The Compose build creates the agent image, so build the training image separately using the command above.

A successful local build registers the tag with that server's Docker daemon. You do not need to publish it to Docker Hub or another registry for that server to use it. For multi-node training, build or load the image on every participating server, or publish it to a registry that all servers can pull from. Images available from an accessible registry can be pulled rather than built locally. Private registries require Docker authentication on the training hosts.

### Select an image and pip packages in training code

`TRAINING_IMAGE` is the agent's default. Training code can select a different Docker image for an individual task and specify its Python packages before submitting the task:

```python
from clearml import Task

task = Task.init(project_name="training", task_name="my-training")
task.set_base_docker(
    docker_image="clearml-local/torch:2.9.1-py3.12-cu128"
)
task.set_packages("requirements.txt")
task.execute_remotely(queue_name="default")

# Training code continues here when the agent runs this task.
```

Keep `requirements.txt` in the training repository and use a path relative to the submission script's working directory. Include all required Python packages because `set_packages()` replaces the task's recorded package list. Alternatively, specify a complete list directly, for example `task.set_packages(["clearml", "torch==2.9.1", "numpy", "tqdm"])`, adjusting it to your project.

For an additional package alongside automatic dependency detection, call `Task.add_requirements("package-name", "==version")` before `Task.init()`. Use `set_packages()` when you want to explicitly define the complete requirements instead.

The agent uses the task's selected image in preference to its default, prepares the task's Python environment, and installs the recorded pip requirements before starting the training script. Setting requirements in code records instructions for remote execution; it does not install packages into the local submission process or rebuild the Docker image. Submit these settings before `execute_remotely()` so they are available when the agent prepares the environment. Package installation requires access to the configured package index or other package sources, and package versions must be compatible with the image's Python and CUDA environment.

Changing the task image or Python dependencies does not require changing the agent's `.env`. The selected image must still be available locally or pullable on every participating training server. For system libraries and tools that pip cannot provide, update the training Dockerfile and rebuild the image.

See the [ClearML Task SDK reference](https://clear.ml/docs/latest/docs/references/sdk/task/) for `set_base_docker()`, `set_packages()`, and `add_requirements()`.

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

## Multi-node DDP: prepare the agents

Before starting a multi-node DDP job, prepare every training server:

- Run one agent on each participating server and give each agent a unique `AGENT_WORKER_ID`.
- Configure the agents to watch the queue used by the distributed job. A dedicated queue, such as `ddp`, helps keep unrelated tasks separate.
- Set `WORKER_GPUS` on each server to the GPUs assigned to the job. This exposes GPUs to training containers; the training launcher must start the DDP processes.
- Make sure every server can reach the same ClearML Server. Use reachable server addresses instead of `localhost` when the management server is on another machine.
- Make sure the training servers can communicate with each other for DDP and NCCL. Host networking is already enabled, but routing and firewall rules must still allow that traffic.
- Prepare compatible GPU drivers, NVIDIA Container Toolkit, training images, repository access, and datasets on every server. Dataset paths inside containers must match the training configuration.

**You must keep the servers assigned to the DDP job free of other work.** For example, a two-node job needs an available agent on each of two servers. If server A starts its part while server B is still running another task, A waits for B and DDP training cannot proceed. The waiting job may eventually time out and fail. With this Compose setup, each agent picks up tasks independently, so check that all participating agents are idle before submitting the job and keep unrelated jobs off those servers during training. A dedicated queue helps separate tasks, but does not reserve the servers or GPUs for you.

The training repository should document the multi-node launcher, ranks, data sampling, and checkpoint handling. This agent project provides the execution environment; setting `WORKER_GPUS` alone does not configure DDP.

## GitHub publication

Commit `.env_bak` with empty credential fields as the configuration template. Never commit `.env`. The current ignore rules exclude `.env`, `cache/`, the local training Dockerfile/build scripts, and `dockers/agent/Dockerfile`. Include the agent Dockerfile before publishing a runnable checkout. Decide whether to publish the training-image sources or document an accessible image instead. Review the files to be committed and keep credentials and runtime caches out of the repository.

## References

- [ClearML Agent execution environments](https://clear.ml/docs/latest/docs/clearml_agent/clearml_agent_execution_env/)
- [ClearML Agent Docker sources](https://github.com/clearml/clearml-agent/tree/master/docker/agent)
