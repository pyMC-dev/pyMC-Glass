import type { RepeaterResponse } from "../types";

const DEFAULT_REPEATER_UI_PORT = 8000;

interface RepeaterWithSettings extends RepeaterResponse {
  settings?: Record<string, unknown> | null;
}

function asRecord(value: unknown): Record<string, unknown> | null {
  return typeof value === "object" && value !== null && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : null;
}

function normalizePort(value: unknown): string {
  if (typeof value === "number" && Number.isInteger(value) && value > 0 && value <= 65535) {
    return String(value);
  }
  if (typeof value === "string" && /^\d+$/.test(value.trim())) {
    const parsed = Number.parseInt(value.trim(), 10);
    if (parsed > 0 && parsed <= 65535) {
      return String(parsed);
    }
  }
  return String(DEFAULT_REPEATER_UI_PORT);
}

function repeaterUiPort(settings?: Record<string, unknown> | null): string {
  const httpSettings = asRecord(settings?.http);
  return normalizePort(httpSettings?.port);
}

function stripProtocol(value: string): string {
  try {
    return new URL(value).host;
  } catch {
    return value.replace(/^https?:\/\//i, "").replace(/\/.*$/, "");
  }
}

function isDockerBridgeGateway(host: string): boolean {
  return /^172\.(1[6-9]|2\d|3[0-1])\.0\.1$/.test(host.trim());
}

function isBrowserLocalHost(host: string): boolean {
  const normalized = host.trim().toLowerCase();
  return normalized === "localhost" || normalized === "127.0.0.1" || normalized === "::1";
}

function hostForRepeaterUi(informIp: string | null | undefined): string {
  const fallbackHost = window.location.hostname;
  if (!informIp) {
    return fallbackHost;
  }
  const candidate = stripProtocol(informIp.trim());
  const candidateHost = candidate.replace(/^\[(.*)](?::\d+)?$/, "$1").replace(/:\d+$/, "");
  if (!candidateHost || isBrowserLocalHost(candidateHost) || isDockerBridgeGateway(candidateHost)) {
    return fallbackHost;
  }
  return candidate;
}

function normalizeOpenUrlOverride(value: string | null | undefined): string | null {
  const text = value?.trim();
  if (!text) {
    return null;
  }
  return /^https?:\/\//i.test(text) ? text : `http://${text}`;
}

export function repeaterUiUrl(repeater: RepeaterWithSettings): string {
  const override = normalizeOpenUrlOverride(repeater.open_url);
  if (override) {
    return override;
  }
  const url = new URL(`http://${hostForRepeaterUi(repeater.inform_ip)}`);
  url.port = repeaterUiPort(repeater.settings);
  return url.toString();
}
