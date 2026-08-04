import { computed, ref, unref } from 'vue';
import CrmActivitiesAPI from 'dashboard/api/crm/activities';

/**
 * Timeline of a deal, page by page. `Api::V1::Accounts::Crm::ActivitiesController` answers 25
 * activities at a time and reports the total in `meta.count`, so a deal with a long history keeps
 * its older entries reachable through `loadMore` instead of stopping at the first page.
 *
 * @param {import('vue').Ref<number|string>|number|string} dealId Deal the timeline belongs to.
 */
export function useDealActivities(dealId) {
  const activities = ref([]);
  const totalCount = ref(0);
  const currentPage = ref(0);
  const isFetching = ref(false);

  // Only the pages already loaded are on screen, so "there is more history" is the server total
  // measured against them — the same rule the board columns use for their cards.
  const hasMore = computed(() => activities.value.length < totalCount.value);

  const fetchPage = async page => {
    const id = unref(dealId);
    if (!id) return;

    isFetching.value = true;
    try {
      const { data } = await CrmActivitiesAPI.getActivities(id, { page });
      // The endpoint is chronological, so a later page carries the entries that follow the ones
      // on screen and is appended; page 1 is a fresh load and replaces them.
      activities.value =
        page === 1 ? data.payload : [...activities.value, ...data.payload];
      totalCount.value = Number(data.meta.count);
      currentPage.value = Number(data.meta.current_page);
    } finally {
      isFetching.value = false;
    }
  };

  const fetchActivities = () => fetchPage(1);

  const loadMore = () => {
    if (!hasMore.value || isFetching.value) return Promise.resolve();

    return fetchPage(currentPage.value + 1);
  };

  // A note written from the drawer joins both the page on screen and the server total, otherwise
  // the button to load more would come back for an entry that is already listed.
  const addActivity = activity => {
    activities.value = [...activities.value, activity];
    totalCount.value += 1;
  };

  const replaceActivity = activity => {
    activities.value = activities.value.map(item =>
      item.id === activity.id ? activity : item
    );
  };

  return {
    activities,
    isFetching,
    hasMore,
    fetchActivities,
    loadMore,
    addActivity,
    replaceActivity,
  };
}
