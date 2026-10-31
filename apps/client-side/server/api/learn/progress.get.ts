import type { UserProgress } from "../../../app/types/api";
import { fetchBackend } from "../../utils/backend";

export default defineEventHandler(
  (event): Promise<UserProgress[]> =>
    fetchBackend<UserProgress[]>(event, "/api/learn/progress"),
);
