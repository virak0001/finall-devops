import { fetchBackend } from "../../../../utils/backend";

export default defineEventHandler((event) => {
  const lessonId = getRouterParam(event, "id");
  return fetchBackend(event, `/api/learn/lessons/${lessonId}/complete`, {
    method: "POST",
  });
});
