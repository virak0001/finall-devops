import { readBody } from "h3";
import { fetchBackend } from "../../../utils/backend";
import type {
  CreateLessonPayload,
  AdminLessonDetail,
} from "../../../../app/types/api";

export default defineEventHandler(async (event): Promise<AdminLessonDetail> => {
  const body = await readBody<CreateLessonPayload>(event);
  return fetchBackend<AdminLessonDetail>(event, "/api/learn/admin/lessons", {
    method: "POST",
    body,
  });
});
