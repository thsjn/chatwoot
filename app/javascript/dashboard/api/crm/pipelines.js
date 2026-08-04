/* global axios */
import ApiClient from '../ApiClient';

class CrmPipelines extends ApiClient {
  constructor() {
    super('crm/pipelines', { accountScoped: true });
  }

  create(data) {
    return axios.post(this.url, { pipeline: data });
  }

  update(id, data) {
    return axios.patch(`${this.url}/${id}`, { pipeline: data });
  }
}

export default new CrmPipelines();
