export const resolveRuntimeAppResource = (isOffline: boolean, customAppStatus?: string) => {
    if (isOffline) {
        return 'remote';
    }
    return customAppStatus?.toLowerCase() === 'enable' ? 'custom' : 'remote';
};
