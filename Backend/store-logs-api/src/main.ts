import { NestFactory } from '@nestjs/core';
import { AppModule } from './app.module';
import helmet from 'helmet';
import compression from 'compression';
import { SwaggerModule, DocumentBuilder } from '@nestjs/swagger';
import * as moment from 'moment-timezone';
import { ExecutionTimeInterceptor } from './common/interceptors/execution-time.interceptor';
import { json, urlencoded } from 'body-parser';

import swaggerMiddleware from "./common/swagger.auth";

async function bootstrap() {
    const app = await NestFactory.create(AppModule);

    app.use(helmet(), compression());
    const allowedOrigins = (process.env.ALLOWED_ORIGINS || '')
        .split(',')
        .map((o) => o.trim())
        .filter(Boolean);
    app.enableCors(
        allowedOrigins.length > 0
            ? { origin: allowedOrigins, credentials: true }
            : undefined,
    );
    // Timezone setting
    moment.tz.setDefault(process.env.TIMEZONE);

    // body Parser
    app.use(json({ limit: '50mb' }));
    app.use(urlencoded({ limit: '50mb', extended: true }));

    // Add global interceptor for calculating execution time for completing any req handler
    app.useGlobalInterceptors(new ExecutionTimeInterceptor());

    // Normalize /api/desktop/*, /api/activity/*, /api/clock-in/*, /desktop/* and /api/v1/activity/* for compatibility
    app.use((req, res, next) => {
        const origUrl = req.url;
        res.on('finish', () => {
            if (!origUrl.includes('add-activity') || res.statusCode >= 400) {
                console.log(`[HTTP-3001] ${req.method} ${origUrl} -> ${req.url} | status=${res.statusCode} | ip=${req.socket.remoteAddress}`);
            }
        });
        if (
            req.url.startsWith('/desktop/') ||
            req.url.startsWith('/activity/') ||
            req.url.startsWith('/clock-in/')
        ) {
            req.url = '/api/v1' + req.url;
            req.originalUrl = req.url;
        }
        if (
            req.url.startsWith('/api/desktop/') ||
            req.url.startsWith('/api/activity/') ||
            req.url.startsWith('/api/clock-in/')
        ) {
            req.url = req.url.replace('/api/', '/api/v1/');
            req.originalUrl = req.url;
        }
        if (req.url.startsWith('/api/v1/activity/')) {
            req.url = req.url.replace('/api/v1/activity/', '/api/v1/desktop/');
            req.originalUrl = req.url;
        }
        next();
    });

    // prefixing 'api' to all routes
    app.setGlobalPrefix('api');

    if (process.env.ENABLE_SWAGGER === 'true') {
        SwaggerModule.setup('/api/v1/explorer', app, SwaggerModule.createDocument(app, new DocumentBuilder()
            .setTitle('ACA Advisor Logs API')
            .setDescription('API documentation for ACA Advisor Store Logs Service')
            .setVersion('3.0.3')
            .addBearerAuth()
            .build(),
        ));
    }
    await app.listen(process.env.PORT);
}
bootstrap();
