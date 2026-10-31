import { readBody } from 'h3';
import type { BlogPost, CreateBlogPostPayload } from '../../app/types/api';
import { fetchBackend } from '../utils/backend';

export default defineEventHandler(async (event): Promise<BlogPost> => {
  const body = await readBody<CreateBlogPostPayload>(event);
  return fetchBackend<BlogPost>(event, '/api/blog', {
    method: 'POST',
    body,
  });
});
