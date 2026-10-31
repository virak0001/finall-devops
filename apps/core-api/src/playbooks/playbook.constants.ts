export const playbookCategories = [
  'delivery',
  'observability',
  'resilience',
  'security',
] as const;

export const playbookDifficulties = ['intermediate', 'advanced'] as const;

export const playbookStatuses = ['planned', 'practicing', 'validated'] as const;

export type PlaybookCategory = (typeof playbookCategories)[number];
export type PlaybookDifficulty = (typeof playbookDifficulties)[number];
export type PlaybookStatus = (typeof playbookStatuses)[number];
