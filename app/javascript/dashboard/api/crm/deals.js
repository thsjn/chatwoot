/* global axios */
import ApiClient from '../ApiClient';

class CrmDeals extends ApiClient {
  constructor() {
    super('crm/deals', { accountScoped: true });
  }

  get(params = {}) {
    return axios.get(this.url, { params });
  }

  create(data) {
    return axios.post(this.url, { deal: data });
  }

  // `lock_version` travels outside the `deal` wrapper (same shape as `move`) and is optional: it
  // is what turns two agents editing the same card from a silent overwrite into a 409.
  update(id, data, lockVersion = null) {
    return axios.patch(`${this.url}/${id}`, {
      deal: data,
      ...(lockVersion === null || lockVersion === undefined
        ? {}
        : { lock_version: lockVersion }),
    });
  }

  // `destroy` archives the deal, so restoring it is a dedicated endpoint instead of an update:
  // `archived_at` is not part of the permitted deal params.
  unarchive(id) {
    return axios.patch(`${this.url}/${id}/unarchive`);
  }

  // `move` reads its params from the request root (not wrapped in `deal`) and `lock_version` is
  // mandatory: it is what makes a concurrent drag fail with 409 instead of overwriting the
  // other agent's move.
  move(dealId, { stageId, position, lockVersion, lostReasonId } = {}) {
    return axios.patch(`${this.url}/${dealId}/move`, {
      stage_id: stageId,
      position,
      lock_version: lockVersion,
      lost_reason_id: lostReasonId,
    });
  }
}

export default new CrmDeals();
