const WebSocket = require('ws');

const agentValidation = require('../auth/agentValidation');
const adminValidation = require('../auth/adminValidation');

// Initialize objects to store connected agents and image requests
const connectedAgents = {};
const imageRequests = {};
const streamQualityRequests = {}; // { [agentUserId]: { [viewerId]: 'sd' | 'hd' | 'fhd' } }
let organizationRealTime = {};
let cameraStreamRequests = {};

const QUALITY_RANK = { sd: 1, hd: 2, fhd: 3 };
const normalizeQuality = (q) => {
    const v = String(q || 'sd').trim().toLowerCase();
    if (v === 'fhd' || v === '1080p' || v === 'high') return 'fhd';
    if (v === 'hd' || v === '720p' || v === 'medium') return 'hd';
    return 'sd';
};

const computeEffectiveQuality = (agentUserId) => {
    const viewers = imageRequests[agentUserId] || [];
    if (viewers.length === 0) return 'idle';
    const qMap = streamQualityRequests[agentUserId] || {};
    let best = 'sd';
    for (const vid of viewers) {
        const q = normalizeQuality(qMap[vid] || 'sd');
        if (QUALITY_RANK[q] > QUALITY_RANK[best]) best = q;
    }
    return best;
};

const notifyAgentQuality = (agentUserId) => {
    const agentWs = connectedAgents[agentUserId];
    if (!agentWs || agentWs === "Dummy user" || agentWs.readyState !== WebSocket.OPEN) return;
    const eff = computeEffectiveQuality(agentUserId);
    if (eff === 'idle') {
        agentWs.send("User is disconnected, please stop sending images");
    } else {
        agentWs.send(`Start sending image - user is waiting | quality:${eff}`);
    }
};


const { publishToChannel, subscribeToChannel, getAsync, setAsync, delAsync, keysAsync, getUserMetaData } = require("../auth/redis");

const parseIfString = (msg) => {
    if (typeof msg === 'string') {
        try { return JSON.parse(msg); } catch (e) { return null; }
    }
    return msg;
};

subscribeToChannel("channel-auth", (message) => {
    message = parseIfString(message);
    switch (message?.message) {
        case "Agent Auth":
            if (!connectedAgents[message.user_id]) connectedAgents[message.user_id] = "Dummy user";
            break;
        case "Frontend Auth":
            if (!connectedAgents[message.user_id]) connectedAgents[message.user_id] = "Dummy user";
            break;
        default:
            break;
    }
});

subscribeToChannel("channel-image-stream", (message) => {
    message = parseIfString(message);
    switch (message?.message) {
        case "channel-image-stream": {
            const targetUid = message.user_id;
            if (!targetUid) break;
            const reqSet = new Set(imageRequests[targetUid] || []);
            const sanitizedPayload = {
                ...(message.parsedMessage || {}),
                user_id: Number(targetUid) || targetUid,
                device_id: message.device_id || message.parsedMessage?.device_id || '',
                computer_name: message.computer_name || message.parsedMessage?.computer_name || ''
            };
            delete sanitizedPayload.employee_id;
            reqSet.forEach(agentId => {
                const agentWs = connectedAgents[agentId];
                if (agentWs != "Dummy user" && agentWs && agentWs.readyState === WebSocket.OPEN) {
                    if (agentWs.isScreenCast && !agentWs.isRealTimeCards && !agentWs.isWebCamStream) {
                        agentWs.send(JSON.stringify(sanitizedPayload));
                    }
                }
            });
            break;
        }
        default:
            break;
    }
});

subscribeToChannel("channel-camera-stream", (message) => {
    message = parseIfString(message);
    switch (message?.message) {
        case "channel-camera-stream": // Find the admin who requested the webcam stream and send the message received from agent to connected admin/frontend user
            const requests = cameraStreamRequests[message.user_id] || [];
            requests.forEach(agentId => {
                const agentWs = connectedAgents[agentId];
                if (agentWs != "Dummy user" && agentWs && agentWs.readyState === WebSocket.OPEN) {
                    if(!agentWs.isScreenCast && !agentWs.isRealTimeCards && agentWs.isWebCamStream) agentWs.send(JSON.stringify({...message.parsedMessage, user_id: message.user_id}));
                }
            });
            break;
        case "channel-camera-stream-count": // Find the admin who requested the webcam stream and send the message received from agent to connected admin/frontend user
            const requestsCount = cameraStreamRequests[message.user_id] || [];
            requestsCount.forEach(agentId => {
                const agentWs = connectedAgents[agentId];
                if (agentWs != "Dummy user" && agentWs && agentWs.readyState === WebSocket.OPEN) {
                    if(!agentWs.isScreenCast && !agentWs.isRealTimeCards && agentWs.isWebCamStream) agentWs.send(JSON.stringify({type: message.parsedMessage.type, ...message.parsedMessage, user_id: message.user_id}));
                }
            });
            break;
        default:
            break;
    }
});

subscribeToChannel("channel-update-image-request", (message) => {
    message = parseIfString(message);
    switch (message?.message) {
        case "channel-update-image-request":
            if (!imageRequests[message.user_id]) imageRequests[message.user_id] = [];
            break;
        case "channel-update-image-request2":
            if (!imageRequests[message.user_id]) imageRequests[message.user_id] = [];
            if (!imageRequests[message.user_id].includes(message.id)) {
                imageRequests[message.user_id].push(message.id);
            }
            if (!streamQualityRequests[message.user_id]) streamQualityRequests[message.user_id] = {};
            streamQualityRequests[message.user_id][message.id] = normalizeQuality(message.quality || streamQualityRequests[message.user_id][message.id] || 'sd');
            notifyAgentQuality(message.user_id);
            break;
        case "setStreamQualityViewer":
            if (!imageRequests[message.user_id]) imageRequests[message.user_id] = [];
            if (!imageRequests[message.user_id].includes(message.id)) {
                imageRequests[message.user_id].push(message.id);
            }
            if (!streamQualityRequests[message.user_id]) streamQualityRequests[message.user_id] = {};
            streamQualityRequests[message.user_id][message.id] = normalizeQuality(message.quality);
            notifyAgentQuality(message.user_id);
            break;
        case "removeImageRequestViewer":
            if (streamQualityRequests[message.user_id]) {
                delete streamQualityRequests[message.user_id][message.id];
            }
            if (imageRequests[message.user_id]) {
                imageRequests[message.user_id] = imageRequests[message.user_id].filter(id => id !== message.id);
                if (imageRequests[message.user_id].length === 0) {
                    delete imageRequests[message.user_id];
                    delete streamQualityRequests[message.user_id];
                }
            }
            notifyAgentQuality(message.user_id);
            break;
        case "channel-update-image-request3":
            notifyAgentQuality(message.user_id);
            break;
        case "handleFEControl":
            const agentWs = connectedAgents[message.user_id];
            if (agentWs && agentWs !== "Dummy user" && agentWs.readyState === WebSocket.OPEN) {
                agentWs.send(JSON.stringify(message.payload));
            }
            break;
        case "startLatencyTestAgent":
            const agentSocketWS = connectedAgents[message.user_id];
            if (agentSocketWS && agentSocketWS !== "Dummy user" && agentSocketWS.readyState === WebSocket.OPEN) {
                agentSocketWS.send('Start Latency Test');
            }
            break;
        case "latencyTestRecords":
            const requests = imageRequests[message.user_id] || [];
            requests.forEach(agentId => {
                const feUserWS = connectedAgents[agentId];
                if (feUserWS !== "Dummy user" && feUserWS && feUserWS.readyState === WebSocket.OPEN) {
                    feUserWS.send(JSON.stringify(message.parsedMessage));
                }
            });
            const camReq = cameraStreamRequests[message.user_id] || [];
            camReq.forEach(agentId => {
                const feUserWS = connectedAgents[agentId];
                if (feUserWS !== "Dummy user" && feUserWS && feUserWS.readyState === WebSocket.OPEN) {
                    feUserWS.send(JSON.stringify(message.parsedMessage));
                }
            });
            break;
        case "closeHandler":
            const agentCloseWs = connectedAgents[message.user_id];
            if (agentCloseWs !== "Dummy user" && agentCloseWs && agentCloseWs.readyState === WebSocket.OPEN) {
                agentCloseWs.send("User is disconnected, please stop sending images");
            }
            break;
        case "deleteConnectedAgents":
            if (!message.socket_id || connectedAgents[message.user_id] === "Dummy user" || connectedAgents[message.user_id]?.socket_id === message.socket_id) {
                delete connectedAgents[message.user_id];
            }
            break;
        case "deleteImageRequest":
            delete imageRequests[message.user_id];
            delete streamQualityRequests[message.user_id];
            break;
        case "admin_request_webcam_stream":
            // Handle admin request for webcam stream find connected agent and send message to agent to start webcam stream
            let userId = message.user_id;
            const adminWebcamRequest = connectedAgents[userId];
            if (adminWebcamRequest !== "Dummy user" && adminWebcamRequest && adminWebcamRequest.readyState === WebSocket.OPEN) {
                adminWebcamRequest.send(JSON.stringify({ type: "admin_request_webcam_stream", message: "User is connected for web cam stream" }));
            }
            if(!cameraStreamRequests[userId]) cameraStreamRequests[userId] = [message.frontend_user_id];
            else if (!cameraStreamRequests[userId].includes(message.frontend_user_id)) cameraStreamRequests[userId].push(message.frontend_user_id);
            break;
        case "admin_request_webcam_stream_select":
            let userIdSelect = message.user_id;
            const adminWebcamRequestSelect = connectedAgents[userIdSelect];
            if (adminWebcamRequestSelect !== "Dummy user" && adminWebcamRequestSelect && adminWebcamRequestSelect.readyState === WebSocket.OPEN) {
                adminWebcamRequestSelect.send(JSON.stringify({ type: "admin_request_webcam_stream_selected_screen", message: message.parsedMessage }));
            }
            break;
        case "admin_disconnected": 
            // Handle admin disconnection for webcam stream
            Object.keys(cameraStreamRequests).forEach(async (requestedUserId) => {
                cameraStreamRequests[requestedUserId] = cameraStreamRequests[requestedUserId].filter(id => id !== message.user_id);
                if (cameraStreamRequests[requestedUserId].length === 0) {
                    const agentCloseWs = connectedAgents[requestedUserId];
                    if (agentCloseWs !== "Dummy user" && agentCloseWs && agentCloseWs.readyState === WebSocket.OPEN) {
                        agentCloseWs.send("User is disconnected, please stop sending camera stream");
                    }
                }
            });
            break;
        default:
            break;
    }
});


subscribeToChannel("channel-update-realtime-activity", (message) => {
    message = parseIfString(message);
    switch (message?.message) {
        case "agent_auth":
            organizationRealTime[message.organization_id] = organizationRealTime[message.organization_id] || { frontend: [], agents: [] };
            if (!organizationRealTime[message.organization_id].agents.includes(message.user_id)) {
                organizationRealTime[message.organization_id].agents.push(message.user_id);
            }
            break;
        case "admin_auth":
            organizationRealTime[message.organization_id] = organizationRealTime[message.organization_id] || { frontend: [], agents: [] };
            if (!organizationRealTime[message.organization_id].frontend.includes(message.user_id)) {
                organizationRealTime[message.organization_id].frontend.push(message.user_id);
            }
            break;
        case "user_connected_to_dashboard_for_activity":
            for (const agent_id of (organizationRealTime[message.organization_id]?.['agents'] || [])) {
                if(connectedAgents[agent_id] && connectedAgents[agent_id] != "Dummy user" && connectedAgents[agent_id].readyState === WebSocket.OPEN) connectedAgents[agent_id].send("User connected to the dashboard, start sending the activity");
            }
            break;
        case "sending_agent_activity_to_users":
            for (const user_id of (organizationRealTime[message.organization_id]?.['frontend'] || [])) {
                if(connectedAgents[user_id] && connectedAgents[user_id] != "Dummy user" && connectedAgents[user_id].readyState === WebSocket.OPEN) 
                if(!connectedAgents[user_id].isScreenCast && !connectedAgents[user_id].isWebCamStream && connectedAgents[user_id].isRealTimeCards) connectedAgents[user_id].send(JSON.stringify(message.parsedMessage));
            }
            break;
        case "no_activity_found_send_current_activity":
            for (const agent_id of (organizationRealTime[message.organization_id]?.['agents'] || [])) {
                if(connectedAgents[agent_id] && connectedAgents[agent_id] != "Dummy user" && connectedAgents[agent_id].readyState === WebSocket.OPEN) connectedAgents[agent_id].send("No activity found, send the current activity");
            }
            break;
        case "idle_agent_alert":
                let passparsedMessage = (message.parsedMessage);
                let senderAgentId = message.senderAgentId;
                let date = passparsedMessage?.date;
                let start_date = passparsedMessage.start_time;
                let end_date = passparsedMessage.end_time;
                if(connectedAgents[senderAgentId] && connectedAgents[senderAgentId] != "Dummy user") connectedAgents[senderAgentId].send(JSON.stringify({ type: "idle_agent_alert", seconds : passparsedMessage._doc.total_duration - passparsedMessage._doc.active_seconds, application_id: passparsedMessage._doc._id, date, clock_in: start_date, clock_out: end_date, date }));

        case "disconnect":
            const userList = organizationRealTime[message.organization_id]?.[message.userType];
            if (userList && userList.length !== 0) {
                organizationRealTime[message.organization_id][message.userType] = userList.filter(id => id !== message.user_id);
            }
            break;
    }
});



const handleAgentAuth = async (ws, wss, parsedMessage) => {
    try {
        const agentData = await agentValidation(ws, wss, parsedMessage);
        if (agentData) {
            const canonicalUid = Number(agentData.user_id) || agentData.user_id;
            const prevWs = connectedAgents[canonicalUid];
            if (prevWs && prevWs !== "Dummy user" && prevWs !== ws) {
                try {
                    if (prevWs.readyState === WebSocket.OPEN || prevWs.readyState === WebSocket.CONNECTING) {
                        prevWs.close(4001, 'Replaced by newer agent session');
                    }
                } catch (e) {}
            }

            ws.socket_id = `${canonicalUid}_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;
            connectedAgents[canonicalUid] = ws;
            ws.user_id = canonicalUid;
            ws.employee_id = agentData.employee_id;
            ws.organization_id = agentData.organization_id;
            ws.device_id = (agentData.device_id || agentData.mac_id || '').toString().trim();
            ws.computer_name = (agentData.computer_name || '').toString().trim();

            await publishToChannel("channel-update-realtime-activity", JSON.stringify({ user_id: canonicalUid, message: "agent_auth", organization_id: agentData.organization_id }));
            await publishToChannel("channel-auth", JSON.stringify({ user_id: canonicalUid, message: "Agent Auth" }));

            ws.send('Agent authenticated successfully');
            if (imageRequests[canonicalUid] && imageRequests[canonicalUid].length > 0) {
                notifyAgentQuality(canonicalUid);
            }
            return;
        } else {
            return ws.close();
        }
    } catch (error) {
        console.error('Error during agent authentication:', error);
        return ws.close();
    }
};

const handleFeAuth = async (ws, wss, parsedMessage) => {
    try {
        let adminData = await adminValidation(ws, wss, parsedMessage);
        if (adminData) {
            adminData.user_id = `${adminData.user_id}${Date.now()}`
            connectedAgents[adminData.user_id] = ws;
            ws.user_id = adminData.user_id;
            ws.organization_id = adminData.organization_id;
            await publishToChannel("channel-auth", JSON.stringify({ user_id: adminData.user_id, message: "Frontend Auth" }));
            await publishToChannel("channel-update-realtime-activity", JSON.stringify({ user_id: adminData.user_id, message: "admin_auth", organization_id: adminData.organization_id }));

            const key = `organizationActive:${ws.organization_id}`;
            let value = await getAsync(key);

            // If value is not found or equals 0, set it to 0
            if (!value || value == 0) {
                await setAsync(key, 0);
            }

            return ws.send('User authenticated successfully');
        } else {
            return ws.close();
        }
    } catch (error) {
        console.error('Error during admin authentication:', error);
        return ws.close();
    }
};

const handleReportAuth = async (ws, wss, parsedMessage) => {
    try {
        ws.user_id = "remote_server";
        return ws.send('Connected');
    } catch (error) {
        return ws.close();
    }
};

const handleStartImageStream = async (ws, wss, parsedMessage) => {
    if (!ws.user_id) return ws.close();
    // Ignore stale frames from a superseded agent WebSocket
    if (connectedAgents[ws.user_id] && connectedAgents[ws.user_id] !== ws) return;

    // Enforce machine identifier match when provided on frame
    const frameDeviceId = (parsedMessage?.device_id || '').toString().trim().toLowerCase();
    const expectedDeviceId = (ws.device_id || '').toString().trim().toLowerCase();
    if (frameDeviceId && expectedDeviceId && frameDeviceId !== expectedDeviceId) {
        console.warn(`[REALTIME] Dropped frame with mismatched device_id=${frameDeviceId} on user_id=${ws.user_id} (expected=${expectedDeviceId})`);
        return;
    }

    if (parsedMessage && parsedMessage.image0) {
        const imgVal = parsedMessage.image0.startsWith('data:')
            ? parsedMessage.image0
            : `data:image/jpeg;base64,${parsedMessage.image0}`;
        setAsync(`latest_screenshot:${ws.user_id}`, imgVal, 'EX', 86400).catch(() => {});
    }

    const cleanFrame = {
        ...parsedMessage,
        user_id: ws.user_id,
        device_id: ws.device_id || '',
        computer_name: ws.computer_name || '',
        quality: parsedMessage?.quality ? normalizeQuality(parsedMessage.quality) : 'sd'
    };
    delete cleanFrame.employee_id;

    await publishToChannel("channel-image-stream", JSON.stringify({
        user_id: ws.user_id,
        device_id: ws.device_id || '',
        computer_name: ws.computer_name || '',
        message: "channel-image-stream",
        parsedMessage: cleanFrame
    }));
};

const handleImageRequest = async (ws, wss, parsedMessage) => {
    if (!ws.user_id) return ws.close();

    const key = `organizationActive:${ws.organization_id}`;
    const value = await getAsync(key);
    if (value === '1') {
        // return ws.send("You are already connected to a different system.");
    }
    await setAsync(key, 1);
    ws.recevingImage = true;
    ws.isScreenCast = true;
    ws.isRealTimeCards = false;
    ws.isWebCamStream = false;

    const requestedUserId = Number(parsedMessage.requested_user_id) || parsedMessage.requested_user_id;
    if (!requestedUserId) return ws.send('Invalid requested_user_id');
    const requestedQuality = normalizeQuality(parsedMessage.quality || 'sd');

    if (!imageRequests[requestedUserId]) {
        imageRequests[requestedUserId] = [];
        await publishToChannel("channel-update-image-request", JSON.stringify({ user_id: requestedUserId, message: "channel-update-image-request" }));
    }

    await publishToChannel("channel-update-image-request", JSON.stringify({
        user_id: requestedUserId,
        message: "channel-update-image-request2",
        id: ws.user_id,
        quality: requestedQuality
    }));

    // Send latest screenshot immediately ONLY to the requesting viewer
    try {
        let cachedImg = await getAsync(`latest_screenshot:${requestedUserId}`);
        let userMeta = null;
        if (!cachedImg) {
            userMeta = await getUserMetaData(requestedUserId);
            const email = userMeta?.data?.email;
            if (email) {
                const fs = require('fs');
                const path = require('path');
                const baseDir = path.join('/app/shared_screenshots', email);
                if (fs.existsSync(baseDir)) {
                    const days = fs.readdirSync(baseDir).sort().reverse();
                    for (const day of days) {
                        const dayDir = path.join(baseDir, day);
                        const files = fs.readdirSync(dayDir).filter(f => f.endsWith('.jpg') || f.endsWith('.jpeg') || f.endsWith('.png')).sort().reverse();
                        if (files.length > 0) {
                            const buf = fs.readFileSync(path.join(dayDir, files[0]));
                            cachedImg = `data:image/jpeg;base64,${buf.toString('base64')}`;
                            await setAsync(`latest_screenshot:${requestedUserId}`, cachedImg, 'EX', 86400);
                            break;
                        }
                    }
                }
            }
        }

        if (cachedImg && ws.readyState === WebSocket.OPEN) {
            if (!userMeta) userMeta = await getUserMetaData(requestedUserId).catch(() => null);
            const streamPayload = {
                type: 'start_image_stream',
                user_id: requestedUserId,
                device_id: userMeta?.data?.mac_id || '',
                computer_name: userMeta?.data?.computer_name || '',
                image0: cachedImg,
                screenData0: {
                    aspectRatio0: 1.7777777777777777,
                    width0: 1920,
                    height0: 1080
                }
            };
            ws.send(JSON.stringify(streamPayload));
        }
    } catch (fetchErr) {
        console.error('[REALTIME] Error delivering immediate screenshot:', fetchErr.message);
    }

    return ws.send(`Image request received for user ${requestedUserId}`);
};

const onCloseHandler = async (ws) => {
    const user_id = ws.user_id;
    if (user_id && connectedAgents[user_id] === ws) {
        await publishToChannel("channel-update-image-request", JSON.stringify({ user_id: user_id, socket_id: ws.socket_id || null, message: "deleteConnectedAgents" }));
    }

    if (ws.organization_id && ws.recevingImage) {
        const key = `organizationActive:${ws.organization_id}`;
        const value = await delAsync(key);
    }

    // Remove the closed WebSocket from imageRequests and recalc stream quality
    Object.keys(imageRequests).forEach(async (requestedUserId) => {
        const hadViewer = imageRequests[requestedUserId].includes(user_id);
        if (!hadViewer) return;
        await publishToChannel("channel-update-image-request", JSON.stringify({
            user_id: Number(requestedUserId) || requestedUserId,
            id: user_id,
            message: "removeImageRequestViewer"
        }));
    });


    if(ws.isWebCamStream) await publishToChannel("channel-update-image-request", JSON.stringify({ message: "admin_disconnected", user_id }));

    if (typeof user_id === "string" || typeof user_id === "number") {
        const userType = typeof user_id === "string" ? "frontend" : "agents";
        await publishToChannel("channel-update-realtime-activity", JSON.stringify({ message: "disconnect", organization_id: ws.organization_id, user_id, userType }));
    }
};


const checkAgentOnlineStatus = async (ws, wss, parsedMessage) => {
    if (!ws.user_id) return ws.close();

    const requestedUserId = parsedMessage.requested_user_id;
    if (!requestedUserId) return ws.send('Invalid requested_user_id');

    const agentWs = connectedAgents[requestedUserId];
    const redisActive = await getAsync(`${requestedUserId}_agent_request`);
    if (agentWs || redisActive) {
        ws.send('Agent is online -- Agent Status');
    } else {
        ws.send('Agent is offline -- Agent Status');
    }
}

const handleFeControl = async (ws, wss, parsedMessage) => {
    if (!ws.user_id) return ws.close();
    let { event, data, requested_user_id, ...rest } = parsedMessage;

    if (!requested_user_id) return ws.send('Invalid requested_user_id');
    await publishToChannel("channel-update-image-request", JSON.stringify({ user_id: requested_user_id, message: "handleFEControl", payload: { type: 'control', event: event, data: data, rest } }));
};

const handleLatencyTest = (ws, wss, parsedMessage) => {
    ws.send('Latency Test Completed');
};

const handleLatencyTestAgent = (ws, wss, parsedMessage) => {
    ws.send(JSON.stringify(parsedMessage));
};

const handleAgentLatencyTestRequest = async (ws, wss, parsedMessage) => {
    if (!ws.user_id) return ws.close();

    const requestedUserId = parsedMessage.requested_user_id;
    if (!requestedUserId) return ws.send('Invalid requested_user_id');

    await publishToChannel("channel-update-image-request", JSON.stringify({ user_id: requestedUserId, message: "startLatencyTestAgent" }));
};


const handleLatencyTestRecordSend = async (ws, wss, parsedMessage) => {
    if (!ws.user_id) return ws.close();
    await publishToChannel("channel-update-image-request", JSON.stringify({ user_id: ws.user_id, message: "latencyTestRecords", parsedMessage }));
};

const handleSystemStatusRecordSend = async (ws, wss, parsedMessage) => {
    if (!ws.user_id) return ws.close();
    await publishToChannel("channel-update-image-request", JSON.stringify({ user_id: ws.user_id, message: "latencyTestRecords", parsedMessage }));
};





/* Below Code is for Real time dashboard activity */

const getActiveOnlineAgents = async (orgId) => {
    const active = new Set((organizationRealTime[orgId]?.agents || []).map(Number).filter(Boolean));
    try {
        if (typeof keysAsync === "function") {
            const keys = await keysAsync("*_agent_request");
            if (keys && keys.length) {
                for (const key of keys) {
                    const uid = key.replace("_agent_request", "");
                    if (uid && !isNaN(uid)) {
                        const meta = await getUserMetaData(uid);
                        if (meta && meta.code === 200 && meta.data) {
                            if (String(meta.data.organization_id) === String(orgId)) {
                                // Strictly return canonical user_id (never mix employee_id into user_id set)
                                if (meta.data.user_id) active.add(Number(meta.data.user_id));
                            }
                        }
                    }
                }
            }
        }
    } catch (err) {
        console.error("Error fetching active agents from Redis:", err.message);
    }
    return Array.from(active);
};

const handleUserConnected = async (ws, wss, parsedMessage) => {
    if (!ws.user_id) return ws.close();
    if (!ws.organization_id) return ws.close();

    const agents = await getActiveOnlineAgents(ws.organization_id);
    if (agents.length == 0) return ws.send('No agents connected to the system');

    await publishToChannel("channel-update-realtime-activity", JSON.stringify({ message: "user_connected_to_dashboard_for_activity", organization_id: ws.organization_id }));

    ws.isScreenCast = false;
    ws.isRealTimeCards = true;
    ws.isWebCamStream = false;

    ws.send(JSON.stringify({ type: "send_connected_agent_status", data: agents }));

    // Immediately deliver cached latest activity for each online agent
    for (const agentId of agents) {
        try {
            const actStr = await getAsync(`latest_activity:${agentId}`);
            if (actStr && ws.readyState === 1) {
                ws.send(actStr);
            }
        } catch (actErr) {}
    }
};


const handleRealTimeAgentConnectedStatus = async (ws, wss, parsedMessage) => {
    if (!ws.user_id) return ws.close();
    if (!ws.organization_id) return ws.close();

    const agents = await getActiveOnlineAgents(ws.organization_id);
    if (agents.length == 0) return ws.send('No agents connected to the system');

    ws.send(JSON.stringify({ type: "send_connected_agent_status", data: agents }));
};

const handleRealTimeUsageHistoryStatus = async (ws, wss, parsedMessage) => {
    if (!ws.user_id) return ws.close();
    if (!ws.organization_id) return ws.close();

    if (organizationRealTime[ws.organization_id] && organizationRealTime[ws.organization_id]['frontend'].length == 0) return ws.send('No user connected to the system, stop sending requests');

    await publishToChannel("channel-update-realtime-activity", JSON.stringify({ message: "sending_agent_activity_to_users", organization_id: ws.organization_id, parsedMessage: { ...parsedMessage, user_id: ws.user_id } }));
};

const handleRealTimeUsageHistoryStatusNoActivity = async (ws, wss, parsedMessage) => {
    const agents = await getActiveOnlineAgents(ws.organization_id);
    if (agents.length == 0) return ws.send('No agents connected to the system');
    await publishToChannel("channel-update-realtime-activity", JSON.stringify({ message: "no_activity_found_send_current_activity", organization_id: ws.organization_id }));
    ws.send(JSON.stringify({ type: "send_connected_agent_status", data: agents }));

    // Send latest activity for each agent
    for (const agentId of agents) {
        try {
            const actStr = await getAsync(`latest_activity:${agentId}`);
            if (actStr && ws.readyState === 1) {
                ws.send(actStr);
            }
        } catch (actErr) {}
    }
}

const handleCheckAdminConnectedStatus = (ws, wss, parsedMessage) => {
    if (organizationRealTime[ws.organization_id] && organizationRealTime[ws.organization_id]['frontend'].length == 0) return ws.send('No user connected to the system, stop sending requests');
    return ws.send("User connected to the dashboard, start sending the activity");
};

const handleAgentIdleAlert = async (ws, wss, parsedMessage) => {
    if(!ws.user_id) return ws.close();
    if(ws.user_id) await publishToChannel("channel-update-realtime-activity", JSON.stringify({ message: "idle_agent_alert", organization_id: ws.organization_id, senderAgentId: parsedMessage.senderAgentId, parsedMessage }));
};


const handleSetStreamQuality = async (ws, wss, parsedMessage) => {
    if (!ws.user_id) return ws.close();
    const requestedUserId = Number(parsedMessage.requested_user_id) || parsedMessage.requested_user_id;
    if (!requestedUserId) return;
    const requestedQuality = normalizeQuality(parsedMessage.quality || 'sd');
    return await publishToChannel("channel-update-image-request", JSON.stringify({
        user_id: requestedUserId,
        id: ws.user_id,
        quality: requestedQuality,
        message: "setStreamQualityViewer"
    }));
};

const handleCloseAgentDataStream = async (ws, wss, parsedMessage) => {
    if (!ws.user_id) return ws.close();
    const requestedUserId = Number(parsedMessage.requested_user_id) || parsedMessage.requested_user_id;
    if (!requestedUserId) return;
    return await publishToChannel("channel-update-image-request", JSON.stringify({
        user_id: requestedUserId,
        id: ws.user_id,
        message: "removeImageRequestViewer"
    }));
}

const handleAdminRequestWebcamStream = async (ws, wss, parsedMessage) => {
    if (!ws.user_id) return ws.close();
    const requestedUserId = parsedMessage.requested_user_id;
    if (!requestedUserId) return ws.send('Invalid requested_user_id');
    // Marking user usage status
    ws.isScreenCast = false;
    ws.isRealTimeCards = false;
    ws.isWebCamStream = true;
    // Pushing message to connected agents
    await publishToChannel("channel-update-image-request", JSON.stringify({ user_id: requestedUserId, message: "admin_request_webcam_stream", parsedMessage, frontend_user_id: ws.user_id }));
};

const handleAdminRequestWebcamStreamSelect = async(ws, wss, parsedMessage) => {
    if (!ws.user_id) return ws.close();
    const requestedUserId = parsedMessage.requested_user_id;
    if (!requestedUserId) return ws.send('Invalid requested_user_id');
    await publishToChannel("channel-update-image-request", JSON.stringify({ user_id: requestedUserId, message: "admin_request_webcam_stream_select", parsedMessage, frontend_user_id: ws.user_id }));
}

const handleAgentWebcamStream = async (ws, wss, parsedMessage) => {
    if (!ws.user_id) return ws.close();
    // Publishing received webcam stream to the channel for connected frontend users
    await publishToChannel("channel-camera-stream", JSON.stringify({ user_id: ws.user_id, message: "channel-camera-stream", parsedMessage }));
}

const handleAgentWebcamStreamCount = async (ws, wss, parsedMessage) => {
    if (!ws.user_id) return ws.close();
    // Publishing received webcam stream to the channel for connected frontend users
    await publishToChannel("channel-camera-stream", JSON.stringify({ user_id: ws.user_id, message: "channel-camera-stream-count", parsedMessage }));
}


module.exports = {
    handleAgentAuth,
    handleFeAuth,
    handleStartImageStream,
    handleImageRequest,
    handleSetStreamQuality,
    onCloseHandler,
    checkAgentOnlineStatus,
    handleFeControl,
    handleLatencyTest,
    handleAgentLatencyTestRequest,
    handleLatencyTestRecordSend,
    handleLatencyTestAgent,
    handleSystemStatusRecordSend,
    handleUserConnected,
    handleRealTimeAgentConnectedStatus,
    handleRealTimeUsageHistoryStatus,
    handleRealTimeUsageHistoryStatusNoActivity,
    handleCheckAdminConnectedStatus,
    handleReportAuth,
    handleAgentIdleAlert,
    handleCloseAgentDataStream,
    handleAdminRequestWebcamStream,
    handleAgentWebcamStream,
    handleAgentWebcamStreamCount,
    handleAdminRequestWebcamStreamSelect
}