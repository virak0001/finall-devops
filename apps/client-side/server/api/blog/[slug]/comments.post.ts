import { readBody } from 'h3';
import type { BlogComment, CreateBlogCommentPayload } from '../../../../app/types/api';
import { fetchBackend } from '../../../utils/backend';

export default defineEventHandler(async (event): Promise<BlogComment> => {
  const slug = event.context.params!.slug;
  const body = await readBody<CreateBlogCommentPayload>(event);
  return fetchBackend<BlogComment>(event, `/api/blog/${slug}/comments`, {
    method: 'POST',
    body,
  });
});
