/* global axios */
import ApiClient from '../ApiClient';

// Stages are nested under a pipeline (`crm/pipelines/:pipeline_id/stages`), so the pipeline id
// travels in every call instead of living in the resource path.
class CrmStages extends ApiClient {
  constructor() {
    super('crm/pipelines', { accountScoped: true });
  }

  stagesUrl(pipelineId) {
    return `${this.url}/${pipelineId}/stages`;
  }

  getStages(pipelineId) {
    return axios.get(this.stagesUrl(pipelineId));
  }

  showStage(pipelineId, stageId) {
    return axios.get(`${this.stagesUrl(pipelineId)}/${stageId}`);
  }

  createStage(pipelineId, data) {
    return axios.post(this.stagesUrl(pipelineId), { stage: data });
  }

  updateStage(pipelineId, stageId, data) {
    return axios.patch(`${this.stagesUrl(pipelineId)}/${stageId}`, {
      stage: data,
    });
  }

  deleteStage(pipelineId, stageId) {
    return axios.delete(`${this.stagesUrl(pipelineId)}/${stageId}`);
  }
}

export default new CrmStages();
