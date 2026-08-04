require 'rails_helper'

RSpec.describe Crm::DealPolicy, type: :policy do
  subject { described_class }

  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:other_agent) { create(:user, account: account, role: :agent) }
  let(:administrator_context) { { user: administrator, account: account, account_user: administrator.account_users.find_by(account: account) } }
  let(:agent_context) { { user: agent, account: account, account_user: agent.account_users.find_by(account: account) } }

  let(:open_pipeline) { create(:crm_pipeline, account: account) }
  let(:restricted_pipeline) { create(:crm_pipeline, :restricted_by_owner, account: account) }
  let(:deal) { create(:crm_deal, account: account, pipeline: open_pipeline) }

  permissions :index?, :create? do
    it 'allows administrators' do
      expect(subject).to permit(administrator_context, deal)
    end

    it 'allows agents' do
      expect(subject).to permit(agent_context, deal)
    end
  end

  permissions :destroy? do
    it 'allows administrators' do
      expect(subject).to permit(administrator_context, deal)
    end

    it 'denies agents' do
      expect(subject).not_to permit(agent_context, deal)
    end
  end

  permissions :show?, :update? do
    context 'when the pipeline is not restricted by owner' do
      it 'allows an agent to access a deal owned by someone else' do
        deal.update!(owner: other_agent)

        expect(subject).to permit(agent_context, deal)
      end
    end

    context 'when the pipeline is restricted by owner' do
      let(:deal) { create(:crm_deal, account: account, pipeline: restricted_pipeline) }

      it 'denies an agent access to a deal owned by someone else' do
        deal.update!(owner: other_agent)

        expect(subject).not_to permit(agent_context, deal)
      end

      it 'allows an agent to access their own deal' do
        deal.update!(owner: agent)

        expect(subject).to permit(agent_context, deal)
      end

      it 'allows an agent to access a deal without an owner' do
        expect(deal.owner_id).to be_nil
        expect(subject).to permit(agent_context, deal)
      end

      it 'allows an administrator to access a deal owned by someone else' do
        deal.update!(owner: other_agent)

        expect(subject).to permit(administrator_context, deal)
      end
    end
  end

  describe Crm::DealPolicy::Scope do
    let!(:own_deal) { create(:crm_deal, account: account, pipeline: restricted_pipeline, owner: agent) }
    let!(:other_owner_deal) { create(:crm_deal, account: account, pipeline: restricted_pipeline, owner: other_agent) }
    let!(:ownerless_deal) { create(:crm_deal, account: account, pipeline: restricted_pipeline) }
    let!(:open_pipeline_deal) { create(:crm_deal, account: account, pipeline: open_pipeline, owner: other_agent) }

    # A deal on another account must never surface, whatever the owner rules say.
    before { create(:crm_deal, account: create(:account)) }

    it 'returns every deal of the account for an administrator' do
      resolved = described_class.new(administrator_context, Crm::Deal).resolve

      expect(resolved).to contain_exactly(own_deal, other_owner_deal, ownerless_deal, open_pipeline_deal)
    end

    it 'hides deals owned by other agents on restricted pipelines' do
      resolved = described_class.new(agent_context, Crm::Deal).resolve

      expect(resolved).to contain_exactly(own_deal, ownerless_deal, open_pipeline_deal)
      expect(resolved).not_to include(other_owner_deal)
    end

    it 'returns every deal of the account when no pipeline is restricted' do
      restricted_pipeline.update!(settings: restricted_pipeline.settings.merge('restrito_por_owner' => false))

      resolved = described_class.new(agent_context, Crm::Deal).resolve

      expect(resolved).to contain_exactly(own_deal, other_owner_deal, ownerless_deal, open_pipeline_deal)
    end
  end
end
