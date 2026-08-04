// Formatting shared by the report blocks. The backend answers money in cents
// and durations in seconds, so every block would otherwise repeat the same two
// conversions.

const DURATION_UNITS = [
  { key: 'DAYS', seconds: 86400 },
  { key: 'HOURS', seconds: 3600 },
  { key: 'MINUTES', seconds: 60 },
  { key: 'SECONDS', seconds: 1 },
];

/**
 * Picks the largest unit that fits, so `avg_duration_seconds` reads as "2,4 d"
 * instead of "207360 s". Returns the pieces instead of a string because the
 * unit label is translated.
 *
 * @param {number|null} seconds Value as sent by the backend.
 * @returns {{ key: string, value: number }|null} `null` when there is no
 *   measurement at all (no closed deal, no completed stay in the stage).
 */
export const durationParts = seconds => {
  if (seconds === null || seconds === undefined) return null;

  const unit =
    DURATION_UNITS.find(candidate => seconds >= candidate.seconds) ||
    DURATION_UNITS[DURATION_UNITS.length - 1];

  return {
    key: unit.key,
    value: Math.round((seconds / unit.seconds) * 10) / 10,
  };
};

/**
 * @param {string} locale Resolved dashboard locale.
 * @param {string|null} currency ISO code, or `null` when the account mixes
 *   currencies and stamping a symbol on the sum would be a lie.
 */
export const buildCurrencyFormatter = (locale, currency) =>
  new Intl.NumberFormat(locale, {
    ...(currency ? { style: 'currency', currency } : {}),
    minimumFractionDigits: 0,
    maximumFractionDigits: 0,
  });

export const formatCents = (formatter, cents) =>
  formatter.format((cents || 0) / 100);
