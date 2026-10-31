import { readBody } from "h3";
import type { Resource } from "../../../app/types/api";
import { fetchBackend } from "../../utils/backend";

export default defineEventHandler(async (event): Promise<Resource> => {
  const id = event.context.params!.id;
  const body = await readBody(event);
  return fetchBackend<Resource>(event, `/api/resources/${id}`, {
    method: "PATCH",
    body,
  });
});
