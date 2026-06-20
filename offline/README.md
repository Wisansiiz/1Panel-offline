# 1Panel 离线版构建与部署

> 本项目是 1Panel 社区版的非官方修改版，不属于 1Panel 官方发行版。
> 上游项目版权和商标归原权利人所有，离线版修改由本仓库独立维护。

离线版默认启用 `is_offline`，不会自动同步远程应用商店、检查在线升级、访问在线文档索引、同步公网 NTP、下载语言/GeoIP 资源或发送安装统计。应用启动使用 `docker compose --pull never`，镜像拉取 API 也会被服务端拒绝。

## 内置镜像

- OpenResty：`1panel/openresty:1.27.1.2-2-3-focal`
- MySQL x86_64：`8.4.6`、`8.0.43`、`5.7.44`、`5.6.51`
- MySQL arm64：`8.4.6`、`8.0.43`

## 准备应用目录

构建脚本默认从官方 `https://github.com/1Panel-dev/appstore.git` 获取完整社区应用目录和标签数据。也可以提前把仓库的 `apps/` 与 `data.yaml` 放入 `offline/catalog/`，避免构建时重复下载：

```text
offline/catalog/apps/
├── mysql/
│   ├── data.yml
│   ├── logo.png
│   ├── README.md
│   ├── 8.4.6/
│   │   ├── data.yml
│   │   └── docker-compose.yml
│   └── ...
└── openresty/
    └── ...
offline/catalog/data.yaml
```

面板会按官方应用 key 导入完整社区应用目录，因此 OpenResty、MySQL 等仍会自动集成网站和数据库菜单。应用商店根据当前 Docker 中已有的镜像动态过滤应用：导入一个应用所需的全部镜像后，该应用会自动出现；未导入镜像的应用保持隐藏。

## 在线构建机制作离线包

```bash
./offline/build-bundle.sh amd64
./offline/build-bundle.sh arm64
```

输出位于 `dist/offline/`。构建机需要 Node.js、Go、Docker，并允许访问 npm、Go modules 和镜像仓库。

也可以直接使用 GitHub Actions：

- 推送到 `dev-v2`：生成 amd64、arm64 工作流 Artifact；
- 推送 `offline-v*` 标签：自动创建 Release；
- Actions 页面支持手动指定构建版本。

Release 中的大文件会被拆分为 `.part-*`，恢复方式：

```bash
cat 1panel-offline-*.tar.gz.part-* > 1panel-offline.tar.gz
sha256sum -c SHA256SUMS
```

## 离线服务器安装

```bash
tar -xzf 1panel-offline-linux-amd64.tar.gz
cd 1panel-offline-linux-amd64
sudo ./install.sh
```

安装程序会校验文件、安装 core/agent、复制本地应用目录、自动执行 `docker image load`，并启动 systemd 服务。

## 导入其他应用镜像

可通过 1Panel「容器 → 镜像 → 导入镜像」或命令行导入：

```bash
docker image load -i application-images.tar
```

刷新应用商店后，镜像齐全的应用会显示并可安装。应用定义仍需预先包含在离线包的完整社区应用目录中。
