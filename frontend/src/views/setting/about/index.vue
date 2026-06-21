<template>
    <div>
        <LayoutContent v-loading="loading" :title="$t('setting.about')" :divider="true">
            <template #main>
                <div style="text-align: center; margin-top: 20px">
                    <div style="justify-self: center" class="logo">
                        <img
                            v-if="themeConfig.logo && !logoLoadFailed"
                            style="width: 80px"
                            :src="`/api/v2/images/logo?t=${Date.now()}`"
                            @error="logoLoadFailed = true"
                            alt=""
                        />
                        <PrimaryLogo v-else />
                    </div>
                    <h3 class="description">{{ themeConfig.title || $t('setting.description') }}</h3>
                    <div class="flex justify-center">
                        <SystemUpgrade class="upgrade" />
                    </div>
                </div>
            </template>
        </LayoutContent>
    </div>
</template>

<script lang="ts" setup>
import { getSystemAvailable } from '@/api/modules/setting';
import { onMounted, ref } from 'vue';
import SystemUpgrade from '@/components/system-upgrade/index.vue';
import PrimaryLogo from '@/assets/images/1panel-logo.svg?component';
import { useGlobalStore } from '@/composables/useGlobalStore';
const { themeConfig } = useGlobalStore();
const loading = ref();
const logoLoadFailed = ref(false);

onMounted(() => {
    getSystemAvailable();
});
</script>

<style lang="scss" scoped>
.system-link {
    margin-left: 15px;

    .svg-icon {
        font-size: 7px;
    }
    span {
        line-height: 20px;
        font-weight: 400;
    }
}
.description {
    color: var(--el-text-color-regular);
}
.logo {
    display: flex;
    align-items: center;
    justify-content: center;
    height: 55px;
    img {
        object-fit: contain;
        width: 95%;
        height: 45px;
    }
}
.upgrade {
    all: initial;
}
</style>
