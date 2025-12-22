#!/bin/bash

# Test script for the paginated photo list API endpoint

API_BASE="http://localhost:8080"

echo "========================================="
echo "Testing Photo List API Endpoint"
echo "========================================="
echo ""

# Test 1: Basic list request (defaults)
echo "Test 1: GET /api/photos (default parameters)"
echo "Expected: 50 photos per page, sorted by date_taken DESC, page 1"
curl -s "${API_BASE}/api/photos" | jq -c '{photo_count: (.photos | length), pagination}'
echo ""

# Test 2: Custom page size
echo "Test 2: GET /api/photos?limit=10"
echo "Expected: 10 photos per page"
curl -s "${API_BASE}/api/photos?limit=10" | jq -c '{photo_count: (.photos | length), pagination}'
echo ""

# Test 3: Second page
echo "Test 3: GET /api/photos?page=2&limit=5"
echo "Expected: Page 2 with 5 photos per page"
curl -s "${API_BASE}/api/photos?page=2&limit=5" | jq -c '{photo_count: (.photos | length), pagination}'
echo ""

# Test 4: Sort by created_at ascending
echo "Test 4: GET /api/photos?sort_by=created_at&order=asc&limit=5"
echo "Expected: Sorted by upload date, oldest first"
curl -s "${API_BASE}/api/photos?sort_by=created_at&order=asc&limit=5" | jq '.photos[] | {filename: .original_filename, created_at}'
echo ""

# Test 5: Sort by date_taken descending
echo "Test 5: GET /api/photos?sort_by=date_taken&order=desc&limit=5"
echo "Expected: Sorted by date taken, newest first"
curl -s "${API_BASE}/api/photos?sort_by=date_taken&order=desc&limit=5" | jq '.photos[] | {filename: .original_filename, date_taken}'
echo ""

# Test 6: Maximum limit (100)
echo "Test 6: GET /api/photos?limit=100"
echo "Expected: Maximum of 100 photos"
curl -s "${API_BASE}/api/photos?limit=100" | jq -c '{photo_count: (.photos | length), limit: .pagination.limit}'
echo ""

# Test 7: Over-limit request (should cap at 100)
echo "Test 7: GET /api/photos?limit=200"
echo "Expected: Capped at 100 photos"
curl -s "${API_BASE}/api/photos?limit=200" | jq -c '{photo_count: (.photos | length), limit: .pagination.limit}'
echo ""

# Test 8: Invalid parameters (should use defaults)
echo "Test 8: GET /api/photos?page=-1&limit=abc&order=invalid&sort_by=invalid"
echo "Expected: Defaults applied (page=1, limit=50, order=desc, sort_by=date_taken)"
curl -s "${API_BASE}/api/photos?page=-1&limit=abc&order=invalid&sort_by=invalid" | jq -c '{pagination}'
echo ""

# Test 9: Empty database scenario
echo "Test 9: Testing with current database state"
echo "Full pagination info:"
curl -s "${API_BASE}/api/photos?limit=10" | jq '.pagination'
echo ""

echo "========================================="
echo "Testing Complete!"
echo "========================================="
