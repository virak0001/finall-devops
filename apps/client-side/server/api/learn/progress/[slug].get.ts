import type { TrackProgress } from "../../../../app/types/api";
import { fetchBackend } from "../../../utils/backend";

export default defineEventHandler((event: any): Promise<TrackProgress> => {
  const slug = getRouterParam(event, "slug");
  return fetchBackend<TrackProgress>(event, `/api/learn/progress/${slug}`);
});
