package service

import (
	"testing"

	"github.com/1Panel-dev/1Panel/agent/app/dto"
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
