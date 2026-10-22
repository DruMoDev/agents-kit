import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { SeenQueue, type SendResult } from "../src/lib/seen-queue";

type Call = { prs: number[]; keepalive: boolean };

function setup(results: (SendResult | "throw" | Promise<SendResult>)[] = []) {
  const calls: Call[] = [];
  const failed: number[][] = [];
  const queue = new SeenQueue({
    send: async (prs, keepalive) => {
      calls.push({ prs: [...prs], keepalive });
      const r = results.shift() ?? 204;
      if (r === "throw") throw new TypeError("Failed to fetch");
      return r;
    },
    onFail: (prs) => failed.push([...prs]),
  });
  return { queue, calls, failed };
}

beforeEach(() => vi.useFakeTimers());
afterEach(() => vi.useRealTimers());

describe("SeenQueue", () => {
  it("agrupa los PR añadidos en ~1 s en una sola petición", async () => {
    const { queue, calls, failed } = setup();
    queue.add([11]);
    await vi.advanceTimersByTimeAsync(300);
    queue.add([14]);
    queue.add([14, 7]);
    expect(calls).toHaveLength(0);
    await vi.advanceTimersByTimeAsync(1000);
    expect(calls).toEqual([{ prs: [11, 14, 7], keepalive: true }]);
    expect(failed).toEqual([]);
    expect(queue.idle).toBe(true);
  });

  it("solo una petición en vuelo; lo añadido mientras tanto sale después y al menos 1 s más tarde", async () => {
    let release!: (r: SendResult) => void;
    const slow = new Promise<SendResult>((r) => (release = r));
    const { queue, calls } = setup([slow, 204]);
    queue.add([1]);
    await vi.advanceTimersByTimeAsync(1000);
    expect(calls).toHaveLength(1);
    queue.add([2]);
    await vi.advanceTimersByTimeAsync(5000);
    expect(calls).toHaveLength(1);
    release(204);
    await vi.advanceTimersByTimeAsync(999);
    expect(calls).toHaveLength(1);
    await vi.advanceTimersByTimeAsync(1);
    expect(calls.map((c) => c.prs)).toEqual([[1], [2]]);
  });

  it("429, 503 y fallo de red: reintenta con espera creciente y junta lo nuevo", async () => {
    const { queue, calls, failed } = setup([429, "throw", 503, 204]);
    queue.add([1]);
    await vi.advanceTimersByTimeAsync(1000);
    expect(calls).toHaveLength(1);
    queue.add([2]);
    await vi.advanceTimersByTimeAsync(1000);
    expect(calls.map((c) => c.prs)).toEqual([[1], [1, 2]]);
    await vi.advanceTimersByTimeAsync(1999);
    expect(calls).toHaveLength(2);
    await vi.advanceTimersByTimeAsync(1);
    expect(calls).toHaveLength(3);
    await vi.advanceTimersByTimeAsync(4000);
    expect(calls).toHaveLength(4);
    expect(calls[3].prs).toEqual([1, 2]);
    expect(failed).toEqual([]);
    expect(queue.idle).toBe(true);
  });

  it("si los reintentos se agotan, devuelve los PR a onFail", async () => {
    const { queue, calls, failed } = setup(Array(10).fill(503));
    queue.add([5, 6]);
    await vi.advanceTimersByTimeAsync(120_000);
    expect(calls.length).toBe(5);
    expect(failed).toEqual([[5, 6]]);
    expect(queue.idle).toBe(true);
  });

  it("error no reintentable (400, 404, 500): onFail sin reintentar", async () => {
    const { queue, calls, failed } = setup([404]);
    queue.add([9]);
    await vi.advanceTimersByTimeAsync(60_000);
    expect(calls).toHaveLength(1);
    expect(failed).toEqual([[9]]);
  });

  it("parte los lotes en trozos de 1000 como mucho", async () => {
    const { queue, calls } = setup();
    queue.add(Array.from({ length: 1500 }, (_, i) => i + 1));
    await vi.advanceTimersByTimeAsync(1000);
    expect(calls[0].prs).toHaveLength(1000);
    await vi.advanceTimersByTimeAsync(1000);
    expect(calls[1].prs).toHaveLength(500);
    expect(calls[1].prs[0]).toBe(1001);
  });

  it("flushNow (al salir de la página) manda lo pendiente sin esperar", async () => {
    const { queue, calls } = setup();
    queue.add([3]);
    queue.flushNow();
    await vi.advanceTimersByTimeAsync(0);
    expect(calls).toEqual([{ prs: [3], keepalive: true }]);
    await vi.advanceTimersByTimeAsync(5000);
    expect(calls).toHaveLength(1);
  });

  it("ignora ids que no son enteros positivos", async () => {
    const { queue, calls } = setup();
    queue.add([0, -1, 1.5, Number.NaN, 4]);
    await vi.advanceTimersByTimeAsync(1000);
    expect(calls[0].prs).toEqual([4]);
  });
});
