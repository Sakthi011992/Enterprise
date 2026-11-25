// Converts a print payload (see backend PLAN 1.4 and modules/printing/print-renderer.ts) into ESC/POS bytes.

export interface PayloadLine {
  text: string;
  bold?: boolean;
  align?: 'left' | 'center' | 'right';
  size?: 1 | 2;
}

export interface PrintPayload {
  lines: PayloadLine[];
  cut: boolean;
  openDrawer?: boolean;
  copies?: number;
}

const ESC = 0x1b;
const GS = 0x1d;
const LF = 0x0a;

const ALIGN: Record<NonNullable<PayloadLine['align']>, number> = { left: 0, center: 1, right: 2 };

/**
 * Text is sent as 7-bit ASCII. Characters outside ASCII become "?" because most thermal printers ship
 * with a Western code page; Tamil or other scripts need a printer code page set up separately.
 */
export function asciiBytes(text: string): Buffer {
  return Buffer.from(text.replace(/[^\x20-\x7e]/g, '?'), 'ascii');
}

/** One copy of the job: init, drawer pulse, lines, cut. */
export function toEscPos(payload: PrintPayload): Buffer {
  const parts: Buffer[] = [Buffer.from([ESC, 0x40])]; // ESC @  initialise

  if (payload.openDrawer) {
    parts.push(Buffer.from([ESC, 0x70, 0x00, 0x19, 0xfa])); // ESC p 0 25 250  drawer pulse
  }

  for (const line of payload.lines) {
    parts.push(Buffer.from([ESC, 0x61, ALIGN[line.align ?? 'left']])); // ESC a n  alignment
    parts.push(Buffer.from([ESC, 0x45, line.bold ? 1 : 0])); // ESC E n  bold
    parts.push(Buffer.from([GS, 0x21, line.size === 2 ? 0x11 : 0x00])); // GS ! n  double size
    parts.push(asciiBytes(line.text));
    parts.push(Buffer.from([LF]));
  }

  // Reset emphasis and alignment before the cut so the next job starts clean.
  parts.push(Buffer.from([ESC, 0x45, 0, ESC, 0x61, 0, GS, 0x21, 0x00]));
  if (payload.cut) parts.push(Buffer.from([GS, 0x56, 66, 0])); // GS V 66 0  feed and partial cut

  return Buffer.concat(parts);
}

/** `copies` copies of the job, for jobs that print paper. The drawer pulse is never repeated. */
export function jobBytes(kind: string, payload: PrintPayload, copies: number): Buffer {
  const once = toEscPos(payload);
  if (kind === 'DRAWER') return once;
  const n = Math.max(1, Math.min(10, Math.floor(copies)));
  return Buffer.concat(Array.from({ length: n }, () => once));
}
