// Cola del cliente para marcar visto: junta los PR abiertos en ~1 s, manda un único POST
// cada vez (KV admite 1 escritura por segundo y clave) y reintenta con espera creciente
// si el servidor dice 429/502/503/504 o falla la red. Si se rinde, devuelve los PR a onFail.

/** Código HTTP de la respuesta. */
export type SendResult = number;

export interface SeenQueueOptions {
  /** Manda un lote; devuelve el estado HTTP o lanza si falla la red. */
  send: (prs: number[], keepalive: boolean) => Promise<SendResult>;
  /** Lote que no se pudo guardar tras los reintentos (o con un error no reintentable). */
  onFail: (prs: number[]) => void;
  /** Espera para juntar PR y mínimo entre peticiones (ms). */
  debounceMs?: number;
  /** Intentos por lote, contando el primero. */
  maxAttempts?: number;
}

const MAX_BATCH = 1000;
const RETRYABLE = new Set([429, 502, 503, 504]);

const isPr = (n: unknown): n is number => typeof n === "number" && Number.isInteger(n) && n > 0;

export class SeenQueue {
  private pending: number[] = [];
  private timer: ReturnType<typeof setTimeout> | null = null;
  private inFlight = false;
  private attempts = 0;
  private readonly debounceMs: number;
  private readonly maxAttempts: number;

  constructor(private readonly opts: SeenQueueOptions) {
    this.debounceMs = opts.debounceMs ?? 1000;
    this.maxAttempts = opts.maxAttempts ?? 5;
  }

  /** Nada pendiente, en vuelo ni programado. */
  get idle(): boolean {
    return !this.inFlight && !this.timer && this.pending.length === 0;
  }

  add(prs: number[]): void {
    for (const pr of prs) if (isPr(pr) && !this.pending.includes(pr)) this.pending.push(pr);
    if (this.pending.length > 0) this.schedule(this.debounceMs);
  }

  /** Al salir de la página: manda ya lo pendiente (con keepalive). */
  flushNow(): void {
    if (this.timer) clearTimeout(this.timer);
    this.timer = null;
    if (this.pending.length > 0 && !this.inFlight) void this.flush();
  }

  private schedule(ms: number): void {
    if (this.timer || this.inFlight) return;
    this.timer = setTimeout(() => {
      this.timer = null;
      void this.flush();
    }, ms);
  }

  private async flush(): Promise<void> {
    if (this.inFlight || this.pending.length === 0) return;
    const batch = this.pending.splice(0, MAX_BATCH);
    this.inFlight = true;
    let status: number | null;
    try {
      status = await this.opts.send(batch, true);
    } catch {
      status = null;
    }
    this.inFlight = false;

    if (status !== null && status >= 200 && status < 300) {
      this.attempts = 0;
      if (this.pending.length > 0) this.schedule(this.debounceMs);
      return;
    }

    const retryable = status === null || RETRYABLE.has(status);
    this.attempts++;
    if (retryable && this.attempts < this.maxAttempts) {
      // el lote vuelve delante y se junta con lo que haya llegado mientras tanto
      this.pending = [...batch, ...this.pending.filter((pr) => !batch.includes(pr))];
      this.schedule(this.debounceMs * 2 ** (this.attempts - 1));
      return;
    }
    this.attempts = 0;
    this.opts.onFail(batch);
    if (this.pending.length > 0) this.schedule(this.debounceMs);
  }
}
