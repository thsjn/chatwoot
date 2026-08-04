import {
  CHART_FONT_FAMILY,
} from 'dashboard/routes/dashboard/settings/reports/constants';

// Hex twins of the `n-*-9` tokens `ChartLegend.vue` paints its dots with, so
// the legend and the bars are the same colour. Chart.js takes colours, not
// classes, which is why the value has to be repeated here.
export const CHART_COLORS = {
  primary: 'rgb(31, 147, 255)',
  muted: '#8B8D98',
  positive: '#12A594',
  negative: '#E54666',
};

/**
 * Options for `shared/components/charts/BarChart.vue`. The value axis and the
 * tooltip go through the same formatter, which is what keeps a money chart from
 * printing raw cents on the ticks.
 *
 * @param {(value: number) => string} [formatValue]
 */
export const buildBarChartOptions = ({ formatValue } = {}) => {
  const tick = value => (formatValue ? formatValue(value) : value);

  return {
    plugins: {
      // The legend is rendered by `ChartLegend.vue`: see the note there.
      legend: { display: false },
      tooltip: {
        callbacks: {
          label: context => `${context.dataset.label}: ${tick(context.raw)}`,
        },
      },
    },
    scales: {
      x: {
        ticks: { font: { family: CHART_FONT_FAMILY } },
        grid: { drawOnChartArea: false },
      },
      y: {
        type: 'linear',
        position: 'left',
        ticks: {
          font: { family: CHART_FONT_FAMILY },
          beginAtZero: true,
          callback: tick,
        },
        grid: { drawOnChartArea: false },
      },
    },
  };
};
