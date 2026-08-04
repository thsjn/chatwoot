/* global axios */
import ApiClient from '../ApiClient';

class CrmLostReasons extends ApiClient {
  constructor() {
    super('crm/lost_reasons', { accountScoped: true });
  }

  // Same contract as the sources index: retired reasons are hidden from the pickers and only
  // the administration screen asks for them through `include_inactive=true`.
  get(params = {}) {
    return axios.get(this.url, { params });
  }

  create(data) {
    return axios.post(this.url, { lost_reason: data });
  }

  update(id, data) {
    return axios.patch(`${this.url}/${id}`, { lost_reason: data });
  }
}

export default new CrmLostReasons();
