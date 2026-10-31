import { readBody } from "h3";
import type { Playbook } from "../../../app/types/api";
import { fetchBackend } from "../../utils/backend";

export default defineEventHandler(async (event): Promise<Playbook> => {
  const id = event.context.params!.id;
  const body = await readBody(event);
  return fetchBackend<Playbook>(event, `/api/playbooks/${id}`, {
    method: "PATCH",
    body,
  });
});
