import { Injectable } from '@nestjs/common';
import * as crypto from 'crypto';

@Injectable()
export class CryptoService {
    async decrypt(text: string, key: string): Promise<any> {
        try {
            const textParts = text.split(':')
            const iv = Buffer.from(textParts.shift(), 'hex')
            const encryptedText = Buffer.from(textParts.join(':'), 'hex')
            const keyBuf = Buffer.alloc(32);
            Buffer.from(key || '').copy(keyBuf);
            const decipher = crypto.createDecipheriv('aes-256-cbc', keyBuf, iv)
            let decrypted = decipher.update(encryptedText)

            decrypted = Buffer.concat([decrypted, decipher.final()])

            return { code: 200, error: null, decoded: decrypted.toString() }
        } catch (err) {
            return { code: 400, error: err, decoded: null }
        }
    }
}
