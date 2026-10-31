import type { Resource } from "../../../app/types/api";
import { fetchBackendPublic } from "../../utils/backend";

export default defineEventHandler((event): Promise<Resource> => {
  const id = event.context.params!.id;
  return fetchBackendPublic<Resource>(event, `/api/resources/${id}`);
});
