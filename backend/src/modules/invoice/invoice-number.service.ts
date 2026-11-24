import { Injectable } from '@nestjs/common';
import { Prisma } from '@prisma/client';

@Injectable()
export class InvoiceNumberService {
  /**
   * Allocates the next gap-free sequential number for a country profile.
   * Must be called inside a Prisma interactive transaction.
   */
  async next(
    tx: Prisma.TransactionClient,
    countryProfileId: string,
    prefix: string,
    resetPeriod: string,
  ): Promise<string> {
    const periodKey = this.periodKey(resetPeriod);

    const counter = await tx.invoiceCounter.upsert({
      where: { countryProfileId_periodKey: { countryProfileId, periodKey } },
      create: { countryProfileId, periodKey, lastSeq: 0 },
      update: {},
    });

    const next = counter.lastSeq + 1;
    await tx.invoiceCounter.update({
      where: { countryProfileId_periodKey: { countryProfileId, periodKey } },
      data: { lastSeq: next },
    });

    const seq = String(next).padStart(6, '0');
    return periodKey ? `${prefix}/${periodKey}/${seq}` : `${prefix}/${seq}`;
  }

  private periodKey(resetPeriod: string): string {
    const now = new Date();
    const year = now.getFullYear();
    if (resetPeriod === 'CALENDAR_YEAR') return String(year);
    if (resetPeriod === 'FINANCIAL_YEAR') {
      // April–March financial year
      const fy = now.getMonth() >= 3 ? year : year - 1;
      return `${fy}-${String(fy + 1).slice(2)}`;
    }
    return '';
  }
}
