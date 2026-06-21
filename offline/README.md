# 1Panel 离线版构建与部署

> 本项目是 1Panel 社区版的非官方修改版，不属于 1Panel 官方发行版。
> 上游项目版权和商标归原权利人所有，离线版修改由本仓库独立维护。

离线版默认启用 `is_offline`，不会自动同步远程应用商店、检查在线升级、访问在线文档索引、同步公网 NTP、下载语言/GeoIP 资源或发送安装统计。应用启动使用 `docker compose --pull never`，镜像拉取 API 也会被服务端拒绝。

安装后会同时启用三层外网保护：

- Core/Agent 的 systemd 服务只允许回环、局域网、链路本地和 IPv6 ULA 地址；
- Docker 的 `DOCKER-USER`/`ip6tables` 规则拒绝容器访问公网；
- Web 界面通过 CSP 和导航拦截拒绝浏览器访问公网地址。

界面不再预置公网 npm、Composer、Debian 或 Ubuntu 软件源。需要相关功能时，必须手动填写企业内网镜像地址。

标准离线包内置 Docker Engine 29.6.0、配套的 containerd/runc，以及 Docker Compose 2.40.3。目标服务器没有 Docker 时，安装程序会自动安装并启动离线运行时。

## 应用商店策略

标准离线包只内置与基础镜像对应的 OpenResty/MySQL 应用定义。安装完成后，这些应用会自动显示在应用商店中，并可通过“已安装应用”统一管理。包内预置以下基础镜像：

- OpenResty：`1panel/openresty:1.27.1.2-2-3-focal`
- MySQL x86_64：`8.4.6`、`8.0.43`、`5.7.44`、`5.6.51`
- MySQL arm64：`8.4.6`、`8.0.43`

OpenResty/MySQL 不需要用户再次导入应用定义或镜像。其他应用仍需要同时准备应用定义和镜像；仅导入镜像无法可靠推断端口、密码、环境变量和数据目录，因此不会自动生成应用。

制作自定义发行包时，可以把应用定义放入：

```text
offline/catalog/apps/
├── redis/
│   ├── data.yml
│   ├── logo.png
│   ├── README.md
│   ├── 7.4.2/
│   │   ├── data.yml
│   │   └── docker-compose.yml
│   └── ...
offline/catalog/data.yaml
```

其他应用的镜像可以继续加入 `offline/images.tsv`：

```text
amd64	redis:7.4.2-alpine
arm64	redis:7.4.2-alpine
```

只有应用定义和所需镜像都已导入时，应用才会在离线应用商店中显示。

## 在线构建机制作离线包

```bash
./offline/build-bundle.sh amd64
./offline/build-bundle.sh arm64
```

输出位于 `dist/offline/`。构建机需要 Node.js、Go、Docker、curl，并允许访问 npm、Go modules、镜像仓库、Docker 官方下载站和 GitHub。

全部预置镜像会合并保存为 `images/images.tar`，共享镜像层只写入一次。

也可以直接使用 GitHub Actions：

- 推送到 `dev-v2`：生成 amd64、arm64 Artifact 并创建正式 Release；
- 推送 `offline-v*` 标签：自动创建 Release；
- Actions 页面支持手动指定构建版本。

Release 中每个架构直接提供一个 `.tar.gz` 文件：

```bash
sha256sum -c SHA256SUMS
tar -xzf 1panel-offline-*-linux-amd64.tar.gz
```

同一个 Release 还会提供可单独下载的应用导入包：

| 导入包 | 版本 | amd64 | arm64 |
|---|---:|:---:|:---:|
| MySQL 8 | `8.4.10` | ✓ | ✓ |
| MySQL 5 | `5.7.44` | ✓ | 不支持 |
| Redis | `7.4.9` | ✓ | ✓ |
| Java 8 | `1.8` | ✓ | ✓ |
| Java 17 | `17` | ✓ | ✓ |
| Java 21 | `21` | ✓ | ✓ |

文件名示例：

```text
1panel-app-mysql5-5.7.44-linux-amd64.tar.gz
1panel-app-redis-7.4.9-linux-arm64.tar.gz
1panel-app-java17-17-linux-amd64.tar.gz
```

每个导入包都包含固定版本的官方应用定义、对应架构的镜像归档、`MANIFEST`
和 `SHA256SUMS`。下载后可以直接导入：

```bash
tar -xzf 1panel-app-redis-7.4.9-linux-amd64.tar.gz
sudo 1panel-import-app ./1panel-app-redis-7.4.9-linux-amd64
```

应用定义固定取自 `1Panel-dev/appstore` 的 commit
`37797c685344fe97ee0819e019ddd744d1846257`，避免同一离线版本在不同时间构建出
不同的应用配置。

## 离线服务器安装

```bash
tar -xzf 1panel-offline-linux-amd64.tar.gz
cd 1panel-offline-linux-amd64
sudo ./install.sh
```

安装程序会校验文件和 CPU 架构，缺少 Docker 时自动安装包内运行时，然后安装 core/agent 并启动 systemd 服务。宿主机需要 Linux、systemd 和 iptables。

## 安装后增加应用

如果 Release 已提供所需版本，优先直接下载上面的独立应用导入包。只有需要其他
版本或其他应用时，才需要自行制作。

最简单可靠的方法是直接使用
[1Panel 官方应用仓库](https://github.com/1Panel-dev/appstore)中的应用定义，
再保存定义中指定的 Docker 镜像。下面以官方 `dev` 分支当前的 Redis `7.4.9`
为例。制作工作应在可以联网并已安装 Git、Docker 的 Linux 机器上进行。

### 1. 下载官方 Redis 应用定义

```bash
git clone --depth 1 --filter=blob:none --sparse \
  https://github.com/1Panel-dev/appstore.git
git -C appstore sparse-checkout set apps/redis
```

查看仓库目前提供的 Redis 版本：

```bash
find appstore/apps/redis -mindepth 1 -maxdepth 1 -type d -printf '%f\n'
```

### 2. 只复制需要的版本

```bash
REDIS_VERSION=7.4.9
mkdir -p "redis-bundle/apps/redis" redis-bundle/images

cp appstore/apps/redis/data.yml redis-bundle/apps/redis/
cp appstore/apps/redis/logo.png redis-bundle/apps/redis/
cp appstore/apps/redis/README.md redis-bundle/apps/redis/
if [[ -f appstore/apps/redis/README_en.md ]]; then
  cp appstore/apps/redis/README_en.md redis-bundle/apps/redis/
fi
cp -R "appstore/apps/redis/${REDIS_VERSION}" redis-bundle/apps/redis/
```

必须复制整个版本目录，不能只复制 `docker-compose.yml`。官方 Redis 定义还需要
该目录中的 `data.yml` 和 `conf/redis.conf`。

Redis 包不需要顶层 `data.yaml`，因为离线版已经存在 `Database` 标签定义；省略它
也可避免覆盖当前离线应用商店的标签目录。

### 3. 从官方 Compose 中读取镜像

不要手工猜镜像标签，直接读取 `docker-compose.yml`：

```bash
COMPOSE_FILE="redis-bundle/apps/redis/${REDIS_VERSION}/docker-compose.yml"
REDIS_IMAGE="$(awk '$1 == "image:" { print $2; exit }' "${COMPOSE_FILE}")"
test -n "${REDIS_IMAGE}"
echo "${REDIS_IMAGE}"
```

对于官方 Redis `7.4.9`，输出应为：

```text
redis:7.4.9
```

### 4. 下载并保存对应架构的镜像

x86_64 / amd64：

```bash
docker pull --platform linux/amd64 "${REDIS_IMAGE}"
docker image save \
  -o "redis-bundle/images/redis-${REDIS_VERSION}-amd64.tar" \
  "${REDIS_IMAGE}"
```

arm64：

```bash
docker pull --platform linux/arm64 "${REDIS_IMAGE}"
docker image save \
  -o "redis-bundle/images/redis-${REDIS_VERSION}-arm64.tar" \
  "${REDIS_IMAGE}"
```

一个离线包只放目标服务器对应架构的镜像，不要把两个架构使用同一标签的镜像放进
同一个 `redis-bundle`。

### 5. 检查并打包

```bash
test -f "redis-bundle/apps/redis/${REDIS_VERSION}/data.yml"
test -f "redis-bundle/apps/redis/${REDIS_VERSION}/docker-compose.yml"
test -f "redis-bundle/apps/redis/${REDIS_VERSION}/conf/redis.conf"
docker image inspect "${REDIS_IMAGE}" >/dev/null

tar -czf redis-bundle.tar.gz redis-bundle
```

最终结构类似：

```text
redis-bundle/
├── apps/
│   └── redis/
│       ├── data.yml
│       ├── logo.png
│       ├── README.md
│       └── 7.4.9/
│           ├── conf/
│           │   └── redis.conf
│           ├── data.yml
│           └── docker-compose.yml
└── images/
    └── redis-7.4.9-amd64.tar
```

### 6. 在离线服务器导入

将压缩包复制到离线服务器后执行：

```bash
tar -xzf redis-bundle.tar.gz
sudo 1panel-import-app ./redis-bundle
```

导入工具会复制应用定义、加载 `images/*.tar`，并重启 Agent 触发本地应用目录同步。

```bash
REDIS_VERSION=7.4.9
REDIS_IMAGE="$(
  awk '$1 == "image:" { print $2; exit }' \
    "redis-bundle/apps/redis/${REDIS_VERSION}/docker-compose.yml"
)"
sudo docker image inspect "${REDIS_IMAGE}" >/dev/null
sudo systemctl is-active 1panel-agent
```

刷新应用商店后即可安装 Redis。安装成功后，Redis 会进入“已安装应用”页面，
可执行启动、停止、重启和卸载。

## 卸载离线版

默认停止由应用商店管理的容器，卸载面板程序，并保留 `/opt/1panel` 下的数据和 Docker：

```bash
sudo 1panel-uninstall
# 等价命令
sudo 1pctl uninstall
```

删除全部 1Panel 数据：

```bash
sudo 1panel-uninstall --purge-data
```

如果 Docker 是由该离线包安装的，可同时删除 Docker/containerd 程序：

```bash
sudo 1panel-uninstall --remove-docker
```

卸载脚本不会删除安装前已经存在的 Docker。
