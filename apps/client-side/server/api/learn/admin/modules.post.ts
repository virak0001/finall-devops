import { readBody } from 'h3';
import { fetchBackend } from '../../../utils/backend';
import type { CreateModulePayload, TrackModule } from '../../../../app/types/api';

export default defineEventHandler(async (event): Promise<TrackModule> => {
  const body = await readBody<CreateModulePayload>(event);
  return fetchBackend<TrackModule>(event, '/api/learn/admin/modules', {
    method: 'POST',
    body,
  });
});
