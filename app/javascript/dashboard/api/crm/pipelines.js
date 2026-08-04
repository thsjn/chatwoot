/* global axios */
import ApiClient from '../ApiClient';

class CrmPipelines extends ApiClient {
  constructor() {
    super('crm/pipelines', { accountScoped: true });
  }

  // The index only returns the active pipelines unless it is asked otherwise, so the board never
  // offers an archived funnel and the administration passes `include_archived=true` to restore it.
  get(params = {}) {
    return axios.get(this.url, { params });
  }

  create(data) {
    return axios.post(this.url, { pipeline: data });
  }

  update(id, data) {
    return axios.patch(`${this.url}/${id}`, { pipeline: data });
  }

  // Retiring a funnel that still holds deals, which `delete` refuses to do. The deals are kept.
  archive(id) {
    return axios.post(`${this.url}/${id}/archive`);
  }

  unarchive(id) {
    return axios.post(`${this.url}/${id}/unarchive`);
  }
}

export default new CrmPipelines();
