export const STORAGE_SERVICE = 'STORAGE_SERVICE';

export interface StorageService {
  /** Stores the buffer under `folder` and returns its public URL. */
  save(buffer: Buffer, originalName: string, folder: string): Promise<string>;
  /** Deletes the object behind a URL previously returned by save. Missing objects are ignored. */
  remove(url: string): Promise<void>;
}
