import type { Resource } from "../../app/types/api";
import { fetchBackendPublic } from "../utils/backend";

export default defineEventHandler((event): Promise<Resource[]> => {
  const query = getQuery(event);
  const params = new URLSearchParams();
  if (query.track) params.set("track", String(query.track));
  if (query.type) params.set("type", String(query.type));
  if (query.search) params.set("search", String(query.search));
  const qs = params.toString();
  return fetchBackendPublic<Resource[]>(event, `/api/resources${qs ? `?${qs}` : ""}`);
});
