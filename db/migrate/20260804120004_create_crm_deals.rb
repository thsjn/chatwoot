class CreateCrmDeals < ActiveRecord::Migration[7.1]
  def change
    create_crm_deals
    add_crm_deal_indexes
  end

  private

  def create_crm_deals # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    create_table :crm_deals do |t|
      t.references :account, null: false, index: true, foreign_key: { on_delete: :cascade }
      t.references :pipeline, null: false, index: true, foreign_key: { to_table: :crm_pipelines }
      t.references :stage, null: false, index: true, foreign_key: { to_table: :crm_stages }
      t.references :contact, null: false, index: true, foreign_key: { on_delete: :cascade }
      t.string :title, null: false
      t.bigint :value_cents, null: false, default: 0
      t.string :currency, null: false, default: 'BRL'
      t.integer :status, null: false, default: 0
      t.references :owner, null: true, index: true, foreign_key: { to_table: :users, on_delete: :nullify }
      t.references :team, null: true, index: true, foreign_key: { on_delete: :nullify }
      t.references :source, null: true, index: true, foreign_key: { to_table: :crm_sources, on_delete: :nullify }
      t.references :source_inbox, null: true, index: true, foreign_key: { to_table: :inboxes, on_delete: :nullify }
      t.jsonb :utm, null: false, default: {}
      t.jsonb :custom_attributes, null: false, default: {}
      t.date :expected_close_on
      t.datetime :closed_at
      t.references :lost_reason, null: true, index: true, foreign_key: { to_table: :crm_lost_reasons, on_delete: :nullify }
      # Fractional indexing: moving a card writes the average of the two neighbouring positions.
      t.decimal :position, null: false, default: 0
      t.datetime :stage_entered_at
      t.datetime :last_activity_at
      t.integer :lock_version, null: false, default: 0
      t.datetime :archived_at

      t.timestamps
    end
  end

  def add_crm_deal_indexes
    add_index :crm_deals, [:account_id, :pipeline_id, :stage_id], name: 'index_crm_deals_on_account_pipeline_stage'
    add_index :crm_deals, [:stage_id, :position], name: 'index_crm_deals_on_stage_id_and_position'
    add_index :crm_deals, [:account_id, :status], name: 'index_crm_deals_on_account_id_and_status'
    add_index :crm_deals, [:account_id, :archived_at], name: 'index_crm_deals_on_account_id_and_archived_at'
  end
end
