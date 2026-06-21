const privateIPv4 = [
    /^10\./,
    /^127\./,
    /^169\.254\./,
    /^192\.168\./,
    /^172\.(1[6-9]|2\d|3[01])\./,
];

const isPrivateHostname = (hostname: string) => {
    const normalized = hostname.toLowerCase().replace(/^\[|\]$/g, '');
    if (
        normalized === 'localhost' ||
        normalized === '::1' ||
        normalized.startsWith('fc') ||
        normalized.startsWith('fd') ||
        normalized.startsWith('fe80:')
    ) {
        return true;
    }
    if (privateIPv4.some((pattern) => pattern.test(normalized))) {
        return true;
    }
    return !normalized.includes('.') || /\.(local|internal|lan)$/.test(normalized);
};

export const isAllowedOfflineURL = (value: string | URL | undefined) => {
    if (!value) {
        return true;
    }
    try {
        const url = new URL(value.toString(), window.location.origin);
        if (!['http:', 'https:', 'ws:', 'wss:'].includes(url.protocol)) {
            return true;
        }
        return url.origin === window.location.origin || isPrivateHostname(url.hostname);
    } catch {
        return false;
    }
};

export const installOfflineNavigationGuard = () => {
    const originalOpen = window.open.bind(window);
    window.open = ((url?: string | URL, target?: string, features?: string) => {
        if (!isAllowedOfflineURL(url)) {
            console.warn('Blocked public network navigation in offline mode');
            return null;
        }
        return originalOpen(url, target, features);
    }) as typeof window.open;

    document.addEventListener(
        'click',
        (event) => {
            const target = event.target;
            if (!(target instanceof Element)) {
                return;
            }
            const anchor = target.closest('a[href]');
            if (anchor instanceof HTMLAnchorElement && !isAllowedOfflineURL(anchor.href)) {
                event.preventDefault();
                event.stopImmediatePropagation();
                console.warn('Blocked public link in offline mode');
            }
        },
        true,
    );
};
