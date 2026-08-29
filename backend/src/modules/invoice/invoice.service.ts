import { Injectable, NotFoundException } from '@nestjs/common';
import { InvoiceStatus, DownloadContext, Prisma } from '@prisma/client';
import { PrismaService } from '../../prisma/prisma.service';
import { BlobStorageService } from '../../common/storage/blob-storage.service';
import { InvoiceNumberService } from './invoice-number.service';
import { InvoicePdfService } from './invoice-pdf.service';
import { GenerateInvoiceDto, AuditQueryDto } from './dto/invoice.dto';

@Injectable()
export class InvoiceService {
  constructor(
    private prisma: PrismaService,
    private blobs: BlobStorageService,
    private numberSvc: InvoiceNumberService,
    private pdfSvc: InvoicePdfService,
  ) {}

  private async resolveProfile(countryCode = 'IN') {
    const profile = await this.prisma.invoiceCountryProfile.findUnique({
      where: { countryCode },
    });
    if (!profile) throw new NotFoundException(`No invoice profile for country: ${countryCode}`);
    return profile;
  }

  async generate(dto: GenerateInvoiceDto, actorId?: string) {
    const order = await this.prisma.order.findUnique({
      where: { id: dto.orderId },
      include: { items: true },
    });
    if (!order) throw new NotFoundException('Order not found');

    const profile = await this.resolveProfile(dto.countryCode ?? 'IN');

    return this.prisma.$transaction(async (tx) => {
      const invoiceNumber = await this.numberSvc.next(
        tx,
        profile.id,
        profile.numberPrefix,
        profile.resetPeriod,
      );

      const taxBreakdown = this.buildTaxBreakdown(order.items as any[], profile.taxBreakdownMode);

      const { buffer, contentHash } = await this.pdfSvc.generate({
        invoiceNumber,
        orderId: order.id,
        issuedAt: new Date().toLocaleDateString(),
        items: order.items,
        subtotal: order.subtotal.toString(),
        taxAmount: order.taxAmount.toString(),
        grandTotal: order.grandTotal.toString(),
      });

      const stored = await this.blobs.store(buffer, { mimeType: 'application/pdf', folder: 'invoices' });

      return tx.invoice.create({
        data: {
          invoiceNumber,
          orderId: order.id,
          countryProfileId: profile.id,
          taxBreakdown,
          subtotal: order.subtotal,
          taxAmount: order.taxAmount,
          grandTotal: order.grandTotal,
          blobPath: stored.blobPath,
          contentHash,
        },
      });
    });
  }

  private buildTaxBreakdown(items: any[], mode: string) {
    if (mode === 'SPLIT_COMPONENTS') {
      return items.map((i) => ({
        item: i.productName,
        cgst: Number(i.taxAmount) / 2,
        sgst: Number(i.taxAmount) / 2,
      }));
    }
    return items.map((i) => ({ item: i.productName, tax: Number(i.taxAmount) }));
  }

  async voidInvoice(id: string) {
    const inv = await this.prisma.invoice.findUnique({ where: { id } });
    if (!inv) throw new NotFoundException('Invoice not found');
    return this.prisma.invoice.update({
      where: { id },
      data: { status: InvoiceStatus.VOIDED, voidedAt: new Date() },
    });
  }

  async findAudit(q: AuditQueryDto) {
    const where: Prisma.InvoiceWhereInput = {
      ...(q.countryCode ? { countryProfile: { countryCode: q.countryCode } } : {}),
      ...(q.status ? { status: q.status as InvoiceStatus } : {}),
      ...(q.invoiceNumber ? { invoiceNumber: { contains: q.invoiceNumber } } : {}),
      ...(q.from || q.to
        ? { issuedAt: { ...(q.from ? { gte: new Date(q.from) } : {}), ...(q.to ? { lte: new Date(q.to) } : {}) } }
        : {}),
    };
    const page = q.page ?? 1;
    const limit = q.limit ?? 20;
    const [data, total] = await this.prisma.$transaction([
      this.prisma.invoice.findMany({
        where,
        skip: (page - 1) * limit,
        take: limit,
        orderBy: { issuedAt: 'desc' },
        include: { countryProfile: { select: { countryCode: true } } },
      }),
      this.prisma.invoice.count({ where }),
    ]);
    return { data, meta: { total, page, limit, pages: Math.ceil(total / limit) } };
  }

  async download(id: string, actorId?: string, ip?: string) {
    const inv = await this.prisma.invoice.findUnique({ where: { id } });
    if (!inv || !inv.blobPath) throw new NotFoundException('Invoice PDF not found');

    await this.prisma.invoiceDownloadLog.create({
      data: { invoiceId: id, context: DownloadContext.SINGLE, actorId, ipAddress: ip },
    });

    const buffer = await this.blobs.read(inv.blobPath);
    return { buffer, invoiceNumber: inv.invoiceNumber };
  }

  async bulkExport(ids: string[]) {
    // Stub: logs and returns IDs — zip assembly to be added
    await Promise.all(
      ids.map((id) =>
        this.prisma.invoiceDownloadLog.create({
          data: { invoiceId: id, context: DownloadContext.BULK_EXPORT },
        }),
      ),
    );
    return { queued: ids.length, ids };
  }
}
