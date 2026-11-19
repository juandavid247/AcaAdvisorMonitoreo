'use strict';

const crypto = require('crypto');
const router = require('express').Router();
const rateLimit = require('express-rate-limit');
const auth = require('./auth.controller');
const AuthMiddleware = require('../auth/services/auth.middleware');
const { ResellerAuthRoutes } = require('./reseller/Reseller.Routes');

const authRateLimiter = rateLimit({
    windowMs: 5 * 60 * 1000,
    max: 30,
    standardHeaders: true,
    legacyHeaders: false,
    message: { code: 429, data: null, error: 'TooManyRequests', message: 'Too many authentication attempts. Please try again later.' },
});

function requireInternalAdminAuth(req, res, next) {
    const expectedSecret = process.env.INTERNAL_AUTH_SECRET || process.env.SESSION_SECRET || '';
    const providedSecret = String(req.headers['x-internal-auth'] || '');
    const remoteIp = String((req.socket && req.socket.remoteAddress) || req.ip || '');
    const isLoopback = remoteIp === '127.0.0.1' || remoteIp === '::1' || remoteIp === '::ffff:127.0.0.1';

    if (!expectedSecret || !isLoopback) {
        return res.status(403).json({ code: 403, data: null, error: 'Forbidden', message: 'Direct access to internal admin auth endpoint is not allowed.' });
    }

    const expectedBuf = Buffer.from(expectedSecret);
    const providedBuf = Buffer.from(providedSecret);
    if (expectedBuf.length !== providedBuf.length || !crypto.timingSafeEqual(expectedBuf, providedBuf)) {
        return res.status(403).json({ code: 403, data: null, error: 'Forbidden', message: 'Invalid internal authentication secret.' });
    }

    return next();
}

class AuthModule {

    constructor() {
        this.myRoutes = router;
        this.core();
    }

    core() {
        this.myRoutes.post('/sso', authRateLimiter, auth.ssoAuth);
        this.myRoutes.post('/admin', requireInternalAdminAuth, auth.adminAuth);
        this.myRoutes.post('/user', authRateLimiter, auth.userAuth);
        this.myRoutes.post('/info', auth.info);
        this.myRoutes.post('/info-custom', auth.infoCustom);
        this.myRoutes.post('/validate-otp-2fa', authRateLimiter, auth.validateOTP2FA);
        this.myRoutes.post('/validate-otp-2fa-organization', authRateLimiter, auth.validateOTP2FAOrganization);

        this.myRoutes.post('/role-account-switch', AuthMiddleware.authenticate, auth.accountSwitch);
        this.myRoutes.post('/admin-send-email', AuthMiddleware.authenticate, auth.adminSendEmail);
        this.myRoutes.post('/admin-resend-email', authRateLimiter, auth.adminSendEmail);
        this.myRoutes.post('/employee-resend-email', authRateLimiter, auth.employeeSendEmail);

        this.myRoutes.get('/logout', AuthMiddleware.authenticate, auth.logout);
        this.myRoutes.get('/agent-logout', AuthMiddleware.authenticate, auth.agentLogout);

        this.myRoutes.post("/amember-logout", auth.amemberLogout);

        this.myRoutes.use('/', new ResellerAuthRoutes().getRoutes());
    }

    getRouters() {
        return this.myRoutes;
    }
}

module.exports = AuthModule;