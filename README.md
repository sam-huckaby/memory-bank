# Memory Bank - Photo Display API

A REST API service for managing and serving photos to a living room revolving display. Built with OCaml and Dream web framework.

## Features

- **Random Playlists:** Serves up to 1000 photos in random order on each request
- **EXIF Metadata Extraction:** Automatically extracts photo date, dimensions from image files
- **Multiple Format Support:** JPEG, PNG, HEIC, HEIF, GIF, TIFF (all iPhone photo formats)
- **SQLite Storage:** Lightweight database for photo metadata
- **Flat File Storage:** Photos stored by UUID for simple management
- **Stateless Design:** No session management, perfect for multiple display clients

## Requirements

- OCaml >= 4.14
- opam (OCaml package manager)
- exiftool (for EXIF extraction)

Install exiftool:
```bash
# macOS
brew install exiftool

# Linux (Debian/Ubuntu)
apt-get install libimage-exiftool-perl

# Linux (Fedora)
dnf install perl-Image-ExifTool
```

## Installation

1. Clone the repository:
```bash
git clone <repository-url>
cd memory-bank
```

2. Install dependencies:
```bash
opam install . --deps-only
```

3. Build the project:
```bash
dune build
```

## Configuration

Set the following environment variables:

```bash
# Required: Directory where photos will be stored
export PHOTO_STORAGE_PATH=/path/to/photos

# Optional: Database location (default: ./photos.db)
export DATABASE_PATH=/path/to/photos.db

# Optional: Server port (default: 8080)
export PORT=8080

# Optional: CORS allowed origins (default: * allows all origins)
export CORS_ALLOWED_ORIGINS=*
```

Or create a `.env` file (see `.env.example`).

## Running the Server

```bash
dune exec memory-bank
```

The server will start and display:
```
[INFO] Photo storage: /path/to/photos
[INFO] Database: /path/to/photos.db
[INFO] Port: 8080
[INFO] CORS allowed origins: *
[INFO] Server starting on http://localhost:8080
[INFO] Ready to serve photos!
```

## CORS Configuration

The server supports Cross-Origin Resource Sharing (CORS) to allow requests from web applications and mobile apps running on different origins.

### Default Behavior

By default, **all origins are allowed** (`CORS_ALLOWED_ORIGINS=*`). This is suitable for home network deployments where the server is not exposed to the internet.

### Custom Origins

For added security, you can restrict access to specific origins by setting the `CORS_ALLOWED_ORIGINS` environment variable:

**Single origin (web app on localhost):**
```bash
export CORS_ALLOWED_ORIGINS=http://localhost:3000
```

**Multiple origins (web app + local network access):**
```bash
export CORS_ALLOWED_ORIGINS=http://localhost:3000,http://192.168.1.5:3000
```

**Android app access:**
Android apps should use your server's local network IP address. For example, if your server runs on `192.168.1.100:8080`, the Android app would make requests to `http://192.168.1.100:8080/api/photos`.

Native mobile apps are not subject to browser CORS restrictions, but you may still want to include their origins in the whitelist for consistency.

**Future HTTPS support:**
When running behind HTTPS, update your origins accordingly:
```bash
export CORS_ALLOWED_ORIGINS=https://myapp.com,https://192.168.1.100:8443
```

### CORS Headers

The server automatically adds the following headers to matching origins:
- `Access-Control-Allow-Origin`: The matching origin or `*`
- `Access-Control-Allow-Methods`: `GET, POST, OPTIONS`
- `Access-Control-Allow-Headers`: `Content-Type`
- `Access-Control-Max-Age`: `86400` (24-hour preflight cache)

---

## API Endpoints

### 1. Upload a Photo

**Endpoint:** `POST /api/photos`

**Description:** Upload a new photo to the collection. Automatically generates a unique ID, extracts EXIF metadata (including date taken), and stores the photo.

**Request:**
```bash
curl -X POST http://localhost:8080/api/photos \
  -F "photo=@/path/to/your/photo.jpg"
```

**Response (201 Created):**
```json
{
  "id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
  "original_filename": "photo.jpg",
  "date_taken": "2023-12-13T14:30:45Z",
  "file_size": 2048576,
  "width": 4032,
  "height": 3024,
  "mime_type": "image/jpeg",
  "created_at": "2024-12-13T20:15:30Z"
}
```

**Notes:**
- `date_taken` is extracted from EXIF data, falls back to upload time if unavailable
- Photo is stored on disk with UUID-only filename (no extension)
- Original filename preserved in database

---

### 2. Get Random Playlist

**Endpoint:** `GET /api/playlist`

**Description:** Returns all photos (up to 1000) in random order. Each request produces a different random ordering.

**Request:**
```bash
curl http://localhost:8080/api/playlist
```

**Response (200 OK):**
```json
[
  {
    "id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
    "original_filename": "sunset.jpg",
    "date_taken": "2023-12-13T14:30:45Z",
    "file_size": 2048576,
    "width": 4032,
    "height": 3024,
    "mime_type": "image/jpeg",
    "created_at": "2024-12-13T20:15:30Z"
  },
  {
    "id": "b2c3d4e5-f6a7-8901-bcde-f12345678901",
    "original_filename": "beach.heic",
    "date_taken": "2023-11-20T09:15:22Z",
    "file_size": 1524288,
    "width": 3024,
    "height": 4032,
    "mime_type": "image/heic",
    "created_at": "2024-12-13T20:16:45Z"
  }
]
```

**Notes:**
- Order is randomized on every request
- Returns all available photos up to 1000
- Use this to populate your display client

---

### 3. Get Photo by ID

**Endpoint:** `GET /api/photos/:id`

**Description:** Download the actual photo file by its ID.

**Request:**
```bash
curl http://localhost:8080/api/photos/a1b2c3d4-e5f6-7890-abcd-ef1234567890 \
  --output photo.jpg
```

**Response:**
- Status: 200 OK
- Content-Type: `image/jpeg` (or appropriate MIME type)
- Body: Binary image data

**Display in browser:**
```
http://localhost:8080/api/photos/a1b2c3d4-e5f6-7890-abcd-ef1234567890
```

---

### 4. Get Photo Metadata

**Endpoint:** `GET /api/photos/:id/metadata`

**Description:** Get metadata for a specific photo without downloading the image.

**Request:**
```bash
curl http://localhost:8080/api/photos/a1b2c3d4-e5f6-7890-abcd-ef1234567890/metadata
```

**Response (200 OK):**
```json
{
  "id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
  "original_filename": "sunset.jpg",
  "date_taken": "2023-12-13T14:30:45Z",
  "file_size": 2048576,
  "width": 4032,
  "height": 3024,
  "mime_type": "image/jpeg",
  "created_at": "2024-12-13T20:15:30Z"
}
```

---

### 5. List All Photos (Paginated)

**Endpoint:** `GET /api/photos`

**Description:** Retrieve a paginated list of all photos, ordered by date. Perfect for building a photo browser with infinite scroll. By default, photos are sorted by the date they were taken (newest first), but you can customize the sorting to use upload date instead.

**Query Parameters:**
- `page` (optional, default: `1`) - Page number, 1-based indexing (minimum: 1)
- `limit` (optional, default: `50`) - Number of photos per page (minimum: 1, maximum: 100)
- `order` (optional, default: `"desc"`) - Sort order: `"asc"` (oldest first) or `"desc"` (newest first)
- `sort_by` (optional, default: `"date_taken"`) - Sort field: `"date_taken"` or `"created_at"`

**Request Examples:**

Get first page with defaults (50 photos, sorted by date_taken descending):
```bash
curl http://localhost:8080/api/photos
```

Get second page with 20 photos per page:
```bash
curl "http://localhost:8080/api/photos?page=2&limit=20"
```

Get photos sorted by upload date (created_at) in ascending order:
```bash
curl "http://localhost:8080/api/photos?sort_by=created_at&order=asc"
```

Get third page, sorted by date taken, oldest first:
```bash
curl "http://localhost:8080/api/photos?page=3&sort_by=date_taken&order=asc"
```

**Response (200 OK):**
```json
{
  "photos": [
    {
      "id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
      "original_filename": "sunset.jpg",
      "date_taken": "2023-12-13T14:30:45Z",
      "file_size": 2048576,
      "width": 4032,
      "height": 3024,
      "mime_type": "image/jpeg",
      "created_at": "2024-12-13T20:15:30Z"
    },
    {
      "id": "b2c3d4e5-f6a7-8901-bcde-f12345678901",
      "original_filename": "beach.heic",
      "date_taken": "2023-11-20T09:15:22Z",
      "file_size": 1524288,
      "width": 3024,
      "height": 4032,
      "mime_type": "image/heic",
      "created_at": "2024-12-13T20:16:45Z"
    }
  ],
  "pagination": {
    "page": 1,
    "limit": 50,
    "total": 150,
    "total_pages": 3,
    "has_next": true,
    "has_prev": false
  }
}
```

**Pagination Metadata:**
- `page` - Current page number
- `limit` - Number of items per page
- `total` - Total number of photos in database
- `total_pages` - Total number of pages available
- `has_next` - Boolean indicating if there's a next page
- `has_prev` - Boolean indicating if there's a previous page

**Notes:**
- Invalid query parameters are automatically sanitized to safe defaults
- Pages are 1-indexed (first page is `page=1`)
- Empty database returns `{"photos": [], "pagination": {...}}`
- Photos are efficiently queried using database indexes on both `date_taken` and `created_at`

**NextJS Infinite Scroll Integration:**

Here's a pattern for implementing infinite scroll in a NextJS app:

```typescript
// Example React component with infinite scroll
import { useState, useEffect } from 'react';
import InfiniteScroll from 'react-infinite-scroll-component';

interface Photo {
  id: string;
  original_filename: string;
  date_taken: string;
  file_size: number;
  width?: number;
  height?: number;
  mime_type: string;
  created_at: string;
}

interface Pagination {
  page: number;
  limit: number;
  total: number;
  total_pages: number;
  has_next: boolean;
  has_prev: boolean;
}

export default function PhotoGallery() {
  const [photos, setPhotos] = useState<Photo[]>([]);
  const [pagination, setPagination] = useState<Pagination | null>(null);
  const [page, setPage] = useState(1);
  
  const API_URL = 'http://localhost:8080';
  
  // Fetch initial photos
  useEffect(() => {
    fetchPhotos(1);
  }, []);
  
  const fetchPhotos = async (pageNum: number) => {
    const response = await fetch(
      `${API_URL}/api/photos?page=${pageNum}&limit=50&order=desc&sort_by=date_taken`
    );
    const data = await response.json();
    
    if (pageNum === 1) {
      setPhotos(data.photos);
    } else {
      setPhotos(prev => [...prev, ...data.photos]);
    }
    setPagination(data.pagination);
  };
  
  const loadMore = () => {
    if (pagination?.has_next) {
      const nextPage = page + 1;
      setPage(nextPage);
      fetchPhotos(nextPage);
    }
  };
  
  return (
    <InfiniteScroll
      dataLength={photos.length}
      next={loadMore}
      hasMore={pagination?.has_next ?? false}
      loader={<h4>Loading...</h4>}
      endMessage={<p>No more photos</p>}
    >
      <div className="grid grid-cols-3 gap-4">
        {photos.map(photo => (
          <div key={photo.id}>
            <img 
              src={`${API_URL}/api/photos/${photo.id}`}
              alt={photo.original_filename}
              className="w-full h-auto"
            />
            <p className="text-sm">{photo.original_filename}</p>
            <p className="text-xs text-gray-500">
              {new Date(photo.date_taken).toLocaleDateString()}
            </p>
          </div>
        ))}
      </div>
    </InfiniteScroll>
  );
}
```

**React Query (TanStack Query) Pattern:**

For more robust data fetching with caching:

```typescript
import { useInfiniteQuery } from '@tanstack/react-query';

const fetchPhotosPage = async ({ pageParam = 1 }) => {
  const response = await fetch(
    `http://localhost:8080/api/photos?page=${pageParam}&limit=50`
  );
  return response.json();
};

export default function PhotoGallery() {
  const {
    data,
    fetchNextPage,
    hasNextPage,
    isFetchingNextPage,
    status,
  } = useInfiniteQuery({
    queryKey: ['photos'],
    queryFn: fetchPhotosPage,
    getNextPageParam: (lastPage) => 
      lastPage.pagination.has_next ? lastPage.pagination.page + 1 : undefined,
  });

  // Flatten all pages into single photo array
  const photos = data?.pages.flatMap(page => page.photos) ?? [];
  
  return (
    <InfiniteScroll
      dataLength={photos.length}
      next={fetchNextPage}
      hasMore={!!hasNextPage}
      loader={<h4>Loading...</h4>}
    >
      {/* Render photos */}
    </InfiniteScroll>
  );
}
```

---

## Testing Without Web Interface

### Step 1: Upload Photos

Upload multiple photos to build your collection:

```bash
# Upload a single photo
curl -X POST http://localhost:8080/api/photos \
  -F "photo=@vacation1.jpg"

# Upload multiple photos in a loop
for photo in ~/Pictures/vacation/*.jpg; do
  curl -X POST http://localhost:8080/api/photos \
    -F "photo=@$photo"
  echo "Uploaded: $photo"
done
```

### Step 2: Get a Playlist

Retrieve the random playlist:

```bash
curl http://localhost:8080/api/playlist | jq
```

Save to file for processing:

```bash
curl http://localhost:8080/api/playlist > playlist.json
```

### Step 3: Download Photos

Extract photo IDs and download them:

```bash
# Get first photo ID from playlist
PHOTO_ID=$(curl -s http://localhost:8080/api/playlist | jq -r '.[0].id')

# Download that photo
curl http://localhost:8080/api/photos/$PHOTO_ID --output photo.jpg

# Open in default image viewer
open photo.jpg  # macOS
xdg-open photo.jpg  # Linux
```

### Step 4: View Metadata

Check metadata for a specific photo:

```bash
PHOTO_ID="a1b2c3d4-e5f6-7890-abcd-ef1234567890"
curl http://localhost:8080/api/photos/$PHOTO_ID/metadata | jq
```

### Step 5: Delete a Photo

Delete a photo from the collection:

```bash
PHOTO_ID="a1b2c3d4-e5f6-7890-abcd-ef1234567890"
curl -X DELETE http://localhost:8080/api/photos/$PHOTO_ID | jq
```

### 6. Delete a Photo

**Endpoint:** `DELETE /api/photos/:id`

**Description:** Soft delete a photo from the collection. The photo is marked as deleted in the database and the file is moved to a `deleted/` subdirectory for potential recovery. Deleted photos are immediately excluded from all API responses (playlist, list, get).

**Request:**
```bash
curl -X DELETE http://localhost:8080/api/photos/a1b2c3d4-e5f6-7890-abcd-ef1234567890
```

**Response (200 OK):**
```json
{
  "message": "Photo deleted successfully"
}
```

**Error Responses:**

404 Not Found - Photo doesn't exist or already deleted:
```json
{
  "error": "Photo not found or already deleted",
  "id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890"
}
```

500 Internal Server Error - Server error during deletion:
```json
{
  "error": "Failed to delete photo"
}
```

**Notes:**
- Uses soft delete approach: photos are marked as deleted but files are preserved
- Deleted files are moved to `PHOTO_STORAGE_PATH/deleted/` directory
- Transaction-safe: database and filesystem stay in sync (rollback on failure)
- Deleted photos are automatically excluded from all API endpoints
- Structured deletion events are logged to stdout in JSON format
- Attempting to delete the same photo twice returns 404
- Physical cleanup of soft-deleted photos can be implemented separately

**Deletion Process:**
1. Photo is moved to temporary backup location
2. Database transaction marks photo as deleted
3. On success, file is moved to `deleted/` directory
4. On failure, file is restored from backup
5. Structured log event is written

**Structured Log Output:**
```json
{
  "timestamp": "2025-12-20T15:30:45.000Z",
  "level": "INFO",
  "component": "photo_management",
  "message": "Photo soft deleted successfully",
  "details": {
    "photo_id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
    "original_filename": "sunset.jpg",
    "deleted_at": "2025-12-20T15:30:45.000Z",
    "operation": "soft_delete"
  }
}
```

---

## Example: Complete Workflow

```bash
# 1. Upload a photo
RESPONSE=$(curl -s -X POST http://localhost:8080/api/photos \
  -F "photo=@family_photo.jpg")

echo "Upload response:"
echo $RESPONSE | jq

# 2. Extract the ID from response
PHOTO_ID=$(echo $RESPONSE | jq -r '.id')
echo "Photo ID: $PHOTO_ID"

# 3. Get the playlist
echo "Current playlist:"
curl -s http://localhost:8080/api/playlist | jq '.[].original_filename'

# 4. View the photo
curl http://localhost:8080/api/photos/$PHOTO_ID --output downloaded.jpg
open downloaded.jpg

# 5. Check metadata
echo "Photo metadata:"
curl -s http://localhost:8080/api/photos/$PHOTO_ID/metadata | jq

# 6. Delete the photo
echo "Deleting photo..."
curl -X DELETE -s http://localhost:8080/api/photos/$PHOTO_ID | jq

# 7. Verify deletion (should return 404)
echo "Attempting to get deleted photo:"
curl -s http://localhost:8080/api/photos/$PHOTO_ID/metadata | jq
```

---

## Database Schema

Photos are stored in SQLite with the following schema:

```sql
CREATE TABLE photos (
  id TEXT PRIMARY KEY,              -- UUID v4
  original_filename TEXT NOT NULL,  -- Original filename from upload
  date_taken TEXT NOT NULL,         -- ISO 8601 (EXIF or fallback to upload time)
  file_size INTEGER NOT NULL,       -- Bytes
  width INTEGER,                    -- Pixels (nullable if extraction fails)
  height INTEGER,                   -- Pixels (nullable if extraction fails)
  mime_type TEXT NOT NULL,          -- image/jpeg, image/png, image/heic, etc.
  created_at TEXT NOT NULL,         -- ISO 8601 upload timestamp
  deleted_at TEXT                   -- ISO 8601 deletion timestamp (NULL = active)
);

CREATE INDEX idx_date_taken ON photos(date_taken);
CREATE INDEX idx_created_at ON photos(created_at);
CREATE INDEX idx_deleted_at ON photos(deleted_at);
```

**Soft Delete:** Photos with a non-NULL `deleted_at` timestamp are automatically excluded from all queries. The database is automatically migrated on server startup to add the `deleted_at` column if upgrading from an older version.

---

## File Storage

Photos are stored in the directory specified by `PHOTO_STORAGE_PATH`:

```
/path/to/photos/
  a1b2c3d4-e5f6-7890-abcd-ef1234567890    # Active photo
  b2c3d4e5-f6a7-8901-bcde-f12345678901    # Active photo
  c3d4e5f6-a7b8-9012-cdef-123456789012    # Active photo
  backups/                                  # Temporary during deletion transactions
  deleted/                                  # Soft-deleted photos
    d4e5f6a7-b8c9-0123-def1-234567890123
```

**Notes:**
- No file extensions (use MIME type from database)
- UUID ensures no filename conflicts
- Active photos stored in root directory
- Soft-deleted photos moved to `deleted/` subdirectory
- `backups/` subdirectory used during deletion transactions (normally empty)
- Both subdirectories are created automatically on server startup

---

## Supported Image Formats

All formats commonly used by iPhones:

- **JPEG** (.jpg, .jpeg) - Standard photos
- **PNG** (.png) - Screenshots
- **HEIC/HEIF** (.heic, .heif) - Modern iOS format (iOS 11+)
- **GIF** (.gif) - Animated images
- **TIFF** (.tif, .tiff) - Legacy format

---

## Troubleshooting

### Server won't start

**Error:** `PHOTO_STORAGE_PATH not set`
```bash
# Solution: Set the environment variable
export PHOTO_STORAGE_PATH=/path/to/photos
mkdir -p /path/to/photos
```

### Upload fails with "Invalid file"

**Check:**
- File is a valid image format
- File isn't corrupted
- Server has write permissions to storage directory

### EXIF date not extracted

**Note:** If EXIF data is missing, the API automatically falls back to the upload timestamp. Check the response:
- `date_taken` will equal `created_at` if EXIF was unavailable

### exiftool not found

**Error:** `exiftool: command not found`
```bash
# Install exiftool (see Requirements section)
brew install exiftool  # macOS
```

---

## Living Room Display Client Example

Here's a simple pattern for a display client:

```javascript
// Pseudocode for display client
async function startPhotoDisplay() {
  // Get random playlist
  const playlist = await fetch('http://localhost:8080/api/playlist')
    .then(r => r.json());
  
  // Display each photo for 10 seconds
  for (const photo of playlist) {
    const imageUrl = `http://localhost:8080/api/photos/${photo.id}`;
    displayImage(imageUrl, photo);
    await sleep(10000);
  }
  
  // Get fresh playlist and repeat
  startPhotoDisplay();
}
```

---

## Development

### Project Structure

```
memory-bank/
├── lib/
│   ├── config.ml         -- Environment configuration
│   ├── database.ml       -- SQLite operations
│   ├── models.ml         -- Photo type definitions
│   ├── metadata.ml       -- EXIF extraction
│   ├── storage.ml        -- File system operations
│   └── playlist.ml       -- Playlist query logic
├── bin/
│   └── main.ml           -- Dream server and routing
├── test/
│   └── test_memory_bank.ml
└── dune-project          -- Build configuration
```

### Build Commands

```bash
# Build
dune build

# Run
dune exec memory-bank

# Run tests
dune test

# Clean build artifacts
dune clean

# Watch mode (rebuild on file changes)
dune build --watch
```

---

## Future Enhancements

Planned features (not yet implemented):

- Web UI for uploading photos
- Thumbnail generation for faster loading
- Photo filtering by date range
- Search by filename or metadata
- Duplicate detection
- Batch upload endpoint
- Advanced sorting options (by file size, dimensions, etc.)
- Restore deleted photos endpoint
- Permanent deletion/cleanup of soft-deleted photos
- View soft-deleted photos endpoint

---

## License

MIT

## Contributing

Contributions welcome! Please file issues or submit pull requests.

---

## Support

For issues or questions, please file an issue on the GitHub repository.
