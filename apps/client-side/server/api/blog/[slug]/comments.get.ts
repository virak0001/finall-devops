import type { BlogComment } from '../../../../app/types/api';
import { fetchBackendPublic } from '../../../utils/backend';

export default defineEventHandler((event): Promise<BlogComment[]> => {
  const slug = event.context.params!.slug;
  return fetchBackendPublic<BlogComment[]>(event, `/api/blog/${slug}/comments`);
});
