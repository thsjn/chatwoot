import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

import { useLocale } from 'shared/composables/useLocale';
import { useCrmReportsStore } from 'dashboard/store/crm/reports';
import {
  buildCurrencyFormatter,
  durationParts,
  formatCents,
} from '../helpers/format';

/**
 * Number/money/duration formatting for the report blocks, bound to the store so
 * the currency decision is taken in ONE place: when the account runs pipelines
 * in different currencies the aggregates (raw sums of `value_cents`) are not
 * money in any single currency, so no symbol is printed at all.
 */
export const useCrmReportFormat = () => {
  const { t } = useI18n();
  const { resolvedLocale } = useLocale();
  const store = useCrmReportsStore();

  const currencyFormatter = computed(() =>
    buildCurrencyFormatter(
      resolvedLocale.value,
      store.hasMixedCurrencies ? null : store.getCurrency
    )
  );

  const numberFormatter = computed(
    () => new Intl.NumberFormat(resolvedLocale.value)
  );

  const decimalFormatter = computed(
    () =>
      new Intl.NumberFormat(resolvedLocale.value, { maximumFractionDigits: 1 })
  );

  const formatMoney = cents => formatCents(currencyFormatter.value, cents);

  const formatNumber = value => numberFormatter.value.format(value || 0);

  const formatPercent = value =>
    `${decimalFormatter.value.format(value || 0)}%`;

  const formatDuration = seconds => {
    const parts = durationParts(seconds);
    if (!parts) return t('CRM.REPORTS.DURATION.EMPTY');

    return t(`CRM.REPORTS.DURATION.${parts.key}`, {
      value: decimalFormatter.value.format(parts.value),
    });
  };

  return { formatMoney, formatNumber, formatPercent, formatDuration };
};
