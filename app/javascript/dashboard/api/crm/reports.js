/* global axios */
import ApiClient from '../ApiClient';

/**
 * The seven funnel metrics live under a singular `resource :reports`, so every
 * endpoint is a GET on the same base URL and they all share the exact same
 * scope params: `pipeline_id` plus the `since`/`until` window, which the
 * backend `DateRangeHelper` parses as UNIX timestamps in SECONDS (`%s`) and
 * ignores entirely unless BOTH sides are present.
 */
class CrmReports extends ApiClient {
  constructor() {
    super('crm/reports', { accountScoped: true });
  }

  funnel(params = {}) {
    return axios.get(`${this.url}/funnel`, { params });
  }

  stageDurations(params = {}) {
    return axios.get(`${this.url}/stage_durations`, { params });
  }

  salesCycle(params = {}) {
    return axios.get(`${this.url}/sales_cycle`, { params });
  }

  forecast(params = {}) {
    return axios.get(`${this.url}/forecast`, { params });
  }

  sources(params = {}) {
    return axios.get(`${this.url}/sources`, { params });
  }

  lossReasons(params = {}) {
    return axios.get(`${this.url}/loss_reasons`, { params });
  }

  // Answers `text/csv`, not JSON: the response body is already the file, so it
  // is handed to the caller as text for `downloadCsvFile` to wrap in a Blob.
  dealsExport(params = {}) {
    return axios.get(`${this.url}/deals_export`, {
      params,
      responseType: 'text',
    });
  }
}

export default new CrmReports();
