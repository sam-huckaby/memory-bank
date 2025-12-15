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
[INFO] Server starting on http://localhost:8080
[INFO] Ready to serve photos!
```

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
  created_at TEXT NOT NULL          -- ISO 8601 upload timestamp
);
```

---

## File Storage

Photos are stored in the directory specified by `PHOTO_STORAGE_PATH`:

```
/path/to/photos/
  a1b2c3d4-e5f6-7890-abcd-ef1234567890
  b2c3d4e5-f6a7-8901-bcde-f12345678901
  c3d4e5f6-a7b8-9012-cdef-123456789012
```

**Notes:**
- No file extensions (use MIME type from database)
- UUID ensures no filename conflicts
- Flat directory structure for simple management

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
- Photo deletion endpoint

---

## License

MIT

## Contributing

Contributions welcome! Please file issues or submit pull requests.

---

## Support

For issues or questions, please file an issue on the GitHub repository.
