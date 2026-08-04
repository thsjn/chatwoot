class CreateCrmStageTransitions < ActiveRecord::Migration[7.1]
  def change
    create_table :crm_stage_transitions do |t|
      t.references :deal, null: false, index: true, foreign_key: { to_table: :crm_deals, on_delete: :cascade }
      t.references :from_stage, null: true, index: true, foreign_key: { to_table: :crm_stages, on_delete: :nullify }
      t.references :to_stage, null: false, index: true, foreign_key: { to_table: :crm_stages }
      t.references :user, null: true, index: true, foreign_key: { on_delete: :nullify }
      t.integer :duration_seconds
      t.boolean :automated, null: false, default: false

      t.datetime :created_at, null: false

      t.index [:deal_id, :created_at], name: 'index_crm_stage_transitions_on_deal_id_and_created_at'
    end
  end
end
