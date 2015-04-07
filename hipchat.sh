#!/bin/sh
curl -H "Content-Type: application/json" \
     -X POST \
     -d "{\"color\": \"purple\", \"message_format\": \"text\", \"message\": \"$1\" }" \
     "https://api.hipchat.com/v2/room/807962/notification?auth_token=${HIPCHAT_API_KEY}"