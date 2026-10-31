import { createError, getCookie, setCookie } from "h3";
import type { H3Event } from "h3";

type FetchErrorShape = {
  response?: {
    status?: number;
    _data?: {
      message?: string | string[];
      error?: string;
    };
  };
};

interface TokenPair {
  accessToken: string;
  refreshToken: string;
}

async function fetchService<T>(
  baseUrl: string,
  path: string,
  options?: Parameters<typeof $fetch<T>>[1],
): Promise<T> {
  if (!baseUrl) {
    throw createError({
      statusCode: 503,
      statusMessage: "Upstream service not configured.",
    });
  }
  try {
    return (await $fetch(`${baseUrl}${path}`, options)) as T;
  } catch (error) {
    const fetchError = error as FetchErrorShape;
    const message = fetchError.response?._data?.message;

    throw createError({
      statusCode: fetchError.response?.status ?? 502,
      statusMessage: Array.isArray(message)
        ? message.join(", ")
        : (message ??
          fetchError.response?._data?.error ??
          "Upstream request failed."),
    });
  }
}

function buildAuthHeaders(
  token: string,
  base?: Parameters<typeof $fetch>[1],
): Parameters<typeof $fetch>[1] {
  return {
    ...base,
    headers: {
      ...(base?.headers as Record<string, string> | undefined),
      Authorization: `Bearer ${token}`,
    },
  };
}

async function tryRefresh(event: H3Event): Promise<string | null> {
  const refreshToken = getCookie(event, "refresh_token");
  if (!refreshToken) return null;

  const runtimeConfig = useRuntimeConfig(event);
  const authUrl = (runtimeConfig.authUrl ?? "").replace(/\/$/, "");

  try {
    const data = await $fetch<TokenPair>(`${authUrl}/api/auth/refresh`, {
      method: "POST",
      headers: { Authorization: `Bearer ${refreshToken}` },
      body: { refreshToken },
    });

    setCookie(event, "access_token", data.accessToken, {
      maxAge: 60 * 15,
      sameSite: "lax",
      path: "/",
    });
    setCookie(event, "refresh_token", data.refreshToken, {
      maxAge: 60 * 60 * 24 * 7,
      sameSite: "lax",
      path: "/",
    });

    return data.accessToken;
  } catch {
    return null;
  }
}

export async function fetchBackend<T>(
  event: H3Event,
  path: string,
  options?: Parameters<typeof $fetch<T>>[1],
): Promise<T> {
  const runtimeConfig = useRuntimeConfig(event);
  // ?? "" so a missing runtimeConfig key reaches fetchService's guard and
  // returns 503 "Upstream service not configured", instead of throwing
  // "Cannot read properties of undefined (reading 'replace')" as a 500.
  const backendUrl = (runtimeConfig.backendUrl ?? "").replace(/\/$/, "");
  const token = getCookie(event, "access_token");

  console.log("Access token:", token);

  if (token) {
    try {
      return await fetchService<T>(
        backendUrl,
        path,
        buildAuthHeaders(token, options) as Parameters<typeof $fetch<T>>[1],
      );
    } catch (err) {
      const status = (err as { statusCode?: number }).statusCode;
      if (status !== 401) throw err;
    }
  }

  // Access token missing or expired — attempt silent refresh
  const newToken = await tryRefresh(event);
  if (!newToken) {
    throw createError({ statusCode: 401, statusMessage: "Unauthorized" });
  }

  return fetchService<T>(
    backendUrl,
    path,
    buildAuthHeaders(newToken, options) as Parameters<typeof $fetch<T>>[1],
  );
}

export async function fetchBackendPublic<T>(
  event: H3Event,
  path: string,
  options?: Parameters<typeof $fetch<T>>[1],
): Promise<T> {
  const runtimeConfig = useRuntimeConfig(event);
  // ?? "" so a missing runtimeConfig key reaches fetchService's guard and
  // returns 503 "Upstream service not configured", instead of throwing
  // "Cannot read properties of undefined (reading 'replace')" as a 500.
  const backendUrl = (runtimeConfig.backendUrl ?? "").replace(/\/$/, "");
  return fetchService<T>(backendUrl, path, options);
}

export async function fetchAuth<T>(
  event: H3Event,
  path: string,
  options?: Parameters<typeof $fetch<T>>[1],
): Promise<T> {
  const runtimeConfig = useRuntimeConfig(event);
  const authUrl = (runtimeConfig.authUrl ?? "").replace(/\/$/, "");
  return fetchService<T>(authUrl, path, options);
}
