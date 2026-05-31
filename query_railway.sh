#!/bin/bash
TOKEN="QlDm..."
curl -s \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"query":"{ deployments(input: {serviceId: \"7defa0b8-c329-44da-9944-3bf3afe8164d\"}, first: 5) { edges { node { id status createdAt } } } }"}' \
  https://backboard.railway.app/graphql/v2
