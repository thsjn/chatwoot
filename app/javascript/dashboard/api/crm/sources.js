/* global axios */
import ApiClient from '../ApiClient';

class CrmSources extends ApiClient {
  constructor() {
    super('crm/sources', { accountScoped: true });
  }

  create(data) {
    return axios.post(this.url, { source: data });
  }

  update(id, data) {
    return axios.patch(`${this.url}/${id}`, { source: data });
  }
}

export default new CrmSources();
