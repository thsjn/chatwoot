class CreateCrmStages < ActiveRecord::Migration[7.1]
  def change
    create_table :crm_stages do |t|
      t.references :account, null: false, index: true, foreign_key: { on_delete: :cascade }
      t.references :pipeline, null: false, index: true, foreign_key: { to_table: :crm_pipelines, on_delete: :cascade }
      t.string :name, null: false
      t.integer :position, null: false, default: 0
      t.string :color
      t.integer :category, null: false, default: 0
      t.integer :probability, null: false, default: 0
      t.integer :rotting_days
      t.integer :wip_limit
      t.boolean :is_entry, null: false, default: false

      t.timestamps

      t.index [:pipeline_id, :position]
      t.index [:account_id, :category]
    end
  end
end
