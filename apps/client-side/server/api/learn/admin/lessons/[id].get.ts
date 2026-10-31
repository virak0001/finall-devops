import { fetchBackend } from "../../../../utils/backend";
import type { AdminLessonDetail } from "../../../../../app/types/api";

export default defineEventHandler(async (event): Promise<AdminLessonDetail> => {
  const id = event.context.params!.id;
  return fetchBackend<AdminLessonDetail>(
    event,
    `/api/learn/admin/lessons/${id}`,
  );
});
