import { getCookie, setCookie } from "h3";
import { fetchAuth } from "../../utils/backend";

interface TokenPair {
  accessToken: string;
  refreshToken: string;
}

export default defineEventHandler(async (event) => {
  const refreshToken = getCookie(event, "refresh_token");
  if (!refreshToken) {
    throw createError({ statusCode: 401, statusMessage: "No refresh token" });
  }

  const data = await fetchAuth<TokenPair>(event, "/api/auth/refresh", {
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

  return { ok: true };
});
