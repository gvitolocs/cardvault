#!/usr/bin/env bun
import { mkdirSync, readFileSync, writeFileSync } from "fs";
import localtunnel from "localtunnel";
import { homedir } from "node:os";
import { join } from "path";

// ─── Config ──────────────────────────────────────────────────────────────────
// Windows often has USERPROFILE but not HOME; never use "~" as a path segment
// (join would treat it as a relative folder and create ./~ in the project).
const HOME = process.env.HOME || homedir();
const PORT = 3000;
const API_URL = "https://chatgpt.com/backend-api/codex/responses";
const AUTH_PATH = join(HOME, ".codex", "auth.json");
const CONFIG_DIR = join(HOME, ".codex", "cursor-proxy");
const CONFIG_PATH = join(CONFIG_DIR, "config.json");
const DEFAULT_SUBDOMAIN =
  (process.env.CODEX_CURSOR_PROXY_SUBDOMAIN || "pokoin-gv-codex").trim().toLowerCase();

// Parameters the Codex Responses API accepts
const ALLOWED_PARAMS = new Set([
  "model",
  "input",
  "instructions",
  "tools",
  "tool_choice",
  "store",
  "include",
  "stream",
  "reasoning",
  "temperature",
  "top_p",
  "max_output_tokens",
  "truncation",
  "text",
  "parallel_tool_calls",
  "previous_response_id",
]);

const REASONING_EFFORT_VALUES = new Set([
  "none",
  "minimal",
  "low",
  "medium",
  "high",
  "xhigh",
]);

function normalizeReasoningEffort(value: unknown): string | null {
  const effort = String(value ?? "").trim().toLowerCase();
  if (!effort) return null;
  if (effort === "extra_high" || effort === "extra-high" || effort === "extrahigh") {
    return "xhigh";
  }
  return REASONING_EFFORT_VALUES.has(effort) ? effort : null;
}

function normalizeInputMessage(msg: Record<string, unknown>): Record<string, unknown> {
  const role = String(msg.role ?? "user");
  const content = msg.content;
  if (typeof content === "string") {
    return { role, content };
  }
  if (Array.isArray(content)) {
    return { role, content };
  }
  return { role, content: String(content ?? "") };
}

// ─── Auth ────────────────────────────────────────────────────────────────────

function getAccessToken(): string {
  try {
    const auth = JSON.parse(readFileSync(AUTH_PATH, "utf-8"));
    return auth?.tokens?.access_token ?? "";
  } catch {
    console.error("[proxy] Could not read", AUTH_PATH);
    return "";
  }
}

// ─── Tunnel ──────────────────────────────────────────────────────────────────

function readConfig(): Record<string, unknown> {
  try {
    return JSON.parse(readFileSync(CONFIG_PATH, "utf-8")) as Record<string, unknown>;
  } catch {
    return {};
  }
}

function writeConfig(patch: Record<string, unknown>) {
  const config = { ...readConfig(), ...patch };
  mkdirSync(CONFIG_DIR, { recursive: true });
  writeFileSync(CONFIG_PATH, JSON.stringify(config, null, 2) + "\n");
}

function getSubdomain(): string {
  const config = readConfig();
  const existing =
    typeof config.subdomain === "string" ? config.subdomain.trim().toLowerCase() : "";

  // Older installs used random ULIDs that localtunnel often does not reserve.
  if (existing && !existing.startsWith("01") && existing.length <= 32) {
    return existing;
  }

  writeConfig({ subdomain: DEFAULT_SUBDOMAIN });
  return DEFAULT_SUBDOMAIN;
}

function resolveFinishReason(resp: Record<string, unknown> | undefined): string {
  if (!resp) return "stop";

  const status = String(resp.status ?? "");
  const incomplete = resp.incomplete_details as Record<string, unknown> | undefined;
  if (status === "incomplete" || incomplete) {
    const reason = String(incomplete?.reason ?? "");
    if (reason === "max_output_tokens") return "length";
    if (reason) return reason;
    return "length";
  }

  return "stop";
}

// ─── Request transformation ──────────────────────────────────────────────────

function sanitizeBody(body: Record<string, unknown>): Record<string, unknown> {
  // Convert Chat Completions-style payloads into Responses-style input.
  if (!Array.isArray(body.input) && Array.isArray(body.messages)) {
    body.input = body.messages
      .filter((msg): msg is Record<string, unknown> => Boolean(msg && typeof msg === "object"))
      .map((msg) => normalizeInputMessage(msg));
  }

  // Convert reasoning_effort into Responses reasoning object.
  const effort = normalizeReasoningEffort(body.reasoning_effort);
  if (effort) {
    const existing = body.reasoning;
    body.reasoning = typeof existing === "object" && existing !== null && !Array.isArray(existing)
      ? { ...existing as Record<string, unknown>, effort }
      : { effort };
  }

  // Promote the first system message to the top-level `instructions` field
  if (!body.instructions && Array.isArray(body.input)) {
    const idx = body.input.findIndex((m: { role?: string }) => m.role === "system");
    if (idx !== -1) {
      body.instructions = body.input[idx].content;
      body.input.splice(idx, 1);
    }
  }

  body.store = false;
  body.stream = true;

  for (const key of Object.keys(body)) {
    if (!ALLOWED_PARAMS.has(key)) delete body[key];
  }

  return body;
}

// ─── Response stream translation ─────────────────────────────────────────────
// Converts Responses API SSE events into Chat Completions SSE chunks so that
// clients like Cursor (which speak the completions protocol) can consume them.

function responsesToCompletionsStream(
  upstream: ReadableStream<Uint8Array>,
  model: string,
): ReadableStream<Uint8Array> {
  const encoder = new TextEncoder();
  const decoder = new TextDecoder();

  let buffer = "";
  let id = "chatcmpl-" + crypto.randomUUID();
  const created = Math.floor(Date.now() / 1000);
  const toolIndices = new Map<string, number>();
  let nextToolIdx = 0;

  function chunk(delta: Record<string, unknown>, finish: string | null = null) {
    return `data: ${JSON.stringify({
      id,
      object: "chat.completion.chunk",
      created,
      model,
      choices: [{ index: 0, delta, finish_reason: finish }],
    })}\n\n`;
  }

  return new ReadableStream({
    async start(controller) {
      const reader = upstream.getReader();
      controller.enqueue(encoder.encode(chunk({ role: "assistant" })));

      try {
        while (true) {
          const { done, value } = await reader.read();
          if (done) break;

          buffer += decoder.decode(value, { stream: true });
          const lines = buffer.split("\n");
          buffer = lines.pop() ?? "";

          let eventType = "";
          for (const line of lines) {
            if (line.startsWith("event: ")) {
              eventType = line.slice(7).trim();
              continue;
            }
            if (!line.startsWith("data: ")) continue;

            let evt: Record<string, unknown>;
            try {
              evt = JSON.parse(line.slice(6));
            } catch {
              continue;
            }

            const type = (evt.type as string) ?? eventType;

            if (type === "response.output_text.delta") {
              const d = evt.delta as string;
              if (d) controller.enqueue(encoder.encode(chunk({ content: d })));
            } else if (type === "response.reasoning.delta") {
              const d = evt.delta as string;
              if (d) controller.enqueue(encoder.encode(chunk({ reasoning_content: d })));
            } else if (type === "response.output_item.added") {
              const item = evt.item as Record<string, unknown> | undefined;
              if (item?.type === "function_call") {
                const idx = nextToolIdx++;
                toolIndices.set(item.id as string, idx);
                controller.enqueue(
                  encoder.encode(
                    chunk({
                      tool_calls: [{
                        index: idx,
                        id: item.call_id ?? item.id,
                        type: "function",
                        function: { name: item.name as string, arguments: "" },
                      }],
                    }),
                  ),
                );
              }
            } else if (type === "response.function_call_arguments.delta") {
              const d = evt.delta as string;
              if (d) {
                const idx = toolIndices.get(evt.item_id as string) ?? 0;
                controller.enqueue(
                  encoder.encode(
                    chunk({ tool_calls: [{ index: idx, function: { arguments: d } }] }),
                  ),
                );
              }
            } else if (
              type === "response.completed" ||
              type === "response.incomplete" ||
              type === "response.failed"
            ) {
              const resp = evt.response as Record<string, unknown> | undefined;
              if (resp) id = (resp.id as string) ?? id;
              const usage = resp?.usage as Record<string, unknown> | undefined;
              const finishReason = resolveFinishReason(resp);

              const final = {
                id,
                object: "chat.completion.chunk",
                created,
                model,
                choices: [{ index: 0, delta: {}, finish_reason: finishReason }],
                ...(usage && {
                  usage: {
                    prompt_tokens: usage.input_tokens ?? 0,
                    completion_tokens: usage.output_tokens ?? 0,
                    total_tokens: usage.total_tokens ?? 0,
                  },
                }),
              };
              controller.enqueue(encoder.encode(`data: ${JSON.stringify(final)}\n\n`));
              controller.enqueue(encoder.encode("data: [DONE]\n\n"));
            }
          }
        }
      } finally {
        reader.releaseLock();
        controller.close();
      }
    },
  });
}

// ─── Server ──────────────────────────────────────────────────────────────────

Bun.serve({
  port: PORT,
  idleTimeout: 0,

  async fetch(req) {
    if (req.method === "GET") {
      const config = readConfig();
      return Response.json({
        ok: true,
        service: "codex-cursor-proxy",
        subdomain: config.subdomain ?? null,
        tunnelUrl: config.tunnelUrl ?? null,
      });
    }

    if (req.method === "OPTIONS") {
      return new Response(null, {
        headers: {
          "Access-Control-Allow-Origin": "*",
          "Access-Control-Allow-Methods": "POST, OPTIONS",
          "Access-Control-Allow-Headers": "Content-Type, Authorization",
        },
      });
    }

    if (req.method !== "POST") {
      return Response.json({ error: "Method not allowed" }, { status: 405 });
    }

    let parsed: Record<string, unknown>;
    try {
      parsed = (await req.json()) as Record<string, unknown>;
    } catch {
      return Response.json({ error: "Invalid JSON" }, { status: 400 });
    }

    const body = sanitizeBody(parsed);
    const model = (body.model as string) ?? "gpt-5.4";
    const inputCount = Array.isArray(body.input) ? body.input.length : 0;
    const toolCount = Array.isArray(body.tools) ? body.tools.length : 0;
    console.log(`-> ${model} | ${inputCount} messages | ${toolCount} tools`);

    const token = getAccessToken();
    if (!token) {
      return Response.json(
        { error: "No access token. Run `codex` to authenticate." },
        { status: 401 },
      );
    }

    const upstream = await fetch(API_URL, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${token}`,
      },
      body: JSON.stringify(body),
    });

    if (!upstream.ok) {
      const text = await upstream.text();
      console.log(`<- ${upstream.status} ERROR`);
      return new Response(text, {
        status: upstream.status,
        headers: { "Content-Type": "application/json" },
      });
    }

    console.log(`<- ${upstream.status} streaming`);

    if (!upstream.body) {
      return Response.json({ error: "Empty upstream response" }, { status: 502 });
    }

    return new Response(responsesToCompletionsStream(upstream.body, model), {
      headers: {
        "Content-Type": "text/event-stream; charset=utf-8",
        "Cache-Control": "no-cache",
        Connection: "keep-alive",
      },
    });
  },
});

// ─── Startup ─────────────────────────────────────────────────────────────────

const subdomain = getSubdomain();
console.log(`[proxy] Reusing stable tunnel subdomain: ${subdomain}`);

localtunnel({ port: PORT, subdomain })
  .then((tunnel) => {
    const expectedHost = `${subdomain}.loca.lt`;
    if (!tunnel.url.includes(expectedHost)) {
      console.warn(
        `[proxy] Reserved subdomain unavailable (${expectedHost}); using ${tunnel.url} instead.`,
      );
    }

    writeConfig({ subdomain, tunnelUrl: tunnel.url });
    console.log(`\nOpenAI Base URL for Cursor: ${tunnel.url}`);
    console.log("API Key: Anything you like!");
    console.log(`Stable subdomain persisted in ${CONFIG_PATH}\n`);
  })
  .catch((err) => {
    console.error("Tunnel failed:", err.message);
    console.error(
      "If the subdomain is unavailable, delete ~/.codex/cursor-proxy/config.json only if you accept a new loca.lt URL.",
    );
    process.exit(1);
  });
