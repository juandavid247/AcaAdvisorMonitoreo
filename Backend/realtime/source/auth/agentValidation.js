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
                console.log(`[AGENT-AUTH] Validated user ${decoded.user_id} (${decoded.email})`);
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