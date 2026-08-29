export const seedProfiles = [
  {
    countryCode: 'IN',
    numberPrefix: 'GST',
    resetPeriod: 'FINANCIAL_YEAR',
    taxBreakdownMode: 'SPLIT_COMPONENTS',
    roundingRule: 'ROUND_PER_LINE',
    retentionYears: 8,
    requiredFields: ['gstin', 'hsnCode'],
  },
  {
    countryCode: 'US',
    numberPrefix: 'INV',
    resetPeriod: 'CALENDAR_YEAR',
    taxBreakdownMode: 'SINGLE_LINE',
    roundingRule: 'ROUND_TOTAL',
    retentionYears: 7,
    requiredFields: [],
  },
  {
    countryCode: 'JP',
    numberPrefix: 'REC',
    resetPeriod: 'CALENDAR_YEAR',
    taxBreakdownMode: 'SINGLE_LINE',
    roundingRule: 'ROUND_TOTAL',
    retentionYears: 7,
    requiredFields: ['registrationNumber'],
  },
];
