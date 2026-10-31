import { readBody } from 'h3';
import { fetchBackend } from '../../../../utils/backend';
import type { UpdateModulePayload, TrackModule } from '../../../../../app/types/api';

export default defineEventHandler(async (event): Promise<TrackModule> => {
  const id = event.context.params!.id;
  const body = await readBody<UpdateModulePayload>(event);
  return fetchBackend<TrackModule>(event, `/api/learn/admin/modules/${id}`, {
    method: 'PATCH',
    body,
  });
});
