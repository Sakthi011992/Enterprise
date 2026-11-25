import * as net from 'net';
import { jobBytes, PrintPayload } from './escpos';

// Print agent: polls the POS API for queued print jobs and sends them to LAN printers.
// Required environment: API_BASE_URL (e.g. https://pos.example.com/api/v1) and DEVICE_KEY (the key shown once
// when the PRINTER device was registered in Settings -> Devices).

const POLL_INTERVAL_MS = 2000;
const SOCKET_TIMEOUT_MS = 5000;

interface AgentJob {
  id: string;
  kind: string;
  printer: { host: string | null; port: number; paperWidth: number; copies: number };
  payload: PrintPayload;
}

interface JobResult {
  ok: boolean;
  error?: string;
  printerStatus?: 'READY' | 'PAPER_LOW' | 'OFFLINE';
}

function requireEnv(name: string): string {
  const value = process.env[name];
  if (!value) {
    console.error(`Missing environment variable ${name}`);
    process.exit(1);
  }
  return value;
}

const API_BASE_URL = requireEnv('API_BASE_URL').replace(/\/$/, '');
const DEVICE_KEY = requireEnv('DEVICE_KEY');

const sleep = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

/** Writes bytes to a LAN printer over TCP and resolves once the socket closes cleanly. */
export function sendToPrinter(host: string, port: number, bytes: Buffer): Promise<void> {
  return new Promise((resolve, reject) => {
    const socket = net.createConnection({ host, port });
    socket.setTimeout(SOCKET_TIMEOUT_MS);
    socket.once('timeout', () => {
      socket.destroy();
      reject(new Error(`No response from ${host}:${port} within ${SOCKET_TIMEOUT_MS / 1000} s`));
    });
    socket.once('error', (err) => reject(new Error(`${host}:${port} ${err.message}`)));
    socket.once('connect', () => socket.end(bytes));
    socket.once('close', (hadError) => {
      if (!hadError) resolve();
    });
  });
}

async function fetchJobs(): Promise<AgentJob[]> {
  const res = await fetch(`${API_BASE_URL}/print-jobs/next`, { headers: { 'X-Device-Key': DEVICE_KEY } });
  if (!res.ok) throw new Error(`GET /print-jobs/next failed with ${res.status}`);
  return (await res.json()) as AgentJob[];
}

async function reportResult(jobId: string, result: JobResult): Promise<void> {
  const res = await fetch(`${API_BASE_URL}/print-jobs/${jobId}/result`, {
    method: 'POST',
    headers: { 'X-Device-Key': DEVICE_KEY, 'Content-Type': 'application/json' },
    body: JSON.stringify(result),
  });
  if (!res.ok) console.error(`Reporting job ${jobId} failed with ${res.status}`);
}

async function runJob(job: AgentJob): Promise<void> {
  const { host, port } = job.printer;
  if (!host) {
    await reportResult(job.id, { ok: false, error: 'Printer has no IP address', printerStatus: 'OFFLINE' });
    return;
  }
  try {
    await sendToPrinter(host, port, jobBytes(job.kind, job.payload, job.printer.copies));
    console.log(`Printed ${job.kind} job ${job.id} on ${host}:${port}`);
    await reportResult(job.id, { ok: true, printerStatus: 'READY' });
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    console.error(`Job ${job.id} failed: ${message}`);
    await reportResult(job.id, { ok: false, error: message, printerStatus: 'OFFLINE' });
  }
}

async function main(): Promise<void> {
  console.log(`Print agent polling ${API_BASE_URL} every ${POLL_INTERVAL_MS / 1000} s`);
  for (;;) {
    try {
      const jobs = await fetchJobs();
      for (const job of jobs) await runJob(job);
    } catch (err) {
      console.error(err instanceof Error ? err.message : String(err));
    }
    await sleep(POLL_INTERVAL_MS);
  }
}

if (require.main === module) {
  void main();
}
