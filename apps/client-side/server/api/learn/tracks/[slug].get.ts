import type { TrackDetail } from "../../../../app/types/api";
import { fetchBackend } from "../../../utils/backend";

export default defineEventHandler((event): Promise<TrackDetail> => {
  const slug = getRouterParam(event, "slug");
  return fetchBackend<TrackDetail>(event, `/api/learn/tracks/${slug}`);
});
