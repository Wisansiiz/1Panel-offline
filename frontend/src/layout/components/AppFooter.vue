<template>
    <div class="footer" :style="{ height: isMobile ? '108px' : '48px' }">
        <div class="flex w-full flex-col gap-4 md:justify-between md:flex-row">
            <div class="flex flex-wrap gap-4">
                <span v-if="!isIntl && !isFxplay">
                    Copyright © 2014-{{ year }} {{ $t('commons.fit2cloud') }}
                </span>
                <span v-else>
                    Copyright © {{ year }} {{ $t('commons.lingxia') }}
                </span>
            </div>
            <div class="flex flex-row gap-2 md:flex-col lg:flex-row">
                <SystemUpgrade :footer="true" />
            </div>
        </div>
    </div>
</template>

<script setup lang="ts">
import SystemUpgrade from '@/components/system-upgrade/index.vue';
import { useGlobalStore } from '@/composables/useGlobalStore';

const { isFxplay, isIntl, isMobile } = useGlobalStore();

const year = new Date().getFullYear();
</script>

<style scoped lang="scss">
.footer {
    display: flex;
    align-items: center;
    justify-content: space-between;
    height: 48px;
    background: var(--panel-footer-bg);
    border-top: 1px solid var(--panel-footer-border);
    box-sizing: border-box;
    padding: 10px 20px;
    a {
        font-size: 12px;
        color: #858585;
        text-decoration: none;
        letter-spacing: 0.5px;
    }
    span {
        font-size: 12px;
        color: #858585;
        text-decoration: none;
        letter-spacing: 0.5px;
    }
}
</style>
