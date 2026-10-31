import { readBody } from "h3";
import { fetchAuth } from "../../utils/backend";
import type { LoginResponse } from "../../../app/types/api";

export default defineEventHandler(async (event) => {
  const body = await readBody(event);
  return fetchAuth<LoginResponse>(event, "/api/auth/register", {
    method: "POST",
    body,
  });
});
