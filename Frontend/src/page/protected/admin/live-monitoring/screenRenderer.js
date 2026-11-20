/**
 * Screen renderer — module-level canvas drawing.
 * Keeps base64 image data OUT of React state to avoid re-renders.
 */

const canvasRegistry = new Map();
let modalCanvas = null;
let modalUserId = null;
let modalSelectedScreen = 0;

// Pre-compiled regex (avoid compiling per key per frame)
const IMAGE_KEY_RE = /^image(\d+)$/;
const SCREEN_DATA_KEY_RE = /^screenData(\d+)$/;

/**
 * Parse raw WebSocket image_stream payload into a clean structure.
 */
export const parseImageStream = (raw) => {
    const screens = {};

    for (const key in raw) {
        let match = IMAGE_KEY_RE.exec(key);
        if (match) {
            const idx = match[1];
            if (!screens[idx]) screens[idx] = {};
            screens[idx].image = raw[key];
            continue;
        }

        match = SCREEN_DATA_KEY_RE.exec(key);
        if (match) {
            const idx = match[1];
            if (!screens[idx]) screens[idx] = {};
            const sd = raw[key];
            screens[idx].aspectRatio = sd[`aspectRatio${idx}`];
            screens[idx].width = parseInt(sd[`width${idx}`], 10);
            screens[idx].height = parseInt(sd[`height${idx}`], 10);
        }
    }

    const sortedIndices = Object.keys(screens).sort((a, b) => Number(a) - Number(b));
    return {
        userId: Number(raw.user_id) || null,
        deviceId: raw.device_id || "",
        computerName: raw.computer_name || "",
        quality: raw.quality || "",
        screens: sortedIndices.map((i) => screens[i]),
    };
};

const drawSingleScreen = (canvas, screenData, expectedUserId = null) => {
    if (!canvas || !screenData?.image) return;

    const ctx = canvas.getContext("2d");
    const { aspectRatio, width: origW, height: origH } = screenData;

    const container = canvas.parentElement;
    if (!container) return;

    const displayWidth = container.clientWidth;
    const displayHeight = displayWidth / (aspectRatio || 16 / 9);

    canvas.style.width = `${displayWidth}px`;
    canvas.style.height = `${displayHeight}px`;

    if (canvas.width !== origW) canvas.width = origW;
    if (canvas.height !== origH) canvas.height = origH;

    const seq = (canvas.__renderSeq || 0) + 1;
    canvas.__renderSeq = seq;

    const img = new Image();
    img.onload = () => {
        if (canvas.__renderSeq !== seq) return;
        if (expectedUserId != null && canvas.dataset?.userId && Number(canvas.dataset.userId) !== Number(expectedUserId)) return;
        ctx.clearRect(0, 0, canvas.width, canvas.height);
        ctx.drawImage(img, 0, 0, origW, origH);
    };
    img.src = screenData.image.startsWith("data:") ? screenData.image : `data:image/jpeg;base64,${screenData.image}`;
};

const drawDualScreen = (canvas, screen1, screen2, expectedUserId = null) => {
    if (!canvas || !screen1?.image || !screen2?.image) return;

    const ctx = canvas.getContext("2d");
    const origW = screen1.width;
    const origH = screen1.height;
    const aspectRatio = screen1.aspectRatio || 16 / 9;

    const container = canvas.parentElement;
    if (!container) return;

    const displayWidth = container.clientWidth;
    const displayHeight = displayWidth / (2 * aspectRatio);

    canvas.style.width = `${displayWidth}px`;
    canvas.style.height = `${displayHeight}px`;

    const neededW = origW * 2;
    if (canvas.width !== neededW) canvas.width = neededW;
    if (canvas.height !== origH) canvas.height = origH;

    const seq = (canvas.__renderSeq || 0) + 1;
    canvas.__renderSeq = seq;

    const img1 = new Image();
    const img2 = new Image();
    let loaded = 0;

    const drawIfReady = () => {
        if (++loaded < 2) return;
        if (canvas.__renderSeq !== seq) return;
        if (expectedUserId != null && canvas.dataset?.userId && Number(canvas.dataset.userId) !== Number(expectedUserId)) return;
        ctx.clearRect(0, 0, canvas.width, canvas.height);
        ctx.drawImage(img1, 0, 0, origW, origH);
        ctx.drawImage(img2, origW, 0, origW, origH);
    };

    img1.onload = drawIfReady;
    img2.onload = drawIfReady;
    img1.src = screen1.image.startsWith("data:") ? screen1.image : `data:image/jpeg;base64,${screen1.image}`;
    img2.src = screen2.image.startsWith("data:") ? screen2.image : `data:image/jpeg;base64,${screen2.image}`;
};

export const drawOfflinePlaceholder = (canvas) => {
    if (!canvas) return;
    const ctx = canvas.getContext("2d");
    const container = canvas.parentElement;
    if (!container) return;

    const isDark = typeof document !== "undefined" && document.documentElement.classList.contains("dark");
    const displayWidth = container.clientWidth;
    const displayHeight = displayWidth / (16 / 9);

    canvas.style.width = `${displayWidth}px`;
    canvas.style.height = `${displayHeight}px`;
    canvas.width = 320;
    canvas.height = 180;

    ctx.fillStyle = isDark ? "#0F172A" : "#f1f5f9";
    ctx.fillRect(0, 0, 320, 180);
    ctx.fillStyle = isDark ? "#64748b" : "#94a3b8";
    ctx.font = "14px sans-serif";
    ctx.textAlign = "center";
    ctx.fillText("Offline", 160, 95);
};

// --- Registry ---

export const registerCanvas = (userId, canvas) => {
    if (!canvas) return;
    const numId = Number(userId);
    const existing = canvasRegistry.get(numId);
    if (existing?.canvas === canvas) return;
    if (existing?.resizeObserver) existing.resizeObserver.disconnect();
    canvasRegistry.set(numId, { canvas, resizeObserver: null });
};

export const unregisterCanvas = (userId) => {
    const numId = Number(userId);
    const entry = canvasRegistry.get(numId);
    if (entry?.resizeObserver) entry.resizeObserver.disconnect();
    canvasRegistry.delete(numId);
};

export const setModalCanvas = (canvas, userId) => {
    modalCanvas = canvas;
    modalUserId = Number(userId);
    modalSelectedScreen = 0;
    if (canvas) {
        canvas.dataset.userId = String(modalUserId);
        canvas.__renderSeq = (canvas.__renderSeq || 0) + 1;
        const ctx = canvas.getContext("2d");
        if (ctx) ctx.clearRect(0, 0, canvas.width, canvas.height);
    }
};

export const clearModalCanvas = () => {
    if (modalCanvas) {
        modalCanvas.__renderSeq = (modalCanvas.__renderSeq || 0) + 1;
    }
    modalCanvas = null;
    modalUserId = null;
    modalSelectedScreen = 0;
};

export const setModalSelectedScreen = (idx) => {
    modalSelectedScreen = idx;
};

/**
 * Called by the store when an image_stream message arrives.
 * Strictly routes by canonical user_id (users.id) so streams can never cross.
 * Returns screen count.
 */
export const renderScreen = (parsed, isDualScreen = false) => {
    const { userId, screens } = parsed;
    if (!screens.length || !userId) return 0;
    const numId = Number(userId);

    // Draw to card canvas strictly by canonical user_id
    const entry = canvasRegistry.get(numId);
    if (entry?.canvas) {
        if (isDualScreen && screens.length >= 2) {
            drawDualScreen(entry.canvas, screens[0], screens[1], numId);
        } else {
            drawSingleScreen(entry.canvas, screens[0], numId);
        }
    }

    // Draw to modal canvas strictly if modalUserId matches canonical user_id
    if (modalCanvas && Number(modalUserId) === numId) {
        if (isDualScreen && screens.length >= 2) {
            drawDualScreen(modalCanvas, screens[0], screens[1], numId);
        } else {
            const screenIdx = Math.min(modalSelectedScreen, screens.length - 1);
            drawSingleScreen(modalCanvas, screens[screenIdx], numId);
        }
    }

    return screens.length;
};

// --- Streaming control ---

export const requestStream = (safeSendFn, userId, quality = "sd") => {
    safeSendFn({ type: "image_request", requested_user_id: userId, quality });
};

export const setStreamQuality = (safeSendFn, userId, quality = "sd") => {
    safeSendFn({ type: "set_stream_quality", requested_user_id: userId, quality });
};

export const stopStream = (safeSendFn, userId) => {
    safeSendFn({ type: "close_agent_data_stream", requested_user_id: userId });
};
