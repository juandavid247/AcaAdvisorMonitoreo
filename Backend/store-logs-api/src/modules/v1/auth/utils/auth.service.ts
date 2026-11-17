import { Injectable, ForbiddenException, HttpException } from '@nestjs/common';
import { CryptoService } from './crypto.service';
import { JWTService } from './jwt.service';
import { RedisService } from 'nestjs-redis';

import config from '../../../../../../config/config.js';

let screenshotCustomRequestLimit = [...config.CUSTOM_SCREENSHOT_FREQUENCY_120_PER_HOUR, ...config.CUSTOM_SCREENSHOT_FREQUENCY_180_PER_HOUR, ...config.CUSTOM_SCREENSHOT_FREQUENCY_240_PER_HOUR, ...config.CUSTOM_SCREENSHOT_FREQUENCY_360_PER_HOUR, ...config.CUSTOM_SCREENSHOT_FREQUENCY_480_PER_HOUR, ...config.CUSTOM_SCREENSHOT_FREQUENCY_600_PER_HOUR, ...config.CUSTOM_SCREENSHOT_FREQUENCY_720_PER_HOUR, ...config.CUSTOM_SCREENSHOT_FREQUENCY_900_PER_HOUR, ...config.CUSTOM_SCREENSHOT_FREQUENCY_1200_PER_HOUR, ...config.CUSTOM_SCREENSHOT_FREQUENCY_1800_PER_HOUR, ...config.CUSTOM_SCREENSHOT_FREQUENCY_3600_PER_HOUR];

let MAX_REQUEST_ALLOWED = process.env.MAX_REQUEST_ALLOWED;

@Injectable()
export class AuthService {

    constructor(
        private readonly crytoService: CryptoService,
        private readonly jwtService: JWTService,
        private readonly redisService: RedisService
    ) { }

    async verify(token: string): Promise<any> {

        // logout token check
        const invalidToken = await this.redisService.getClient().get(token);
        if (invalidToken) {
            throw new ForbiddenException('Invalid token');
        }
        const decryptedToken: any = await this.crytoService.decrypt(token, process.env.CRYPTO_PASSWORD);

        if (decryptedToken.error || decryptedToken.code !== 200) {
            throw new ForbiddenException('Invalid token');
            // throw new ForbiddenException('Invalid token string.');
        }

        token = decryptedToken.decoded;

        const decodedButEncryptedToken: any = await this.jwtService.verifyToken(token);
        if (decodedButEncryptedToken.signature) {
            const decryptedSignature: any = await this.crytoService.decrypt(decodedButEncryptedToken.signature, process.env.CRYPTO_PASSWORD);

            if (decryptedSignature.error || decryptedSignature.code !== 200) {
                throw new ForbiddenException('Invalid token');
                // throw new ForbiddenException('Invalid token string.');
            }

            const decoded = JSON.parse(decryptedSignature.decoded);

            const [userData] = await Promise.all([
                await this.redisService.getClient().get(decoded.user_id),
            ]);

            const agentTtl = Math.max(+(process.env.MAX_REQUEST_ALLOWED_TIMEFRAME || 300), 300);
            await this.redisService.getClient().set(`${decoded.user_id}_agent_request`, 1, 'EX', agentTtl);
            if (userData) {
                try {
                    const parsedUser = JSON.parse(userData);
                    if (parsedUser.employee_id && String(parsedUser.employee_id) !== String(decoded.user_id)) {
                        await this.redisService.getClient().set(`${parsedUser.employee_id}_agent_request`, 1, 'EX', agentTtl);
                    }
                } catch (e) {}
            }
            return userData;
            // return await this.redisService.getClient().get(decoded.user_id);
        } else {
            throw new ForbiddenException('Invalid token');
            // throw new ForbiddenException('Not autherised to access this.');
        }
    }
}
