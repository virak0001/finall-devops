import type { Track } from "../../../app/types/api";
import { fetchBackend } from "../../utils/backend";

export default defineEventHandler(
  (event): Promise<Track[]> =>
    fetchBackend<Track[]>(event, "/api/learn/tracks"),
);
