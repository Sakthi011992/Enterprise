import { Inject, Injectable } from '@nestjs/common';
import { apiError } from '../../common/filters/api-error';
import { STORAGE_SERVICE, StorageService } from '../uploads/storage.interface';

export const MAX_STOCK_UPLOAD_BYTES = 8 * 1024 * 1024;

/** Recognises jpg, png and pdf by their first bytes; the client's content type is not trusted. */
export function sniffStockFile(buffer: Buffer): 'jpg' | 'png' | 'pdf' | null {
  if (buffer.length >= 3 && buffer[0] === 0xff && buffer[1] === 0xd8 && buffer[2] === 0xff) return 'jpg';
  if (buffer.length >= 4 && buffer[0] === 0x89 && buffer[1] === 0x50 && buffer[2] === 0x4e && buffer[3] === 0x47) {
    return 'png';
  }
  if (buffer.length >= 4 && buffer.subarray(0, 4).toString('latin1') === '%PDF') return 'pdf';
  return null;
}

/** Photos for wastage and receiving (POST /stock/uploads). */
@Injectable()
export class StockUploadsService {
  constructor(@Inject(STORAGE_SERVICE) private storage: StorageService) {}

  async upload(file: Express.Multer.File | undefined): Promise<{ url: string }> {
    if (!file || !file.buffer || file.buffer.length === 0) throw apiError(400, 'INVALID_FILE', 'A file is required');
    if (file.buffer.length > MAX_STOCK_UPLOAD_BYTES) throw apiError(400, 'INVALID_FILE', 'The file is larger than 8 MB');
    if (!sniffStockFile(file.buffer)) {
      throw apiError(400, 'INVALID_FILE', 'Upload a jpg, png or pdf file');
    }
    const url = await this.storage.save(file.buffer, file.originalname, 'stock');
    return { url };
  }
}
