import { Injectable, Logger } from '@nestjs/common';
import * as Handlebars from 'handlebars';
import * as crypto from 'crypto';

const TEMPLATE = `
<!DOCTYPE html><html><head>
<meta charset="utf-8">
<style>
  body { font-family: sans-serif; margin: 40px; color: #111; }
  h1 { font-size: 1.4em; }
  .meta { display: flex; justify-content: space-between; margin-bottom: 20px; }
  table { width: 100%; border-collapse: collapse; margin-top: 20px; }
  th, td { border: 1px solid #ccc; padding: 8px 12px; text-align: left; }
  th { background: #f4f4f5; }
  .totals { margin-top: 16px; text-align: right; }
  .totals div { margin: 4px 0; }
  .grand { font-weight: bold; font-size: 1.1em; }
</style>
</head><body>
<div class="meta">
  <div><h1>Invoice</h1><div>{{invoiceNumber}}</div></div>
  <div><div>Date: {{issuedAt}}</div><div>Order: {{orderId}}</div></div>
</div>
<table>
  <thead><tr><th>Item</th><th>Qty</th><th>Price</th><th>Tax</th><th>Total</th></tr></thead>
  <tbody>
  {{#each items}}
    <tr>
      <td>{{productName}}</td>
      <td>{{quantity}}</td>
      <td>{{price}}</td>
      <td>{{taxPercentage}}%</td>
      <td>{{lineTotal}}</td>
    </tr>
  {{/each}}
  </tbody>
</table>
<div class="totals">
  <div>Subtotal: {{subtotal}}</div>
  <div>Tax: {{taxAmount}}</div>
  <div class="grand">Total: {{grandTotal}}</div>
</div>
</body></html>
`;

const compiled = Handlebars.compile(TEMPLATE);

@Injectable()
export class InvoicePdfService {
  private readonly logger = new Logger(InvoicePdfService.name);

  async generate(data: Record<string, any>): Promise<{ buffer: Buffer; contentHash: string }> {
    const html = compiled(data);

    let buffer: Buffer;
    try {
      // Dynamic import so the rest of the app boots even if Puppeteer is unavailable
      const puppeteer = await import('puppeteer');
      const browser = await puppeteer.default.launch({ args: ['--no-sandbox', '--disable-setuid-sandbox'] });
      const page = await browser.newPage();
      await page.setContent(html, { waitUntil: 'networkidle0' });
      const pdf = await page.pdf({ format: 'A4', printBackground: true });
      await browser.close();
      buffer = Buffer.from(pdf);
    } catch (err) {
      this.logger.warn(`Puppeteer PDF generation failed, falling back to HTML: ${err}`);
      buffer = Buffer.from(html, 'utf-8');
    }

    const contentHash = crypto.createHash('sha256').update(buffer).digest('hex');
    return { buffer, contentHash };
  }
}
