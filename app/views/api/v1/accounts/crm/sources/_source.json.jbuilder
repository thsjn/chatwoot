json.id resource.id
json.name resource.name
json.kind resource.kind
json.inbox_id resource.inbox_id
json.identifier resource.identifier
json.active resource.active
# Never the token nor its digest: only whether the source has already been credentialed, which is
# what tells the screen to offer "generate" or "regenerate".
json.has_token resource.token?
