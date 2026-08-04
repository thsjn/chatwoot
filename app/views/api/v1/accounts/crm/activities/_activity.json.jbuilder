json.id resource.id
json.deal_id resource.deal_id
json.kind resource.kind
json.content resource.content
json.due_at resource.due_at&.to_i
json.completed_at resource.completed_at&.to_i
json.created_at resource.created_at.to_i

if resource.user.present?
  json.user do
    json.id resource.user.id
    json.name resource.user.name
  end
end
