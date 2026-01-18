# hono_upload

Chunked file upload handling for v-hono framework with v-hono-storage integration.

## Features

- Multipart form data parsing
- Chunked file upload with resume support
- Memory efficient streaming merge
- Automatic storage to v-hono-storage (supports S3, OSS, COS, local)
- Upload progress tracking
- File deduplication by hash

## Installation

```bash
v install --git https://github.com/v-hono/v-hono-core
v install --git https://github.com/v-hono/v-hono-storage
v install --git https://github.com/v-hono/v-hono-upload
```

## Usage

### Basic Chunked Upload

```v
import hono
import hono_upload

fn main() {
    mut app := hono.new()
    
    // Create upload manager with local storage
    mut manager := hono_upload.new_chunk_upload_manager(
        hono_upload.ChunkUploadConfig{
            chunk_size: 1024 * 1024        // 1MB chunks
            max_file_size: 1024 * 1024 * 1024  // 1GB max
            temp_dir: './uploads/chunks'
            clear_chunks_on_complete: true
        },
        './storage',      // storage path
        './data/files.db' // database path
    ) or {
        eprintln('Failed to create upload manager: ${err}')
        return
    }
    defer { manager.close() }
    
    // Register upload endpoint
    app.post('/upload/chunk', fn [mut manager] (mut ctx hono.Context) http.Response {
        return manager.handle_chunk_upload(mut ctx)
    })
    
    // Register merge endpoint (optional, auto-merge is default)
    app.post('/upload/merge', fn [mut manager] (mut ctx hono.Context) http.Response {
        return manager.handle_chunk_merge(mut ctx)
    })
    
    // Register status endpoint
    app.get('/upload/status', fn [manager] (mut ctx hono.Context) http.Response {
        return manager.get_upload_status(mut ctx)
    })
    
    app.listen(8080)
}
```

### With Existing FileService (Cloud Storage)

```v
import hono
import hono_upload
import v_hono_storage

fn main() {
    mut app := hono.new()
    
    // Create FileService with S3 storage
    mut file_service := v_hono_storage.new_file_service(v_hono_storage.FileServiceConfig{
        storage: v_hono_storage.new_s3_storage_config(
            's3.amazonaws.com',
            'access_key',
            'secret_key',
            'my-bucket'
        )
        db_path: './data/files.db'
    }) or {
        eprintln('Failed to create file service: ${err}')
        return
    }
    defer { file_service.close() }
    
    // Create upload manager with existing FileService
    mut manager := hono_upload.new_chunk_upload_manager_with_storage(
        hono_upload.ChunkUploadConfig{
            chunk_size: 5 * 1024 * 1024  // 5MB chunks for cloud
            temp_dir: './uploads/chunks'
        },
        mut file_service
    )
    
    app.post('/upload/chunk', fn [mut manager] (mut ctx hono.Context) http.Response {
        return manager.handle_chunk_upload(mut ctx)
    })
    
    app.listen(8080)
}
```

## Client-Side Upload Example

```javascript
async function uploadFile(file) {
    const chunkSize = 1024 * 1024; // 1MB
    const totalChunks = Math.ceil(file.size / chunkSize);
    const fileHash = await calculateMD5(file);
    
    for (let i = 0; i < totalChunks; i++) {
        const start = i * chunkSize;
        const end = Math.min(start + chunkSize, file.size);
        const chunk = file.slice(start, end);
        
        const formData = new FormData();
        formData.append('chunk', chunk, file.name);
        formData.append('file_hash', fileHash);
        formData.append('chunk_index', i);
        formData.append('filename', file.name);
        formData.append('file_size', file.size);
        formData.append('chunk_size', chunkSize);
        
        const response = await fetch('/upload/chunk', {
            method: 'POST',
            body: formData
        });
        
        const result = await response.json();
        if (result.all_chunk_uploaded) {
            console.log('Upload complete! File UUID:', result.file_uuid);
            break;
        }
    }
}
```

## API Endpoints

### POST /upload/chunk
Upload a single chunk.

Form fields:
- `chunk` - The chunk file data
- `file_hash` - MD5 hash of the complete file (32 chars)
- `chunk_index` - Zero-based chunk index
- `filename` - Original filename
- `file_size` - Total file size in bytes
- `chunk_size` - Size of each chunk

Response:
```json
{
    "success": true,
    "chunk_index": 0,
    "all_chunk_uploaded": false,
    "message": "Chunk uploaded successfully"
}
```

When all chunks uploaded:
```json
{
    "success": true,
    "all_chunk_uploaded": true,
    "file_uuid": "abc123...",
    "message": "File uploaded successfully"
}
```

### GET /upload/status?file_hash=xxx
Get upload progress.

### POST /upload/merge
Manually trigger merge (optional).

## Dependencies

- `hono` - Core framework
- `v-hono-storage` - Multi-cloud storage service

## License

MIT
