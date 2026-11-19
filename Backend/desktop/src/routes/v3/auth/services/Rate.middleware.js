const rateLimit = require('express-rate-limit');

const APIAuthRateLimiter = rateLimit({
  windowMs: 1 * 60 * 1000, // 60 Seconds in milliseconds
  max: parseInt(process.env.AUTH_RATE_LIMIT_MAX || '60', 10),
  message: { code: 429, data: null, error: 'TooManyRequests', message: "You have reached maximum retries. Please try again after 1 minute" },
  statusCode: 429,
  standardHeaders: true,
  legacyHeaders: false,
});

const APIRateLimiterSystemInfo = rateLimit({
  windowMs: 1 * 60 * 1000, // 60 Seconds in milliseconds
  max: 4, // total 4*3 request per minutes
  message: "You have reached maximum retries. Please try again after 1 minutes", 
  statusCode: 429,
  standardHeaders: true,
  legacyHeaders: false,
});

module.exports = { APIAuthRateLimiter, APIRateLimiterSystemInfo }