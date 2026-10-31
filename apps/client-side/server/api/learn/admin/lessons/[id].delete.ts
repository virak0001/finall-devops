import { fetchBackend } from '../../../../utils/backend';

export default defineEventHandler(async (event): Promise<{ deleted: boolean }> => {
  const id = event.context.params!.id;
  return fetchBackend<{ deleted: boolean }>(event, `/api/learn/admin/lessons/${id}`, {
    method: 'DELETE',
  });
});
