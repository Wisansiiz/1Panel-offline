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

标准离线包不内置应用目录，首次安装后的应用商店为空。包内仍预置以下基础镜像：

- OpenResty：`1panel/openresty:1.27.1.2-2-3-focal`
- MySQL x86_64：`8.4.6`、`8.0.43`、`5.7.44`、`5.6.51`
- MySQL arm64：`8.4.6`、`8.0.43`

用户导入对应的 OpenResty/MySQL 应用定义后，可以直接使用预置镜像，不需要再次导入镜像。其他应用需要同时准备应用定义和镜像。

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

## 离线服务器安装

```bash
tar -xzf 1panel-offline-linux-amd64.tar.gz
cd 1panel-offline-linux-amd64
sudo ./install.sh
```

安装程序会校验文件和 CPU 架构，缺少 Docker 时自动安装包内运行时，然后安装 core/agent 并启动 systemd 服务。宿主机需要 Linux、systemd 和 iptables。

## 安装后增加应用

准备一个目录：

```text
redis-bundle/
├── apps/
│   └── redis/
│       ├── data.yml
│       ├── logo.png
│       └── 7.4.2/
│           ├── data.yml
│           └── docker-compose.yml
├── data.yaml
└── images/
    └── redis-7.4.2.tar
```

复制到离线服务器并执行：

```bash
sudo 1panel-import-app ./redis-bundle
```

导入工具会复制应用定义、加载 `images/*.tar`，并重启 Agent 触发本地应用目录同步。
