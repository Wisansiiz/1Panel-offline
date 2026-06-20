package service

import (
	"context"
	"strings"

	"github.com/1Panel-dev/1Panel/agent/app/model"
	"github.com/1Panel-dev/1Panel/agent/utils/docker"
)

func (a AppService) offlineAvailableAppIDs() ([]uint, error) {
	apps, err := appRepo.GetBy()
	if err != nil {
		return nil, err
	}
	imageList, err := NewIImageService().ListAll()
	if err != nil {
		return nil, err
	}

	availableImages := make(map[string]struct{})
	for _, image := range imageList {
		for _, tag := range image.Tags {
			availableImages[normalizeImageName(tag)] = struct{}{}
		}
	}

	availableIDs := make([]uint, 0, len(apps))
	for _, app := range apps {
		installs, _ := appInstallRepo.ListBy(context.Background(), appInstallRepo.WithAppId(app.ID))
		if len(installs) > 0 || offlineAppHasAvailableVersion(app, availableImages) {
			availableIDs = append(availableIDs, app.ID)
		}
	}
	return availableIDs, nil
}

func offlineAppHasAvailableVersion(app model.App, availableImages map[string]struct{}) bool {
	for _, detail := range app.Details {
		if detail.DockerCompose == "" {
			continue
		}
		images, err := docker.GetImagesFromDockerCompose(nil, []byte(detail.DockerCompose))
		if err != nil {
			continue
		}
		if imagesAvailable(images, availableImages) {
			return true
		}
	}
	return false
}

func imagesAvailable(required []string, available map[string]struct{}) bool {
	if len(required) == 0 {
		return true
	}
	for _, image := range required {
		if _, ok := available[normalizeImageName(image)]; !ok {
			return false
		}
	}
	return true
}

func normalizeImageName(image string) string {
	image = strings.TrimSpace(strings.TrimPrefix(image, "docker.io/"))
	return strings.TrimPrefix(image, "library/")
}
