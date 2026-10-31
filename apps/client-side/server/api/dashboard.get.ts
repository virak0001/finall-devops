import type { DashboardResponse } from '../../app/types/api';
import { fetchBackend } from '../utils/backend';

export default defineEventHandler((event): Promise<DashboardResponse> =>
  fetchBackend<DashboardResponse>(event, '/api/dashboard'),
);
