'use strict';

const crypto = require('crypto');
const router = require('express').Router();
const auth = require('./auth.controller');

const { APIAuthRateLimiter } = require("./services/Rate.middleware");

function verifyEnrollmentKey(req, res, next) {
    const expected = process.env.AGENT_ENROLLMENT_KEY;
    if (!expected) return next();
    const provided = String(req.headers['x-enrollment-key'] || (req.body && req.body.enrollmentKey) || '');
    const expectedBuf = Buffer.from(String(expected));
    const providedBuf = Buffer.from(provided);
    if (expectedBuf.length !== providedBuf.length || !crypto.timingSafeEqual(expectedBuf, providedBuf)) {
        return res.status(403).json({ code: 403, data: null, error: 'Forbidden', message: 'Invalid or missing enrollment key' });
    }
    return next();
}

class AuthModule {

    constructor() {
        this.myRoutes = router;
        this.core();
    }

    core() {
        this.myRoutes.post('/register', APIAuthRateLimiter, verifyEnrollmentKey, auth.registerUsingMacAddress);
        this.myRoutes.post('/authenticate', APIAuthRateLimiter, auth.authenticate);
        this.myRoutes.post('/login', APIAuthRateLimiter, auth.authenticate);
        this.myRoutes.post('/authenticate-extension', APIAuthRateLimiter, auth.authenticateLoginAgent);
        this.myRoutes.post('/check-key', APIAuthRateLimiter, auth.keyCheck);
    }

    getRouters() {
        return this.myRoutes;
    }
}

module.exports = AuthModule;