import { fetchBackend } from '../../../utils/backend';

export default defineEventHandler(async (event) => {
  const slug = event.context.params!.slug;
  return fetchBackend(event, `/api/blog/${slug}/complete`, { method: 'POST' });
});
