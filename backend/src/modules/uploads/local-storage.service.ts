import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { randomUUID } from 'crypto';
import { mkdir, unlink, writeFile } from 'fs/promises';
import { extname, join, resolve, sep } from 'path';
import { StorageService } from './storage.interface';

const SAFE_EXTENSION = /^\.[a-z0-9]{1,10}$/;
const UNSAFE_FOLDER_CHARS = /[^a-z0-9_-]/gi;
const URL_MARKER = '/uploads/';

/** Stores uploads on local disk under UPLOAD_DIR and serves them from /uploads (see main.ts). */
@Injectable()
export class LocalStorageService implements StorageService {
  private readonly logger = new Logger(LocalStorageService.name);
  private readonly uploadDir: string;
  private readonly publicBaseUrl: string;

  constructor(config: ConfigService) {
    this.uploadDir = resolve(process.cwd(), config.get<string>('UPLOAD_DIR', './uploads'));
    this.publicBaseUrl = config.get<string>('PUBLIC_BASE_URL', 'http://localhost:3000').replace(/\/+$/, '');
  }

  async save(buffer: Buffer, originalName: string, folder: string): Promise<string> {
    const safeFolder = folder.replace(UNSAFE_FOLDER_CHARS, '') || 'misc';
    const ext = extname(originalName).toLowerCase();
    const fileName = `${randomUUID()}${SAFE_EXTENSION.test(ext) ? ext : ''}`;

    const dir = join(this.uploadDir, safeFolder);
    await mkdir(dir, { recursive: true });
    await writeFile(join(dir, fileName), buffer);

    return `${this.publicBaseUrl}${URL_MARKER}${safeFolder}/${fileName}`;
  }

  async remove(url: string): Promise<void> {
    const index = url.indexOf(URL_MARKER);
    if (index < 0) return;

    let relative: string;
    try {
      relative = decodeURIComponent(url.slice(index + URL_MARKER.length));
    } catch {
      return;
    }

    const target = resolve(this.uploadDir, relative);
    if (!target.startsWith(this.uploadDir + sep)) {
      this.logger.warn(`Refusing to remove a path outside the upload folder: ${url}`);
      return;
    }

    try {
      await unlink(target);
    } catch (err) {
      if ((err as NodeJS.ErrnoException).code !== 'ENOENT') throw err;
    }
  }
}
