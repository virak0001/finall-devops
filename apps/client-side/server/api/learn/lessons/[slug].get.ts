import type { LessonDetail } from "../../../../app/types/api";
import { fetchBackend } from "../../../utils/backend";

export default defineEventHandler((event): Promise<LessonDetail> => {
  const slug = getRouterParam(event, "slug");
  return fetchBackend<LessonDetail>(event, `/api/learn/lessons/${slug}`);
});
