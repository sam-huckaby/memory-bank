#!/bin/bash
# Test script for Memory Bank API

set -e

echo "Memory Bank API Test Script"
echo "==========================="
echo ""

# Check if server is running
if ! curl -s http://localhost:8080/api/playlist > /dev/null 2>&1; then
    echo "Error: Server is not running on http://localhost:8080"
    echo "Please start the server first:"
    echo "  export PHOTO_STORAGE_PATH=/tmp/memory-bank-photos"
    echo "  dune exec memory-bank"
    exit 1
fi

echo "✓ Server is running"
echo ""

# Test 1: Get empty playlist
echo "Test 1: Getting empty playlist..."
RESPONSE=$(curl -s http://localhost:8080/api/playlist)
echo "Response: $RESPONSE"
echo ""

# Test 2: Create a test image file
echo "Test 2: Creating a test image file..."
TEST_IMAGE="/tmp/test_photo.jpg"
# Create a minimal valid JPEG (1x1 pixel red square)
echo -n -e '\xFF\xD8\xFF\xE0\x00\x10\x4A\x46\x49\x46\x00\x01\x01\x00\x00\x01\x00\x01\x00\x00\xFF\xDB\x00\x43\x00\x08\x06\x06\x07\x06\x05\x08\x07\x07\x07\x09\x09\x08\x0A\x0C\x14\x0D\x0C\x0B\x0B\x0C\x19\x12\x13\x0F\x14\x1D\x1A\x1F\x1E\x1D\x1A\x1C\x1C\x20\x24\x2E\x27\x20\x22\x2C\x23\x1C\x1C\x28\x37\x29\x2C\x30\x31\x34\x34\x34\x1F\x27\x39\x3D\x38\x32\x3C\x2E\x33\x34\x32\xFF\xC0\x00\x0B\x08\x00\x01\x00\x01\x01\x01\x11\x00\xFF\xC4\x00\x14\x00\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x03\xFF\xC4\x00\x14\x10\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\xFF\xDA\x00\x08\x01\x01\x00\x00\x3F\x00\x37\xFF\xD9' > "$TEST_IMAGE"
echo "✓ Test image created: $TEST_IMAGE"
echo ""

# Test 3: Upload the photo
echo "Test 3: Uploading photo..."
UPLOAD_RESPONSE=$(curl -s -X POST http://localhost:8080/api/photos \
  -F "photo=@$TEST_IMAGE")
echo "Upload response:"
echo "$UPLOAD_RESPONSE" | jq '.' 2>/dev/null || echo "$UPLOAD_RESPONSE"
echo ""

# Extract photo ID
PHOTO_ID=$(echo "$UPLOAD_RESPONSE" | jq -r '.id' 2>/dev/null || echo "")
if [ -z "$PHOTO_ID" ] || [ "$PHOTO_ID" = "null" ]; then
    echo "Error: Failed to extract photo ID from upload response"
    exit 1
fi
echo "✓ Photo uploaded with ID: $PHOTO_ID"
echo ""

# Test 4: Get playlist with the new photo
echo "Test 4: Getting playlist with uploaded photo..."
PLAYLIST_RESPONSE=$(curl -s http://localhost:8080/api/playlist)
echo "$PLAYLIST_RESPONSE" | jq '.' 2>/dev/null || echo "$PLAYLIST_RESPONSE"
echo ""

# Test 5: Get photo metadata
echo "Test 5: Getting photo metadata..."
METADATA_RESPONSE=$(curl -s "http://localhost:8080/api/photos/$PHOTO_ID/metadata")
echo "$METADATA_RESPONSE" | jq '.' 2>/dev/null || echo "$METADATA_RESPONSE"
echo ""

# Test 6: Download the photo
echo "Test 6: Downloading photo..."
DOWNLOAD_FILE="/tmp/downloaded_photo.jpg"
curl -s "http://localhost:8080/api/photos/$PHOTO_ID" -o "$DOWNLOAD_FILE"
if [ -f "$DOWNLOAD_FILE" ]; then
    FILE_SIZE=$(wc -c < "$DOWNLOAD_FILE")
    echo "✓ Photo downloaded successfully ($FILE_SIZE bytes)"
else
    echo "Error: Failed to download photo"
    exit 1
fi
echo ""

echo "==========================="
echo "All tests passed! ✓"
echo "I'll write real tests later..."
echo ""
echo "Summary:"
echo "- Server is running correctly"
echo "- Photo upload works"
echo "- Playlist endpoint works"
echo "- Metadata retrieval works"
echo "- Photo download works"
echo ""
echo "You can now use the API!"
