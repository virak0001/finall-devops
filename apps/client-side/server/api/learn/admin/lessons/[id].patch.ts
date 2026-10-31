import { readBody } from "h3";
import { fetchBackend } from "../../../../utils/backend";
import type {
  UpdateLessonPayload,
  AdminLessonDetail,
} from "../../../../../app/types/api";

export default defineEventHandler(async (event): Promise<AdminLessonDetail> => {
  const id = event.context.params!.id;
  const body = await readBody<UpdateLessonPayload>(event);
  return fetchBackend<AdminLessonDetail>(
    event,
    `/api/learn/admin/lessons/${id}`,
    {
      method: "PATCH",
      body,
    },
  );
});
