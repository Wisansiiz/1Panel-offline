package service

import (
	"context"
	"fmt"
	"strings"

	"github.com/1Panel-dev/1Panel/agent/app/model"
	"github.com/1Panel-dev/1Panel/agent/utils/docker"
)

func (a AppService) offlineAvailableAppIDs() ([]uint, error) {
	apps, err := appRepo.GetBy()
	if err != nil {
		return nil, err
	}
	availableImages, err := offlineAvailableImages()
	if err != nil {
		return nil, err
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

func offlineAvailableImages() (map[string]struct{}, error) {
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
	return availableImages, nil
}

func offlineAvailableDetails(details []model.AppDetail) ([]model.AppDetail, error) {
	availableImages, err := offlineAvailableImages()
	if err != nil {
		return nil, err
	}
	result := make([]model.AppDetail, 0, len(details))
	for _, detail := range details {
		if offlineDetailAvailable(detail, availableImages) {
			result = append(result, detail)
		}
	}
	return result, nil
}

func offlineDetailAvailable(detail model.AppDetail, availableImages map[string]struct{}) bool {
	if detail.DockerCompose == "" {
		return false
	}
	env := []byte(fmt.Sprintf("JAVA_VERSION=%s\n", detail.Version))
	images, err := docker.GetImagesFromDockerCompose(env, []byte(detail.DockerCompose))
	return err == nil && imagesAvailable(images, availableImages)
}

func offlineAppHasAvailableVersion(app model.App, availableImages map[string]struct{}) bool {
	for _, detail := range app.Details {
		if offlineDetailAvailable(detail, availableImages) {
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
