import { readBody } from "h3";
import { fetchBackend } from "../../../utils/backend";
import type { CreateTrackPayload, Track } from "../../../../app/types/api";

export default defineEventHandler(async (event): Promise<Track> => {
  const body = await readBody<CreateTrackPayload>(event);
  return fetchBackend<Track>(event, "/api/learn/admin/tracks", {
    method: "POST",
    body,
  });
});
