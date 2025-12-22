#!/bin/bash

# Test script for DELETE endpoint
# Usage: ./test_delete_api.sh [photo_id]

API_BASE="http://localhost:8080/api"

echo "=== Memory Bank DELETE API Test ==="
echo ""

# Check if photo ID is provided
if [ -z "$1" ]; then
  echo "Usage: $0 <photo_id>"
  echo ""
  echo "First, let's list available photos..."
  curl -s "${API_BASE}/photos?limit=5" | jq '.photos[] | {id, original_filename, deleted_at}'
  echo ""
  echo "Please run again with a photo ID: $0 <photo_id>"
  exit 1
fi

PHOTO_ID="$1"

echo "Step 1: Get photo metadata before deletion"
echo "-------------------------------------------"
curl -s "${API_BASE}/photos/${PHOTO_ID}/metadata" | jq '.'
echo ""

echo "Step 2: Delete the photo"
echo "------------------------"
curl -X DELETE -s "${API_BASE}/photos/${PHOTO_ID}" | jq '.'
echo ""

echo "Step 3: Try to get photo metadata after deletion (should return 404)"
echo "---------------------------------------------------------------------"
curl -s "${API_BASE}/photos/${PHOTO_ID}/metadata" | jq '.'
echo ""

echo "Step 4: Try to delete the same photo again (should return 404)"
echo "---------------------------------------------------------------"
curl -X DELETE -s "${API_BASE}/photos/${PHOTO_ID}" | jq '.'
echo ""

echo "Step 5: Check that photo doesn't appear in list"
echo "------------------------------------------------"
curl -s "${API_BASE}/photos?limit=100" | jq ".photos[] | select(.id == \"${PHOTO_ID}\")"
if [ $? -eq 0 ]; then
  echo "(No matching photos found - correct!)"
fi
echo ""

echo "=== Test Complete ==="
echo ""
echo "Check the server logs for structured deletion logging."
echo "Check the storage directory for:"
echo "  - Photo should be in deleted/ subdirectory"
echo "  - backups/ subdirectory should be empty (backup cleaned up)"
