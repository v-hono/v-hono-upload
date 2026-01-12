# hono.upload

File upload handling for v-hono-core framework.

## Features

- Multipart form data parsing
- File upload handling
- Chunked file upload support
- Memory efficient streaming
- File storage and metadata management (SQLite-based)
- File deduplication by hash
- UUID-based file identification

## Installation

```bash
v install hono
v install hono.upload
```

## Usage

### Basic File Upload

```v
import hono
import hono_upload

fn main() {
    mut app := hono.Hono.new()

    app.post('/upload', fn (mut c hono.Context) http.Response {
        // Handle file upload
        files := hono_upload.parse_multipart(c) or {
            return c.json('{"error":"Upload failed"}')
        }
        
        return c.json('{"uploaded":${files.len}}')
    })

    app.listen(':3000')
}
```

### File Storage with Database

```v
import hono
import hono_upload

fn main() {
    mut app := hono.Hono.new()
    
    // Initialize file storage
    mut db := hono_upload.new_database_manager('files.db') or {
        eprintln('Failed to init database: ${err}')
        return
    }
    
    app.post('/upload', fn [mut db] (mut c hono.Context) http.Response {
        // Parse and store file
        files := hono_upload.parse_multipart(c) or {
            return c.json('{"error":"Upload failed"}')
        }
        
        // Save file metadata to database
        for file in files {
            info := db.insert_or_update_file(
                file.hash, 
                file.name, 
                file.size, 
                file.type
            ) or { continue }
            eprintln('Stored: ${info.file_uuid}')
        }
        
        return c.json('{"success":true}')
    })

    app.listen(':3000')
}
```

## Dependencies

- `hono` - Core framework

## License

MIT
