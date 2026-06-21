<template>
    <DrawerPro v-model="open" :header="$t('nginx.build')" size="normal" @close="handleClose">
        <el-form ref="buildForm" label-position="top" :model="build" :rules="rules">
            <el-form-item :label="$t('nginx.mirrorUrl')" prop="mirror">
                <el-input v-model.trim="build.mirror" />
            </el-form-item>
        </el-form>
        <template #footer>
            <el-button @click="handleClose" :disabled="loading">{{ $t('commons.button.cancel') }}</el-button>
            <el-button v-permission type="primary" @click="submit(buildForm)" :disabled="loading">
                {{ $t('commons.button.confirm') }}
            </el-button>
        </template>
    </DrawerPro>
    <TaskLog ref="taskLogRef" />
</template>
<script setup lang="ts">
import { ref } from 'vue';
import { FormInstance } from 'element-plus';
import { getNginxModules, buildNginx } from '@/api/modules/nginx';
import i18n from '@/lang';
import { newUUID } from '@/utils/id';
import TaskLog from '@/components/log/task/index.vue';
import { Rules } from '@/global/form-rules';

const open = ref(false);
const loading = ref(false);
const buildForm = ref<FormInstance>();
const build = ref({
    mirror: '',
});
const rules = {
    mirror: [Rules.requiredSelect],
};
const taskLogRef = ref();

const acceptParams = async () => {
    getModules();
    open.value = true;
};

const getModules = async () => {
    try {
        const res = await getNginxModules();
        build.value.mirror = res.data.mirror;
    } catch (error) {}
};

const submit = async (form: FormInstance) => {
    await form.validate();
    if (form.validate()) {
        ElMessageBox.confirm(i18n.global.t('nginx.buildWarn'), i18n.global.t('nginx.build'), {
            confirmButtonText: i18n.global.t('commons.button.confirm'),
            cancelButtonText: i18n.global.t('commons.button.cancel'),
        }).then(async () => {
            const taskID = newUUID();
            try {
                await buildNginx({
                    taskID: taskID,
                    mirror: build.value.mirror,
                });
                handleClose();
                openTaskLog(taskID);
            } catch (error) {}
        });
    }
};

const openTaskLog = (taskID: string) => {
    taskLogRef.value.openWithTaskID(taskID);
};

const handleClose = () => {
    open.value = false;
};

defineExpose({
    acceptParams,
});
</script>
