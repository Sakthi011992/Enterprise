import { Injectable, Logger } from '@nestjs/common';
import * as fs from 'fs/promises';
import * as path from 'path';
import * as crypto from 'crypto';

/**
 * Content-addressed local blob store.
 * In production swap the fs calls for S3/GCS/Azure SDK calls.
 */
@Injectable()
export class BlobStorageService {
  private readonly logger = new Logger(BlobStorageService.name);
  private readonly root = process.env.BLOB_STORAGE_PATH ?? path.join(process.cwd(), 'blob-store');

  async store(
    buffer: Buffer,
    opts: { mimeType: string; folder?: string },
  ): Promise<{ blobPath: string; contentHash: string; sizeBytes: number }> {
    const contentHash = crypto.createHash('sha256').update(buffer).digest('hex');
    const folder = opts.folder ?? 'misc';
    const ext = mimeToExt(opts.mimeType);
    const blobPath = `${folder}/${contentHash}${ext}`;
    const fullPath = path.join(this.root, blobPath);

    await fs.mkdir(path.dirname(fullPath), { recursive: true });
    await fs.writeFile(fullPath, buffer);

    return { blobPath, contentHash, sizeBytes: buffer.byteLength };
  }

  async read(blobPath: string): Promise<Buffer> {
    return fs.readFile(path.join(this.root, blobPath));
  }

  async delete(blobPath: string): Promise<void> {
    try {
      await fs.unlink(path.join(this.root, blobPath));
    } catch {
      this.logger.warn(`Blob not found for delete: ${blobPath}`);
    }
  }

  publicUrl(blobPath: string): string {
    const base = process.env.BLOB_BASE_URL ?? '/blobs';
    return `${base}/${blobPath}`;
  }
}

function mimeToExt(mime: string): string {
  const map: Record<string, string> = {
    'image/webp': '.webp',
    'image/png': '.png',
    'image/jpeg': '.jpg',
    'image/svg+xml': '.svg',
    'application/pdf': '.pdf',
  };
  return map[mime] ?? '';
}
