import { mount } from '@vue/test-utils';

import ReportBlock from '../ReportBlock.vue';

const mountBlock = (props = {}) =>
  mount(ReportBlock, {
    props: {
      title: 'Conversion funnel',
      emptyLabel: 'No deals went through this pipeline',
      ...props,
    },
    slots: { default: '<p>the chart</p>' },
  });

describe('ReportBlock.vue', () => {
  it('renders the title and the description above the content', () => {
    const wrapper = mountBlock({ description: 'Deals per stage' });

    expect(wrapper.text()).toContain('Conversion funnel');
    expect(wrapper.text()).toContain('Deals per stage');
    expect(wrapper.text()).toContain('the chart');
  });

  it('holds the content back while the metric is still loading', () => {
    const wrapper = mountBlock({ isLoading: true });

    expect(wrapper.findComponent({ name: 'Spinner' }).exists()).toBe(true);
    expect(wrapper.text()).not.toContain('the chart');
    expect(wrapper.text()).not.toContain('No deals went through this pipeline');
  });

  it('explains the emptiness instead of rendering an empty chart', () => {
    const wrapper = mountBlock({ isEmpty: true });

    expect(wrapper.text()).toContain('No deals went through this pipeline');
    expect(wrapper.text()).not.toContain('the chart');
  });

  // Loading wins over emptiness: a block that has not answered yet is not empty,
  // it is unknown, and flashing the empty copy first reads as "there is nothing".
  it('says nothing about emptiness while it is still loading', () => {
    const wrapper = mountBlock({ isLoading: true, isEmpty: true });

    expect(wrapper.text()).not.toContain('No deals went through this pipeline');
  });

  // The hint qualifies the block itself (a period that cannot forecast, for
  // example), so it has to be readable even when there is nothing to show.
  it('keeps the hint visible next to the empty state', () => {
    const wrapper = mountBlock({
      isEmpty: true,
      hint: 'The selected period has already ended',
    });

    expect(wrapper.text()).toContain('The selected period has already ended');
  });

  it('says nothing when no hint was given', () => {
    const wrapper = mountBlock();

    expect(wrapper.text()).not.toContain('The selected period has already');
  });

  it('renders the actions handed to it', () => {
    const wrapper = mount(ReportBlock, {
      props: { title: 'Forecast', emptyLabel: 'Nothing to forecast' },
      slots: { actions: '<button>Export</button>' },
    });

    expect(wrapper.find('button').text()).toBe('Export');
  });
});
