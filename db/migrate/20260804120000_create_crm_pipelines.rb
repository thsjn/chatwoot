class CreateCrmPipelines < ActiveRecord::Migration[7.1]
  def change
    create_table :crm_pipelines do |t|
      t.references :account, null: false, index: true, foreign_key: { on_delete: :cascade }
      t.string :name, null: false
      t.text :description
      t.integer :position, null: false, default: 0
      t.boolean :is_default, null: false, default: false
      # settings holds: inbox_ids (ingestion), janela_dedupe_dias, exige_proxima_atividade,
      # moeda_padrao, restrito_por_owner
      t.jsonb :settings, null: false, default: {}
      t.datetime :archived_at

      t.timestamps

      t.index [:account_id, :position]
      t.index [:account_id, :archived_at]
    end

    # Only one default pipeline per account. Mirrors the model level uniqueness validation.
    add_index :crm_pipelines, :account_id, unique: true, where: 'is_default = true', name: 'index_crm_pipelines_on_account_id_default'
  end
end
