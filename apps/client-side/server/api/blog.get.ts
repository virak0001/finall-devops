import type { BlogPost } from '../../app/types/api';
import { fetchBackendPublic } from '../utils/backend';

export default defineEventHandler((event): Promise<BlogPost[]> =>
  fetchBackendPublic<BlogPost[]>(event, '/api/blog'),
);
