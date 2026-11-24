import { Injectable } from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';
import * as XLSX from 'xlsx';

@Injectable()
export class LocalisationService {
  constructor(private prisma: PrismaService) {}

  async getBundle(locale: string): Promise<Record<string, string>> {
    const values = await this.prisma.translationValue.findMany({
      where: { locale },
      include: { key: true },
    });
    const result: Record<string, string> = {};
    for (const v of values) result[v.key.key] = v.value;
    return result;
  }

  async get(key: string, locale: string): Promise<string> {
    const row = await this.prisma.translationValue.findFirst({
      where: { key: { key }, locale },
    });
    if (row) return row.value;
    if (locale !== 'en') return this.get(key, 'en');
    return key;
  }

  async upsertKey(key: string, description?: string) {
    return this.prisma.translationKey.upsert({
      where: { key },
      create: { key, description },
      update: { description },
    });
  }

  async upsertValue(key: string, locale: string, value: string) {
    const keyRow = await this.upsertKey(key);
    return this.prisma.translationValue.upsert({
      where: { keyId_locale: { keyId: keyRow.id, locale } },
      create: { keyId: keyRow.id, locale, value },
      update: { value },
    });
  }

  async exportExcel(locale: string): Promise<Buffer> {
    const keys = await this.prisma.translationKey.findMany({
      include: { values: { where: { locale } } },
      orderBy: { key: 'asc' },
    });
    const rows = keys.map((k) => ({
      key: k.key,
      description: k.description ?? '',
      value: k.values[0]?.value ?? '',
    }));
    const ws = XLSX.utils.json_to_sheet(rows);
    const wb = XLSX.utils.book_new();
    XLSX.utils.book_append_sheet(wb, ws, locale);
    return Buffer.from(XLSX.write(wb, { type: 'buffer', bookType: 'xlsx' }));
  }

  async importExcel(buffer: Buffer, locale: string) {
    const wb = XLSX.read(buffer, { type: 'buffer' });
    const ws = wb.Sheets[wb.SheetNames[0]];
    const rows = XLSX.utils.sheet_to_json<{ key: string; value: string }>(ws);
    let created = 0;
    let updated = 0;
    for (const row of rows) {
      if (!row.key) continue;
      const existing = await this.prisma.translationValue.findFirst({
        where: { key: { key: row.key }, locale },
      });
      await this.upsertValue(row.key, locale, row.value ?? '');
      existing ? updated++ : created++;
    }
    return { created, updated };
  }

  async setUserLocale(userId: string, locale: string) {
    return this.prisma.userLocalePreference.upsert({
      where: { userId },
      create: { userId, locale },
      update: { locale },
    });
  }
}
