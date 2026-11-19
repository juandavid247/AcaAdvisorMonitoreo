'use strict';

const crypto = require('crypto');
const path = require('path');

const DEFAULT_TTL_SECONDS = parseInt(process.env.SCREENSHOT_URL_TTL_SECONDS || '3600', 10);

function getSigningSecret() {
    return (
        process.env.SCREENSHOT_SIGNING_SECRET ||
        process.env.JWT_ACCESS_TOKEN_SECRET ||
        process.env.SESSION_SECRET ||
        ''
    );
}

function computeSignature(canonicalPath, exp) {
    const secret = getSigningSecret();
    return crypto
        .createHmac('sha256', secret)
        .update(`${canonicalPath}|${exp}`)
        .digest('hex');
}

function signScreenshotUrl(baseUrl, email, dayFolder, fileName, ttlSeconds = DEFAULT_TTL_SECONDS) {
    const canonicalPath = `${email}/${dayFolder}/${fileName}`;
    const exp = Math.floor(Date.now() / 1000) + ttlSeconds;
    const sig = computeSignature(canonicalPath, exp);
    const encodedPath = `${encodeURIComponent(email)}/${encodeURIComponent(dayFolder)}/${encodeURIComponent(fileName)}`;
    return `${baseUrl}/${encodedPath}?exp=${exp}&sig=${sig}`;
}

function verifyScreenshotMiddleware(req, res, next) {
    try {
        const exp = parseInt(String(req.query.exp || ''), 10);
        const sig = String(req.query.sig || '');

        if (!exp || !sig || !/^[0-9a-f]{64}$/i.test(sig)) {
            return res.status(403).json({ code: 403, message: 'Forbidden: missing or invalid screenshot signature' });
        }

        const now = Math.floor(Date.now() / 1000);
        if (now > exp) {
            return res.status(403).json({ code: 403, message: 'Forbidden: screenshot link expired' });
        }

        let decodedPath;
        try {
            decodedPath = decodeURIComponent(req.path);
        } catch {
            return res.status(400).json({ code: 400, message: 'Invalid path encoding' });
        }

        if (decodedPath.includes('\0') || decodedPath.includes('\\') || decodedPath.includes('..')) {
            return res.status(403).json({ code: 403, message: 'Forbidden: invalid path' });
        }

        const normalized = path.posix.normalize(decodedPath).replace(/^\/+/, '');
        if (!normalized || normalized.startsWith('..')) {
            return res.status(403).json({ code: 403, message: 'Forbidden: invalid path' });
        }

        const expectedSig = computeSignature(normalized, exp);
        const expectedBuf = Buffer.from(expectedSig, 'hex');
        const providedBuf = Buffer.from(sig, 'hex');

        if (expectedBuf.length !== providedBuf.length || !crypto.timingSafeEqual(expectedBuf, providedBuf)) {
            return res.status(403).json({ code: 403, message: 'Forbidden: invalid screenshot signature' });
        }

        res.setHeader('Cache-Control', 'private, max-age=300');
        res.setHeader('X-Content-Type-Options', 'nosniff');
        return next();
    } catch {
        return res.status(403).json({ code: 403, message: 'Forbidden' });
    }
}

module.exports = {
    signScreenshotUrl,
    verifyScreenshotMiddleware,
};
