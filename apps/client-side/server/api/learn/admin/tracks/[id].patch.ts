import { readBody } from "h3";
import { fetchBackend } from "../../../../utils/backend";
import type { UpdateTrackPayload, Track } from "../../../../../app/types/api";

export default defineEventHandler(async (event): Promise<Track> => {
  const id = event.context.params!.id;
  const body = await readBody<UpdateTrackPayload>(event);
  return fetchBackend<Track>(event, `/api/learn/admin/tracks/${id}`, {
    method: "PATCH",
    body,
  });
});
