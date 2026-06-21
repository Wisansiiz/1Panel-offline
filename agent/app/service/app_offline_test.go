package service

import (
	"testing"

	"github.com/1Panel-dev/1Panel/agent/app/dto"
	"github.com/1Panel-dev/1Panel/agent/app/model"
	"github.com/1Panel-dev/1Panel/agent/utils/re"
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
