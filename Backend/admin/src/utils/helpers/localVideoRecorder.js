'use strict';

const fs = require('fs');
const path = require('path');
const { execFile } = require('child_process');
const moment = require('moment-timezone');

// In-flight deduplication locks so concurrent admin requests share one ffmpeg encode
const inFlightBuilds = new Map();

/**
 * Parse capture timestamp from either dlp-monitor.ps1 or aca-agent.exe screenshot filenames.
 * Supported formats:
 *   1) 0-0-screenshot_2026-11-20_16-49-08.jpg  (UTC)
 *   2) 0-0-16-2026-11-17 16-48-00-sc0.jpg      (UTC)
 *   3) Fallback: file mtime
 */
function parseScreenshotTimestamp(fileName, fullPath, timezone = 'America/Bogota') {
    const tz = timezone || 'America/Bogota';
    let mUtc = null;

    // Format 1: screenshot_YYYY-MM-DD_HH-mm-ss (UTC)
    const dlpMatch = fileName.match(/screenshot_(\d{4}-\d{2}-\d{2})_(\d{2})-(\d{2})-(\d{2})/i);
    if (dlpMatch) {
        mUtc = moment.utc(`${dlpMatch[1]} ${dlpMatch[2]}:${dlpMatch[3]}:${dlpMatch[4]}`, 'YYYY-MM-DD HH:mm:ss', true);
    }

    // Format 2: HH-YYYY-MM-DD HH-mm-ss-sc0 (UTC)
    if (!mUtc || !mUtc.isValid()) {
        const qtMatch = fileName.match(/(\d{4}-\d{2}-\d{2})\s+(\d{2})-(\d{2})-(\d{2})/);
        if (qtMatch) {
            mUtc = moment.utc(`${qtMatch[1]} ${qtMatch[2]}:${qtMatch[3]}:${qtMatch[4]}`, 'YYYY-MM-DD HH:mm:ss', true);
        }
    }

    let stat = null;
    try {
        stat = fs.statSync(fullPath);
    } catch {
        return null;
    }

    // Ignore corrupt/empty files (< 1 KB)
    if (!stat || stat.size < 1024) return null;

    if (!mUtc || !mUtc.isValid()) {
        mUtc = moment.utc(stat.mtime);
    }

    const mLocal = mUtc.clone().tz(tz);
    const localDate = mLocal.format('YYYY-MM-DD');
    const hourKey = mLocal.format('HH');
    const displayTime = `${mLocal.format('H')}-${mLocal.format('YYYY-MM-DD HH:mm:ss')}.jpg`;

    return {
        fileName,
        fullPath,
        stat,
        epochMs: mUtc.valueOf(),
        localDate,
        hourKey,
        displayTime,
        localTimeStr: mLocal.format('HH:mm:ss'),
    };
}

/**
 * Collect local screenshots for a given user, local date, and [fromHour..toHour] range.
 * Scans UTC day folders [date-1, date, date+1] so UTC-5 / timezone rollovers never drop frames.
 */
function collectLocalScreenshotsByHour({ sharedBase, email, date, fromHour, toHour, timezone = 'America/Bogota' }) {
    const tz = timezone || 'America/Bogota';
    const buckets = new Map();
    for (let h = fromHour; h <= toHour; h++) {
        const hh = String(h).padStart(2, '0');
        buckets.set(hh, []);
    }

    if (!email) return buckets;

    const userDir = path.join(sharedBase, email);
    if (!fs.existsSync(userDir)) return buckets;

    // Candidate UTC day folders covering any timezone offset around local `date`
    const center = moment.utc(date, 'YYYY-MM-DD');
    const candidateDayFolders = [
        center.clone().subtract(1, 'day').format('YYYY-MM-DD'),
        center.format('YYYY-MM-DD'),
        center.clone().add(1, 'day').format('YYYY-MM-DD'),
    ];

    for (const dayFolder of candidateDayFolders) {
        const dirPath = path.join(userDir, dayFolder);
        if (!fs.existsSync(dirPath)) continue;
        let files;
        try {
            files = fs.readdirSync(dirPath).filter((f) => /\.(jpg|jpeg|png)$/i.test(f));
        } catch {
            continue;
        }
        for (const fileName of files) {
            const fullPath = path.join(dirPath, fileName);
            const parsed = parseScreenshotTimestamp(fileName, fullPath, tz);
            if (!parsed) continue;
            if (parsed.localDate !== date) continue;
            if (!buckets.has(parsed.hourKey)) continue;
            buckets.get(parsed.hourKey).push({
                ...parsed,
                dayFolder,
            });
        }
    }

    for (const [, list] of buckets) {
        list.sort((a, b) => a.epochMs - b.epochMs);
    }
    return buckets;
}

function runFfmpeg(args) {
    return new Promise((resolve, reject) => {
        execFile('ffmpeg', args, { timeout: 120000, maxBuffer: 4 * 1024 * 1024 }, (err, stdout, stderr) => {
            if (err) {
                return reject(new Error(stderr ? stderr.slice(-400) : err.message));
            }
            resolve({ stdout, stderr });
        });
    });
}

/**
 * Compile (or serve cached) 720p H.264 MP4 video for a single local hour of screenshots.
 */
async function buildHourlyVideoIfNeeded({ sharedBase, email, date, hourKey, frames }) {
    if (!frames || frames.length === 0) return null;

    const outDir = path.join(sharedBase, email, date);
    fs.mkdirSync(outDir, { recursive: true });

    const videoFileName = `rec_${date}_${hourKey}h.mp4`;
    const videoPath = path.join(outDir, videoFileName);
    const metaPath = path.join(outDir, `rec_${date}_${hourKey}h.meta.json`);

    const firstFrame = frames[0];
    const lastFrame = frames[frames.length - 1];
    const signature = `${frames.length}|${firstFrame.fileName}|${lastFrame.fileName}|${lastFrame.stat.mtimeMs}`;

    // Fast path: cached MP4 matches current frame set
    if (fs.existsSync(videoPath) && fs.existsSync(metaPath)) {
        try {
            const cached = JSON.parse(fs.readFileSync(metaPath, 'utf8'));
            if (cached.signature === signature && fs.statSync(videoPath).size > 1024) {
                return {
                    fileName: videoFileName,
                    dayFolder: date,
                    frameCount: cached.frameCount,
                    durationSec: cached.durationSec,
                    firstTime: cached.firstTime || `${hourKey}:00:00`,
                    lastTime: cached.lastTime || `${hourKey}:59:59`,
                    sizeBytes: fs.statSync(videoPath).size,
                };
            }
        } catch {}
    }

    if (inFlightBuilds.has(videoPath)) {
        return inFlightBuilds.get(videoPath);
    }

    const buildPromise = (async () => {
        // Choose crisp review cadence: 0.6s/frame (<=40), 0.4s/frame (<=120), 0.25s/frame (>120)
        const secPerFrame = frames.length <= 40 ? 0.6 : (frames.length <= 120 ? 0.4 : 0.25);
        const listPath = path.join(outDir, `.concat_${date}_${hourKey}_${Date.now()}.txt`);
        const tmpVideoPath = path.join(outDir, `.tmp_${videoFileName}_${Date.now()}.mp4`);

        try {
            const lines = [];
            for (const f of frames) {
                const escaped = f.fullPath.replace(/'/g, "'\\''");
                lines.push(`file '${escaped}'`);
                lines.push(`duration ${secPerFrame}`);
            }
            // ffmpeg concat demuxer requires repeating last file to honor its duration
            const lastEscaped = lastFrame.fullPath.replace(/'/g, "'\\''");
            lines.push(`file '${lastEscaped}'`);
            fs.writeFileSync(listPath, lines.join('\n') + '\n', 'utf8');

            const ffmpegArgs = [
                '-y',
                '-hide_banner',
                '-loglevel', 'error',
                '-f', 'concat',
                '-safe', '0',
                '-i', listPath,
                '-vf', 'scale=1280:720:force_original_aspect_ratio=decrease:flags=lanczos,pad=1280:720:(ow-iw)/2:(oh-ih)/2:black,format=yuv420p',
                '-c:v', 'libx264',
                '-pix_fmt', 'yuv420p',
                '-preset', 'veryfast',
                '-crf', '24',
                '-r', '10',
                '-movflags', '+faststart',
                '-an',
                tmpVideoPath,
            ];

            await runFfmpeg(ffmpegArgs);
            fs.renameSync(tmpVideoPath, videoPath);

            const durationSec = Math.max(1, Math.round(frames.length * secPerFrame));
            const meta = {
                signature,
                frameCount: frames.length,
                durationSec,
                firstTime: firstFrame.localTimeStr,
                lastTime: lastFrame.localTimeStr,
                resolution: '1280x720',
                generatedAt: new Date().toISOString(),
            };
            fs.writeFileSync(metaPath, JSON.stringify(meta), 'utf8');

            return {
                fileName: videoFileName,
                dayFolder: date,
                frameCount: frames.length,
                durationSec,
                firstTime: firstFrame.localTimeStr,
                lastTime: lastFrame.localTimeStr,
                sizeBytes: fs.statSync(videoPath).size,
            };
        } finally {
            try { if (fs.existsSync(listPath)) fs.unlinkSync(listPath); } catch {}
            try { if (fs.existsSync(tmpVideoPath)) fs.unlinkSync(tmpVideoPath); } catch {}
            inFlightBuilds.delete(videoPath);
        }
    })();

    inFlightBuilds.set(videoPath, buildPromise);
    return buildPromise;
}

module.exports = {
    parseScreenshotTimestamp,
    collectLocalScreenshotsByHour,
    buildHourlyVideoIfNeeded,
};
