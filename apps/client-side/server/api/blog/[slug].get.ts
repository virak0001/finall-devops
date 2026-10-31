import type { BlogPost } from '../../../app/types/api';
import { fetchBackendPublic } from '../../utils/backend';

export default defineEventHandler((event): Promise<BlogPost> => {
  const slug = event.context.params?.slug ?? event.context.params?.id;
  return fetchBackendPublic<BlogPost>(event, `/api/blog/${slug}`);
});
