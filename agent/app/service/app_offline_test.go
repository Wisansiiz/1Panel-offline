package service

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/1Panel-dev/1Panel/agent/app/dto"
	"github.com/1Panel-dev/1Panel/agent/app/dto/request"
	"github.com/1Panel-dev/1Panel/agent/app/model"
	apptask "github.com/1Panel-dev/1Panel/agent/app/task"
	"github.com/1Panel-dev/1Panel/agent/constant"
	"github.com/1Panel-dev/1Panel/agent/global"
	"github.com/1Panel-dev/1Panel/agent/utils/re"
	"github.com/sirupsen/logrus"
	"gopkg.in/yaml.v3"
)

func TestImagesAvailableNormalizesDockerHubNames(t *testing.T) {
	available := map[string]struct{}{
		normalizeImageName("docker.io/library/mysql:8.4.6"): {},
	}
	if !imagesAvailable([]string{"mysql:8.4.6"}, available) {
		t.Fatal("expected Docker Hub aliases to match")
	}
}

func TestImagesAvailableRequiresEveryComposeImage(t *testing.T) {
	available := map[string]struct{}{
		normalizeImageName("mysql:8.4.6"): {},
	}
	if imagesAvailable([]string{"mysql:8.4.6", "redis:7"}, available) {
		t.Fatal("expected app to remain hidden while a required image is missing")
	}
}

func TestOfflineDetailAvailableMatchesExactImportedTag(t *testing.T) {
	re.Init()
	detail := model.AppDetail{
		DockerCompose: "services:\n  mysql:\n    image: mysql:8.4.6\n",
	}
	available := map[string]struct{}{
		normalizeImageName("docker.io/library/mysql:8.4.6"): {},
	}
	if !offlineDetailAvailable(detail, available) {
		t.Fatal("expected the version to be available when its exact image tag exists")
	}
	if offlineDetailAvailable(detail, map[string]struct{}{normalizeImageName("mysql:8.0.43"): {}}) {
		t.Fatal("expected the version to be hidden when only another image tag exists")
	}
}

func TestOfflineDetailAvailableResolvesJavaVersion(t *testing.T) {
	re.Init()
	detail := model.AppDetail{
		Version:       "17",
		DockerCompose: "services:\n  java:\n    image: 1panel/java:${JAVA_VERSION}\n",
	}
	available := map[string]struct{}{
		normalizeImageName("1panel/java:17"): {},
	}
	if !offlineDetailAvailable(detail, available) {
		t.Fatal("expected Java compose image to resolve from the app version")
	}
}

func TestOfflineCatalogTagDataCanBeParsed(t *testing.T) {
	var catalog struct {
		Extra dto.ExtraProperties `yaml:"additionalProperties"`
	}
	data := []byte("additionalProperties:\n  version: v1\n  tags:\n    - key: Database\n      name: 数据库\n      sort: 20\n      locales:\n        en: Database\n")
	if err := yaml.Unmarshal(data, &catalog); err != nil {
		t.Fatal(err)
	}
	if len(catalog.Extra.Tags) != 1 || catalog.Extra.Tags[0].Key != "Database" {
		t.Fatalf("unexpected parsed catalog: %#v", catalog.Extra)
	}
}

func TestCopyDataUsesImportedRemoteAppResourcesOffline(t *testing.T) {
	oldConf := global.CONF
	oldDir := global.Dir
	t.Cleanup(func() {
		global.CONF = oldConf
		global.Dir = oldDir
	})

	rootDir := t.TempDir()
	global.CONF.Base.IsOffline = true
	global.Dir.AppResourceDir = filepath.Join(rootDir, "resource", "apps")
	global.Dir.RemoteAppResourceDir = filepath.Join(global.Dir.AppResourceDir, constant.AppResourceRemote)
	global.Dir.AppInstallDir = filepath.Join(rootDir, "apps")

	resourceDir := filepath.Join(global.Dir.RemoteAppResourceDir, "redis", "7.4.2")
	if err := os.MkdirAll(filepath.Join(resourceDir, "conf"), constant.DirPerm); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(resourceDir, "docker-compose.yml"), []byte("services: {}\n"), constant.FilePerm); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(resourceDir, "conf", "redis.conf"), []byte("appendonly yes\n"), constant.FilePerm); err != nil {
		t.Fatal(err)
	}

	app := model.App{Key: "redis", Resource: constant.AppResourceRemote}
	detail := model.AppDetail{Version: "7.4.2"}
	install := &model.AppInstall{
		Name:          "redis",
		App:           app,
		DockerCompose: "services:\n  redis:\n    image: redis:7.4.2\n",
	}
	req := request.AppInstallCreate{Name: "redis", Params: map[string]interface{}{"PANEL_APP_PORT_HTTP": 6379}}
	testTask := &apptask.Task{Logger: logrus.New()}

	if err := copyData(testTask, app, detail, install, req); err != nil {
		t.Fatal(err)
	}

	composePath := filepath.Join(global.Dir.AppInstallDir, "redis", "redis", "docker-compose.yml")
	compose, err := os.ReadFile(composePath)
	if err != nil {
		t.Fatal(err)
	}
	if string(compose) != install.DockerCompose {
		t.Fatalf("unexpected compose content: %s", compose)
	}
	if _, err = os.Stat(filepath.Join(global.Dir.AppInstallDir, "redis", "redis", "conf", "redis.conf")); err != nil {
		t.Fatal(err)
	}
}
