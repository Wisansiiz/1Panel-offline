package helper

import (
	"encoding/json"
	"testing"

	"github.com/1Panel-dev/1Panel/core/app/dto"
	"github.com/1Panel-dev/1Panel/core/global"
)

func TestLoadMenusExcludesAIInOfflineMode(t *testing.T) {
	oldConf := global.CONF
	t.Cleanup(func() {
		global.CONF = oldConf
	})
	global.CONF.Base.IsOffline = true

	var menus []dto.ShowMenu
	if err := json.Unmarshal([]byte(LoadMenus()), &menus); err != nil {
		t.Fatal(err)
	}
	for _, menu := range menus {
		if menu.Label == "AI-Menu" {
			t.Fatal("offline menu must not include AI")
		}
	}
}

func TestRemoveMenuByLabelPreservesOtherMenus(t *testing.T) {
	menus := []dto.ShowMenu{
		{Label: "App-Menu"},
		{Label: "AI-Menu"},
		{Label: "Website-Menu"},
	}

	filtered := RemoveMenuByLabel(menus, "AI-Menu")
	if len(filtered) != 2 || filtered[0].Label != "App-Menu" || filtered[1].Label != "Website-Menu" {
		t.Fatalf("unexpected filtered menus: %#v", filtered)
	}
}
