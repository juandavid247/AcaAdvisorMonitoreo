import { Injectable, ForbiddenException, HttpException, Inject } from '@nestjs/common';
import { CryptoService } from './crypto.service';
import { JWTService } from './jwt.service';
import { RedisService } from 'nestjs-redis';
import { Sequelize } from 'sequelize-typescript';
import { QueryTypes } from 'sequelize';

import config from '../../../../../../config/config.js';

let screenshotCustomRequestLimit = [...config.CUSTOM_SCREENSHOT_FREQUENCY_120_PER_HOUR, ...config.CUSTOM_SCREENSHOT_FREQUENCY_180_PER_HOUR, ...config.CUSTOM_SCREENSHOT_FREQUENCY_240_PER_HOUR, ...config.CUSTOM_SCREENSHOT_FREQUENCY_360_PER_HOUR, ...config.CUSTOM_SCREENSHOT_FREQUENCY_480_PER_HOUR, ...config.CUSTOM_SCREENSHOT_FREQUENCY_600_PER_HOUR, ...config.CUSTOM_SCREENSHOT_FREQUENCY_720_PER_HOUR, ...config.CUSTOM_SCREENSHOT_FREQUENCY_900_PER_HOUR, ...config.CUSTOM_SCREENSHOT_FREQUENCY_1200_PER_HOUR, ...config.CUSTOM_SCREENSHOT_FREQUENCY_1800_PER_HOUR, ...config.CUSTOM_SCREENSHOT_FREQUENCY_3600_PER_HOUR];

let MAX_REQUEST_ALLOWED = process.env.MAX_REQUEST_ALLOWED;

@Injectable()
export class AuthService {

    constructor(
        private readonly crytoService: CryptoService,
        private readonly jwtService: JWTService,
        private readonly redisService: RedisService,
        @Inject('SEQUELIZE') private readonly sequelize: Sequelize,
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

            let userData = await this.redisService.getClient().get(decoded.user_id);

            // Auto-rehydrate Redis session from MySQL if Redis restarted or key expired
            if (!userData && decoded.user_id) {
                try {
                    const rows: any[] = await this.sequelize.query(
                        `SELECT u.id AS user_id, u.first_name, u.last_name, u.email, u.status, u.username,
                                e.id AS employee_id, e.id AS id, e.organization_id, e.department_id, e.location_id,
                                COALESCE(e.timezone, 'America/Bogota') AS timezone
                         FROM users u
                         JOIN employees e ON e.user_id = u.id
                         WHERE u.id = ? AND u.status = 1
                         LIMIT 1`,
                        { replacements: [decoded.user_id], type: QueryTypes.SELECT }
                    );
                    if (rows && rows.length > 0) {
                        const r = rows[0];
                        const hydrated = {
                            user_id: r.user_id,
                            id: r.employee_id,
                            employee_id: r.employee_id,
                            first_name: r.first_name,
                            last_name: r.last_name,
                            email: r.email,
                            a_email: r.email,
                            username: r.username,
                            status: r.status,
                            organization_id: r.organization_id || 1,
                            department_id: r.department_id || 1,
                            location_id: r.location_id || 1,
                            timezone: r.timezone || 'America/Bogota',
                            is_employee: true,
                            setting: {
                                trackingMode: 'unlimited',
                                features: {
                                    application_usage: '1',
                                    keystrokes: '1',
                                    web_usage: '1',
                                    screenshots: '1',
                                    screen_record: 1,
                                    screencast: '1',
                                    realTimeTrack: '1',
                                    buttonClicks: '1',
                                    mouseMovements: '1'
                                },
                                screenshot: { frequencyPerHour: 180, screenshotPeriodSec: 20 }
                            }
                        };
                        userData = JSON.stringify(hydrated);
                        await this.redisService.getClient().set(String(decoded.user_id), userData);
                        console.log(`[AuthService] Auto-rehydrated Redis session for user_id=${decoded.user_id} (employee_id=${r.employee_id})`);
                    }
                } catch (rehydrateErr) {
                    console.error('[AuthService] Redis rehydrate error:', rehydrateErr?.message || rehydrateErr);
                }
            }

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
