import { Injectable, Logger } from '@nestjs/common';

export interface UnsplashPhoto {
  id: string;
  urls: { regular: string; small: string };
  alt_description: string | null;
  user: { name: string; links: { html: string } };
  links: { download_location: string; html: string };
}

@Injectable()
export class UnsplashAdapter {
  private readonly logger = new Logger(UnsplashAdapter.name);
  private readonly accessKey = process.env.UNSPLASH_ACCESS_KEY ?? '';
  private readonly appName = process.env.APP_NAME ?? 'pos-billing';

  async search(query: string, page = 1): Promise<UnsplashPhoto[]> {
    if (!this.accessKey) return [];
    const url = `https://api.unsplash.com/search/photos?query=${encodeURIComponent(query)}&page=${page}&per_page=20&utm_source=${this.appName}&utm_medium=referral`;
    const res = await fetch(url, { headers: { Authorization: `Client-ID ${this.accessKey}` } });
    if (!res.ok) throw new Error(`Unsplash search failed: ${res.status}`);
    const data = await res.json() as { results: UnsplashPhoto[] };
    return data.results;
  }

  async pingDownload(downloadLocation: string): Promise<void> {
    if (!this.accessKey) return;
    try {
      await fetch(`${downloadLocation}?utm_source=${this.appName}&utm_medium=referral`, {
        headers: { Authorization: `Client-ID ${this.accessKey}` },
      });
    } catch {
      this.logger.warn('Unsplash download ping failed');
    }
  }

  async downloadBytes(imageUrl: string): Promise<Buffer> {
    const res = await fetch(imageUrl);
    if (!res.ok) throw new Error(`Failed to download image: ${res.status}`);
    return Buffer.from(await res.arrayBuffer());
  }
}
