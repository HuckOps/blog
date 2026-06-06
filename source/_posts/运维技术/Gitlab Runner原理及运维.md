---
title: Gitlab Runner原理及运维
date: 2026-03-20 15:55:14
categories: 运维技术
---

在生产项目中，所有可执行文件和项目源码包都不是由开发人员在本地手动构建的，其主要原因有以下几点：

1. 本地构建的产物可能和线上环境不一致，可能会出现奇怪的问题。
2. 针对于微服务来说，一次发版可能会涉及到多个服务，每个服务都需要手动构建，这会增加运维成本。

所以针对这一问题，Gitlab Pipeline 可以将项目构建以及其他一些流程化操作使用流水线的方式进行自动化。

# Gitlab CI 原理

老规矩，要了解一个产品的原理首先要从架构入手。我们先来看一下 Gitlab CI 的工作流。

![1780765077465.png](https://s3.huckops.xyz/1780765077465.png)

## 横向理解

从工作流的过程图可以看出，Gitlab Runner 的架构主要分为三部分：

1. Gitlab: 即为 Gitlab 的主站，负责管理项目的代码仓库、项目配置、构建触发等。
2. Runner：Gitlab Runner 的客户端工具，负责启动任务。
3. Executor：执行器，主要完成 Gitlab CI 脚本中定义的任务。

其简化的架构可以理解为：

```
Gitlab ------> Runner(任务管理器) ------> Executor(任务执行器)
```

## 纵向理解

### 初始化阶段

Gitbal Runner 携带 token 向 Gitlab 注册，注册成功后，Gitlab 会返回一个唯一的 ID，Runner 会将这个 ID 存储在本地。

```
# gitlab-runner register --url https://gitlab.com/ --registration-token <token>
Runtime platform                                    arch=amd64 os=linux pid=2509 revision=07e534ba version=18.9.0
Running in system-mode.

Enter the GitLab instance URL (for example, https://gitlab.com/):
[https://gitlab.com/]:
Enter the registration token:
[token]:
Enter a description for the runner:
[debian]:
Enter tags for the runner (comma-separated):

Enter optional maintenance note for the runner:

WARNING: Support for registration tokens and runner parameters in the 'register' command has been deprecated in GitLab Runner 15.6 and will be replaced with support for authentication tokens. For more information, see https://docs.gitlab.com/ci/runners/new_creation_workflow/
Registering runner... succeeded                     correlation_id=9df253558c3d5e55-SJC runner=XyxCKGHg9 runner_name=debian
Enter an executor: shell, ssh, virtualbox, docker, docker-windows, custom, parallels, docker+machine, kubernetes, docker-autoscaler, instance:
docker
Enter the default Docker image (for example, ruby:3.3):
debian:13.0
Runner registered successfully. Feel free to start it, but if it's running already the config should be automatically reloaded!

Configuration (with the authentication token) was saved in "/etc/gitlab-runner/config.toml"
```

### 运行阶段

Gitlab Runner 在运行阶段，循环监听 Gitlab 端发送的任务。当监听到有自己的任务时将通知 Executor 执行 CI 脚本，并将运行日志及运行结果回报给 Gitlab。

# 常见 Runner 模式

## docker 模式

在使用 docker 模式时，CI 运行时会在本地运行一个 docker 容器运行 CI 脚本。针对于普通类型的编译（如 npm build，go build 等），直接在容器中执行即可。一下为一个简单的 docker 模式下编译的配置：

```yaml
stages:
  - build

build:
  tags:
    - shared
  stage: build
  image: node:16-alpine

  before_script:
    - npm install

  script:
    - npm run build
    - tar -czvf $CI_PROJECT_NAME-$CI_COMMIT_SHA8x.tar.gz dist

  artifacts:
    paths:
      - $CI_PROJECT_NAME-$CI_COMMIT_SHA8x.tar.gz
    when: always
    expire_in: 1 hour
```

可以看到，这里直接在 runner 上运行了一个 node:16-alpine 的 docker 容器，容器中执行了 npm install 和 npm run build 命令，最后将编译产生的 dist 目录打包成 tar.gz 文件暴露给用户。

但是可以考虑一个问题，如果编译的目标项目是需要打包成 docker 镜像，直接这样可以吗？

我们可以尝试用以下脚本进行一次 CI 构建：

```yaml
stages:
  - build

variables:
  DOCKER_TLS_CERTDIR: ""
  IMAGE_NAME: my-golang-app
  IMAGE_TAG: $CI_COMMIT_SHORT_SHA
  DOCKERFILE_PATH: ./Dockerfile

build-docker-image:
  tags:
    - shared
  stage: build
  image: docker:latest
  script:
    - docker info
    - docker build -t $IMAGE_NAME:$IMAGE_TAG -f $DOCKERFILE_PATH .
    - docker images | grep $IMAGE_NAME
  artifacts:
    paths:
      - build.log
    when: always
    expire_in: 1 hour
```

触发构建后，会发现 CI 抛出了一段错误：

```
$ docker info
Client:
 Version:    29.3.0
 Context:    default
 Debug Mode: false
 Plugins:
  buildx: Docker Buildx (Docker Inc.)
    Version:  v0.32.1
    Path:     /usr/local/libexec/docker/cli-plugins/docker-buildx
  compose: Docker Compose (Docker Inc.)
    Version:  v5.1.0
    Path:     /usr/local/libexec/docker/cli-plugins/docker-compose
Server:
failed to connect to the docker API at tcp://docker:2375: lookup docker on 8.8.8.8:53: no such host
```

docker 拉起的 docker 容器并非是一个 docker 的完整体，其本质只是一个 docker 的客户端。从 docker 的原理我们可以知道，docker 是由 docker daemon 和 docker client 组成，docker daemon 负责管理 docker 容器，docker client 负责与 docker daemon 通信，在默认情况下，client 是通过 sock 与 docker daemon 通信的。所以，在这里我们需要对 Runner 进行配置，将本机 docker 的 sock 挂载给容器，让拉起的 CI docker 容器可以操作本机的 Docker daemon。

```toml
[[runners]]
  name = "debian"
  url = "https://gitlab.com/"
  id = 5
  token = ""
  token_obtained_at = 2026-03-20T06:12:02Z
  token_expires_at = 0001-01-01T00:00:00Z
  executor = "docker"
  [runners.cache]
    MaxUploadedArchiveSize = 0
    [runners.cache.s3]
    [runners.cache.gcs]
    [runners.cache.azure]
  [runners.docker]
    tls_verify = false
    image = "debian:13"
    privileged = false
    disable_entrypoint_overwrite = false
    oom_kill_disable = false
    disable_cache = false
    volumes = ["/cache", "/var/run/docker.sock:/var/run/docker.sock"]
    shm_size = 0
    network_mtu = 0
```

这就是典型的 Docker in Docker 模式（DinD）。

## kubernetes 模式

kubernetes 模式和 docker 类似，但是 kubernetes 只需要在任何可以访问到 api server 的节点上运行 Runner，而 Docker 模式是需要在每个节点上运行一个 Runner 的。

无论是使用 docker 还是 kubernetes 模式，使用的 CI 脚本理论上都是一样的，而且一样需要配置 Docker daemon 的 sock 挂载。

```toml
[[runners]]
  name = "k8s"
  url = "https://gitlab.com/"
  id = 5
  token = ""
  token_obtained_at = 2026-03-20T07:04:17Z
  token_expires_at = 0001-01-01T00:00:00Z
  executor = "kubernetes"
  [runners.cache]
    MaxUploadedArchiveSize = 0
    [runners.cache.s3]
    [runners.cache.gcs]
    [runners.cache.azure]
  [runners.kubernetes]
    host = "https://127.0.0.1:6443"
    cert_file = "/root/k8s/admin.crt"
    key_file = "/root/k8s/admin.key"
    ca_file = "/root/k8s/ca.crt"
    bearer_token_overwrite_allowed = false
    image = "debian:13"
    namespace = "default"
    namespace_overwrite_allowed = ""
    namespace_per_job = false
    node_selector_overwrite_allowed = ""
    node_tolerations_overwrite_allowed = ""
    pod_labels_overwrite_allowed = ""
    service_account_overwrite_allowed = ""
    pod_annotations_overwrite_allowed = ""
    [runners.kubernetes.init_permissions_container_security_context]
      [runners.kubernetes.init_permissions_container_security_context.capabilities]
    [runners.kubernetes.build_container_security_context]
      [runners.kubernetes.build_container_security_context.capabilities]
    [runners.kubernetes.helper_container_security_context]
      [runners.kubernetes.helper_container_security_context.capabilities]
    [runners.kubernetes.service_container_security_context]
      [runners.kubernetes.service_container_security_context.capabilities]
    [runners.kubernetes.volumes]
      [[runners.kubernetes.volumes.host_path]]
        name = "docker-sock"
        mount_path = "/var/run/docker.sock"
        host_path = "/var/run/docker.sock"
        read_only = false
    [runners.kubernetes.dns_config]
```

**注意：Runner 配置不支持使用 kubeconfig 文件，只能使用 cert_file、key_file、ca_file 参数配置。证书需要进行 base64 编码。**

```bash
echo "cert" | base64 -d > admin.crt
```
