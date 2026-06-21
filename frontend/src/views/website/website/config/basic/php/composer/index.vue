<template>
    <el-form label-position="right" label-width="100px">
        <el-form-item :label="$t('website.execParameters')">
            <el-select v-model="req.command" class="p-w-400">
                <el-option label="install" value="install"></el-option>
                <el-option label="update" value="update"></el-option>
                <el-option label="require" value="require"></el-option>
                <el-option label="create-project" value="create-project"></el-option>
                <el-option :label="$t('container.custom')" value="custom"></el-option>
            </el-select>
        </el-form-item>
        <el-form-item :label="$t('website.extCommand')">
            <el-input v-model.trim="req.extCommand" class="p-w-400"></el-input>
        </el-form-item>
        <el-form-item :label="$t('website.mirror')">
            <el-select v-model="req.mirror" class="p-w-400" filterable allow-create default-first-option>
                <el-option
                    v-for="mirror in mirrors"
                    :key="mirror.label"
                    :value="mirror.value"
                    :label="mirror.label + ' [' + mirror.value + ']'"
                ></el-option>
            </el-select>
        </el-form-item>
        <el-form-item :label="$t('website.execUser')">
            <el-select v-model="req.user" class="p-w-400">
                <el-option label="www-data" value="www-data"></el-option>
                <el-option label="root" value="root"></el-option>
            </el-select>
        </el-form-item>
        <el-form-item :label="$t('website.execDir')">
            <el-input v-model.trim="req.dir" class="p-w-400">
                <template #prepend>
                    <el-button icon="Folder" @click="dirRef.acceptParams({ dir: true, path: req.dir })" />
                </template>
            </el-input>
        </el-form-item>
        <el-form-item>
            <el-button v-permission type="primary" @click="exec">{{ $t('commons.button.handle') }}</el-button>
        </el-form-item>
    </el-form>
    <TaskLog ref="taskLogRef" @close="search" />
    <FileList ref="dirRef" :dir="true" @choose="getPath" />
</template>
<script setup lang="ts">
import { execComposer, getWebsite } from '@/api/modules/website';
import { newUUID } from '@/utils/id';
import TaskLog from '@/components/log/task/index.vue';
import FileList from '@/components/file-list/index.vue';

const props = defineProps({
    websiteID: {
        type: Number,
        default: 0,
    },
});

const req = reactive({
    websiteID: 0,
    command: 'install',
    extCommand: '',
    mirror: '',
    dir: '',
    user: 'www-data',
    taskID: '',
});
const loading = ref(false);
const taskLogRef = ref();
const dirRef = ref();

const mirrors: Array<{ label: string; value: string }> = [];

const getPath = (execDir: string) => {
    req.dir = execDir;
};

const search = () => {
    loading.value = true;
    getWebsite(req.websiteID)
        .then((res) => {
            req.dir = res.data.sitePath + '/index';
        })
        .finally(() => {
            loading.value = false;
        });
};

const exec = async () => {
    const taskID = newUUID();
    req.taskID = taskID;
    try {
        await execComposer(req);
        taskLogRef.value.openWithTaskID(taskID);
    } catch (error) {
        return;
    }
};

onMounted(() => {
    req.websiteID = props.websiteID;
    search();
});
</script>
