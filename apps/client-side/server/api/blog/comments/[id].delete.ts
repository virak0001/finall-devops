import { fetchBackend } from '../../../utils/backend';

export default defineEventHandler((event): Promise<{ deleted: boolean }> => {
  const id = event.context.params!.id;
  return fetchBackend<{ deleted: boolean }>(event, `/api/blog/comments/${id}`, {
    method: 'DELETE',
  });
});
