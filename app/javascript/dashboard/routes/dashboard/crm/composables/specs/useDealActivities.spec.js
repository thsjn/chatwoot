import { ref } from 'vue';
import CrmActivitiesAPI from 'dashboard/api/crm/activities';
import { useDealActivities } from '../useDealActivities';

vi.mock('dashboard/api/crm/activities', () => ({
  default: { getActivities: vi.fn() },
}));

const activity = id => ({ id, kind: 'note', content: `Note ${id}` });

const page = (ids, { count, currentPage }) => ({
  data: {
    payload: ids.map(activity),
    meta: { count, current_page: currentPage },
  },
});

describe('useDealActivities', () => {
  beforeEach(() => vi.clearAllMocks());

  it('loads the first page and reports there is more history behind it', async () => {
    CrmActivitiesAPI.getActivities.mockResolvedValue(
      page([1, 2], { count: 3, currentPage: 1 })
    );
    const timeline = useDealActivities(ref(7));

    await timeline.fetchActivities();

    expect(CrmActivitiesAPI.getActivities).toHaveBeenCalledWith(7, { page: 1 });
    expect(timeline.activities.value.map(item => item.id)).toEqual([1, 2]);
    expect(timeline.hasMore.value).toBe(true);
    expect(timeline.isFetching.value).toBe(false);
  });

  it('appends the next page and stops once the whole timeline is loaded', async () => {
    CrmActivitiesAPI.getActivities.mockResolvedValueOnce(
      page([1, 2], { count: 3, currentPage: 1 })
    );
    const timeline = useDealActivities(ref(7));
    await timeline.fetchActivities();

    CrmActivitiesAPI.getActivities.mockResolvedValueOnce(
      page([3], { count: 3, currentPage: 2 })
    );
    await timeline.loadMore();

    expect(CrmActivitiesAPI.getActivities).toHaveBeenLastCalledWith(7, {
      page: 2,
    });
    expect(timeline.activities.value.map(item => item.id)).toEqual([1, 2, 3]);
    expect(timeline.hasMore.value).toBe(false);
  });

  it('does not ask for another page when everything is already on screen', async () => {
    CrmActivitiesAPI.getActivities.mockResolvedValue(
      page([1], { count: 1, currentPage: 1 })
    );
    const timeline = useDealActivities(ref(7));
    await timeline.fetchActivities();

    await timeline.loadMore();

    expect(CrmActivitiesAPI.getActivities).toHaveBeenCalledTimes(1);
  });

  it('replaces the list when the first page is fetched again', async () => {
    CrmActivitiesAPI.getActivities.mockResolvedValueOnce(
      page([1, 2], { count: 3, currentPage: 1 })
    );
    const timeline = useDealActivities(ref(7));
    await timeline.fetchActivities();

    CrmActivitiesAPI.getActivities.mockResolvedValueOnce(
      page([1], { count: 1, currentPage: 1 })
    );
    await timeline.fetchActivities();

    expect(timeline.activities.value.map(item => item.id)).toEqual([1]);
    expect(timeline.hasMore.value).toBe(false);
  });

  // A note written from the drawer is already on screen: counting it keeps the "load more"
  // button from coming back for an entry that is listed right above it.
  it('counts a locally created activity towards the total', async () => {
    CrmActivitiesAPI.getActivities.mockResolvedValue(
      page([1], { count: 1, currentPage: 1 })
    );
    const timeline = useDealActivities(ref(7));
    await timeline.fetchActivities();

    timeline.addActivity(activity(2));

    expect(timeline.activities.value.map(item => item.id)).toEqual([1, 2]);
    expect(timeline.hasMore.value).toBe(false);
  });

  it('swaps an activity in place when it comes back updated', async () => {
    CrmActivitiesAPI.getActivities.mockResolvedValue(
      page([1, 2], { count: 2, currentPage: 1 })
    );
    const timeline = useDealActivities(ref(7));
    await timeline.fetchActivities();

    timeline.replaceActivity({ ...activity(2), completed_at: 1234 });

    expect(timeline.activities.value[1].completed_at).toBe(1234);
  });

  it('skips the request while there is no deal to load', async () => {
    const timeline = useDealActivities(ref(null));

    await timeline.fetchActivities();

    expect(CrmActivitiesAPI.getActivities).not.toHaveBeenCalled();
  });
});
