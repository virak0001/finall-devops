import type { Playbook } from '../../app/types/api';
import { fetchBackend } from '../utils/backend';

export default defineEventHandler((event): Promise<Playbook[]> =>
  fetchBackend<Playbook[]>(event, '/api/playbooks'),
);
