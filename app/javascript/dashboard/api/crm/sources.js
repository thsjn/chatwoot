/* global axios */
import ApiClient from '../ApiClient';

class CrmSources extends ApiClient {
  constructor() {
    super('crm/sources', { accountScoped: true });
  }

  // The index only returns the active sources unless it is asked otherwise, so the
  // administration screen passes `include_inactive=true` to see the retired ones as well.
  get(params = {}) {
    return axios.get(this.url, { params });
  }

  create(data) {
    return axios.post(this.url, { source: data });
  }

  update(id, data) {
    return axios.patch(`${this.url}/${id}`, { source: data });
  }
}

export default new CrmSources();
