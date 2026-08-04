/* global axios */
import ApiClient from '../ApiClient';

// Activities are nested under a deal (`crm/deals/:deal_id/activities`).
class CrmActivities extends ApiClient {
  constructor() {
    super('crm/deals', { accountScoped: true });
  }

  activitiesUrl(dealId) {
    return `${this.url}/${dealId}/activities`;
  }

  getActivities(dealId) {
    return axios.get(this.activitiesUrl(dealId));
  }

  showActivity(dealId, activityId) {
    return axios.get(`${this.activitiesUrl(dealId)}/${activityId}`);
  }

  createActivity(dealId, data) {
    return axios.post(this.activitiesUrl(dealId), { activity: data });
  }

  updateActivity(dealId, activityId, data) {
    return axios.patch(`${this.activitiesUrl(dealId)}/${activityId}`, {
      activity: data,
    });
  }

  deleteActivity(dealId, activityId) {
    return axios.delete(`${this.activitiesUrl(dealId)}/${activityId}`);
  }
}

export default new CrmActivities();
