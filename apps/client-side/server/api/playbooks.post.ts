import { readBody } from 'h3';
import type { CreatePlaybookPayload, Playbook } from '../../app/types/api';
import { fetchBackend } from '../utils/backend';

export default defineEventHandler(async (event): Promise<Playbook> => {
  const body = await readBody<CreatePlaybookPayload>(event);

  return fetchBackend<Playbook>(event, '/api/playbooks', {
    method: 'POST',
    body,
  });
});
