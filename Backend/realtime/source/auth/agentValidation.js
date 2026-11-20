const redis = require('./redis');
const jwtService = require('./jwt.services')

const agentValidation = async (ws, wss, parseMessage) => {
    if(!parseMessage.token) {
        console.log('[AGENT-AUTH] Missing token in parseMessage');
        return ws.close();
    }
    try {
        const invalidToken = await redis.getAsync(parseMessage.token);
        if (invalidToken) {
            console.log(`[AGENT-AUTH] Token marked invalid in Redis: ${invalidToken}`);
            if (invalidToken === "deleted") return false;
            return false;
        }

        let userData = JSON.parse(await jwtService.verify(parseMessage.token));
        if (userData && userData.user_id) {
            let [userMetaData, requestCount] = await Promise.all([
                await redis.getUserMetaData(userData.user_id),
                await redis.getAsync(`${userData.user_id}_agent_request`)
            ]);
            if (userMetaData.code === 200 && userMetaData.data) {
                let decoded = userMetaData.data;
                const reqDeviceId = (parseMessage.device_id || '').toString().trim().toLowerCase();
                const expectedDeviceId = (decoded.mac_id || '').toString().trim().toLowerCase();
                const reqCompName = (parseMessage.computer_name || '').toString().trim().toLowerCase();
                const expectedCompName = (decoded.computer_name || '').toString().trim().toLowerCase();

                if (reqDeviceId && expectedDeviceId && reqDeviceId !== expectedDeviceId) {
                    console.warn(`[AGENT-AUTH] Rejected device_id mismatch for user ${decoded.user_id}: got=${reqDeviceId} expected=${expectedDeviceId}`);
                    return false;
                }
                if (reqCompName && expectedCompName && reqCompName !== expectedCompName) {
                    console.warn(`[AGENT-AUTH] Rejected computer_name mismatch for user ${decoded.user_id}: got=${reqCompName} expected=${expectedCompName}`);
                    return false;
                }

                decoded.device_id = decoded.mac_id || parseMessage.device_id || '';
                decoded.computer_name = decoded.computer_name || parseMessage.computer_name || '';
                console.log(`[AGENT-AUTH] Validated user ${decoded.user_id} (${decoded.computer_name || decoded.email}, device=${decoded.device_id || 'n/a'})`);
                return decoded;
            } else {
                console.log(`[AGENT-AUTH] userMetaData not found for user_id ${userData.user_id}`);
                return false;
            }
        } else {
            console.log(`[AGENT-AUTH] Invalid userData from token:`, userData);
            return false;
        }
    } catch (err) {
        console.error('[AGENT-AUTH] Exception during verification:', err.message);
        return false;
    }
}


module.exports = agentValidation;