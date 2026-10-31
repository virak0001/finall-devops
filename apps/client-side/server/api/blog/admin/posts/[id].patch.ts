import { readBody } from 'h3';
import type { UpdateBlogPostPayload, BlogPost } from '../../../../app/types/api';
import { fetchBackend } from '../../../../utils/backend';

export default defineEventHandler(async (event): Promise<BlogPost> => {
  const id = event.context.params!.id;
  const body = await readBody<UpdateBlogPostPayload>(event);
  return fetchBackend<BlogPost>(event, `/api/blog/admin/posts/${id}`, {
    method: 'PATCH',
    body,
  });
});
