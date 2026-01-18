module hono_upload

import hono
import v_hono_storage
import net.http
import os
import crypto.md5
import x.json2
import time

// 验证文件哈希（MD5格式）
fn validate_file_hash(hash string) !string {
	if hash.len != 32 {
		return error('File hash must be 32 characters (MD5)')
	}
	for c in hash {
		if !((c >= `0` && c <= `9`) || (c >= `a` && c <= `f`) || (c >= `A` && c <= `F`)) {
			return error('File hash must be a valid hexadecimal string')
		}
	}
	return hash.to_lower()
}

// 验证文件名
fn validate_filename(filename string) !string {
	if filename == '' {
		return error('Filename cannot be empty')
	}
	dangerous_chars := ['..', '/', '\\', '\x00', '\n', '\r']
	for ch in dangerous_chars {
		if filename.contains(ch) {
			return error('Filename contains dangerous characters')
		}
	}
	return filename
}

// 验证文件大小
fn validate_file_size(size_str string, max_size int) !int {
	size := size_str.int()
	if size <= 0 {
		return error('File size must be positive')
	}
	if size > max_size {
		return error('File size exceeds maximum allowed (${max_size} bytes)')
	}
	return size
}

// 验证分片索引
fn validate_chunk_index(index_str string, max_index int) !int {
	index := index_str.int()
	if index < 0 {
		return error('Chunk index must be non-negative')
	}
	if max_index > 0 && index >= max_index {
		return error('Chunk index exceeds maximum (${max_index})')
	}
	return index
}


// 分片上传配置
pub struct ChunkUploadConfig {
pub:
	chunk_size            int    = 1024 * 1024           // 1MB 默认分片大小
	max_file_size         int    = 1024 * 1024 * 1024    // 1GB 最大文件大小
	max_chunk_size        int    = 10 * 1024 * 1024      // 10MB 最大分片大小
	temp_dir              string = './uploads/chunks'    // 临时分片目录
	cleanup_delay         int    = 3600                  // 1小时后清理临时文件
	clear_chunks_on_complete bool                        // 上传完成后是否清空分片
	merge_buffer_size     int    = 8192                  // 文件合并时的缓冲区大小
}

// 分片信息
pub struct ChunkInfo {
pub:
	file_hash    string
	chunk_index  int
	total_chunks int
	filename     string
	file_size    int
	chunk_size   int
	upload_time  int
}

// 文件上传状态
pub struct FileUploadStatus {
pub:
	file_hash    string
	filename     string
	total_chunks int
	file_size    int
	chunk_size   int
	created_at   int
pub mut:
	uploaded_chunks []int
	status          string
	updated_at      int
}

// 分片上传管理器 - 集成 v-hono-storage
pub struct ChunkUploadManager {
pub mut:
	config       ChunkUploadConfig
	uploads      map[string]FileUploadStatus
	file_service &v_hono_storage.FileService = unsafe { nil }
}

// 创建分片上传管理器（使用现有的 FileService）
pub fn new_chunk_upload_manager_with_storage(config ChunkUploadConfig, mut file_service v_hono_storage.FileService) ChunkUploadManager {
	os.mkdir_all(config.temp_dir) or { panic('Failed to create temp directory') }
	
	return ChunkUploadManager{
		config: config
		uploads: map[string]FileUploadStatus{}
		file_service: file_service
	}
}

// 创建分片上传管理器（自动创建本地 FileService）
pub fn new_chunk_upload_manager(config ChunkUploadConfig, storage_path string, db_path string) !ChunkUploadManager {
	os.mkdir_all(config.temp_dir) or { 
		return error('Failed to create temp directory: ${err}')
	}
	
	mut file_service := v_hono_storage.new_local_file_service(storage_path, db_path)!
	
	return ChunkUploadManager{
		config: config
		uploads: map[string]FileUploadStatus{}
		file_service: &file_service
	}
}


// 处理分片上传
pub fn (mut manager ChunkUploadManager) handle_chunk_upload(mut ctx hono.Context) http.Response {
	// 解析 multipart 表单数据
	content_type := ctx.req.header.get(.content_type) or { '' }
	parser := new_multipart_parser(content_type, ctx.body) or {
		ctx.status(400)
		return ctx.json('{"error": "Invalid form data"}')
	}
	
	items := parser.parse() or {
		ctx.status(400)
		return ctx.json('{"error": "Failed to parse form data"}')
	}
	
	mut form_data := map[string]string{}
	for item in items {
		if item.filename == '' {
			form_data[item.name] = item.content
		}
	}
	
	// 获取并验证必要参数
	file_hash_raw := form_data['file_hash'] or {
		ctx.status(400)
		return ctx.json('{"error": "Missing parameter: file_hash"}')
	}
	
	file_hash := validate_file_hash(file_hash_raw) or {
		ctx.status(400)
		return ctx.json('{"error": "Invalid parameter file_hash: ${err.msg()}"}')
	}
	
	chunk_index_str := form_data['chunk_index'] or {
		ctx.status(400)
		return ctx.json('{"error": "Missing parameter: chunk_index"}')
	}
	
	filename_raw := form_data['filename'] or {
		ctx.status(400)
		return ctx.json('{"error": "Missing parameter: filename"}')
	}
	
	filename := validate_filename(filename_raw) or {
		ctx.status(400)
		return ctx.json('{"error": "Invalid parameter filename: ${err.msg()}"}')
	}
	
	file_size_str := form_data['file_size'] or {
		ctx.status(400)
		return ctx.json('{"error": "Missing parameter: file_size"}')
	}
	
	file_size := validate_file_size(file_size_str, manager.config.max_file_size) or {
		ctx.status(400)
		return ctx.json('{"error": "Invalid parameter file_size: ${err.msg()}"}')
	}
	
	chunk_size_str := form_data['chunk_size'] or {
		ctx.status(400)
		return ctx.json('{"error": "Missing parameter: chunk_size"}')
	}
	
	chunk_size := validate_file_size(chunk_size_str, manager.config.max_chunk_size) or {
		ctx.status(400)
		return ctx.json('{"error": "Invalid parameter chunk_size: ${err.msg()}"}')
	}
	
	chunk_index := validate_chunk_index(chunk_index_str, 0) or {
		ctx.status(400)
		return ctx.json('{"error": "Invalid parameter chunk_index: ${err.msg()}"}')
	}
	
	// 获取文件数据
	mut file_data := ''
	for item in items {
		if item.name == 'chunk' && item.filename != '' {
			file_data = item.content
			break
		}
	}
	
	if file_data == '' {
		ctx.status(400)
		return ctx.json('{"error": "Missing parameter: chunk"}')
	}
	
	if file_data.len > chunk_size {
		ctx.status(400)
		return ctx.json('{"error": "Chunk data size exceeds declared chunk_size"}')
	}
	
	// 保存分片到临时目录
	chunk_dir := os.join_path(manager.config.temp_dir, file_hash, chunk_size.str())
	os.mkdir_all(chunk_dir) or {
		return ctx.file_operation_error('create_directory', chunk_dir, err.msg())
	}
	
	chunk_path := os.join_path(chunk_dir, 'chunk_${chunk_index}.part')
	os.write_file(chunk_path, file_data) or {
		return ctx.file_operation_error('save_chunk', chunk_path, err.msg())
	}
	
	// 更新上传状态
	manager.update_upload_status(file_hash, filename, chunk_index, file_size, chunk_size)
	
	// 更新分片大小记录
	manager.update_chunk_size_record(file_hash, chunk_size, file_data.len)
	
	// 检查是否所有分片都已上传
	total_chunk_size := manager.get_chunk_size_record(file_hash, chunk_size)
	
	if total_chunk_size >= u64(file_size) {
		// 所有分片已上传，执行合并并存储到 v-hono-storage
		result := manager.merge_and_store(file_hash, filename, file_size, chunk_size) or {
			return ctx.file_operation_error('merge_and_store', file_hash, err.msg())
		}
		
		if manager.config.clear_chunks_on_complete {
			manager.cleanup_chunks(file_hash, chunk_size)
		}
		
		return ctx.json('{"success": true, "all_chunk_uploaded": true, "file_uuid": "${result.file_uuid}", "message": "File uploaded successfully"}')
	}
	
	return ctx.json('{"success": true, "chunk_index": ${chunk_index}, "all_chunk_uploaded": false, "message": "Chunk uploaded successfully"}')
}


// 合并分片并存储到 v-hono-storage
fn (mut manager ChunkUploadManager) merge_and_store(file_hash string, filename string, file_size int, chunk_size int) !v_hono_storage.UploadResult {
	upload_status := manager.uploads[file_hash] or {
		return error('Upload status not found')
	}
	
	total_chunks := upload_status.uploaded_chunks.len
	chunk_dir := os.join_path(manager.config.temp_dir, file_hash, chunk_size.str())
	
	// 流式合并分片到内存
	mut final_data := []u8{}
	buffer_size := manager.config.merge_buffer_size
	mut buffer := []u8{len: buffer_size}
	
	for i in 0 .. total_chunks {
		chunk_path := os.join_path(chunk_dir, 'chunk_${i}.part')
		
		if !os.exists(chunk_path) {
			return error('Chunk file not found: ${chunk_path}')
		}
		
		mut chunk_file := os.open(chunk_path) or {
			return error('Failed to open chunk ${i}: ${err}')
		}
		
		for {
			bytes_read := chunk_file.read(mut buffer) or { break }
			if bytes_read == 0 { break }
			final_data << buffer[..bytes_read]
		}
		
		chunk_file.close()
	}
	
	// 获取文件扩展名和 content_type
	file_ext := get_file_extension(filename)
	content_type := infer_content_type(file_ext)
	
	// 使用 v-hono-storage 上传文件
	result := manager.file_service.upload_file(v_hono_storage.UploadParams{
		filename: filename
		content_type: content_type
		metadata: '{"original_hash": "${file_hash}", "chunk_count": ${total_chunks}}'
	}, final_data)!
	
	// 更新状态为完成
	manager.uploads[file_hash].status = 'completed'
	manager.uploads[file_hash].updated_at = int(time.now().unix())
	
	return result
}

// 合并请求结构
pub struct MergeRequest {
pub:
	file_hash    string @[json: 'file_hash']
	filename     string
	total_chunks int    @[json: 'total_chunks']
}

// 处理分片合并（手动触发）
pub fn (mut manager ChunkUploadManager) handle_chunk_merge(mut ctx hono.Context) http.Response {
	merge_request := json2.decode[MergeRequest](ctx.body) or {
		ctx.status(400)
		return ctx.json('{"error": "Invalid request body"}')
	}
	
	file_hash := merge_request.file_hash
	filename := merge_request.filename
	total_chunks := merge_request.total_chunks
	
	upload_status := manager.uploads[file_hash] or {
		return ctx.resource_not_found('upload', file_hash)
	}
	
	if upload_status.uploaded_chunks.len != total_chunks {
		ctx.status(400)
		return ctx.json('{"error": "Not all chunks uploaded", "uploaded": ${upload_status.uploaded_chunks.len}, "total": ${total_chunks}}')
	}
	
	chunk_size := upload_status.chunk_size
	
	result := manager.merge_and_store(file_hash, filename, upload_status.file_size, chunk_size) or {
		return ctx.file_operation_error('merge_and_store', file_hash, err.msg())
	}
	
	manager.cleanup_chunks(file_hash, chunk_size)
	
	return ctx.json('{"success": true, "file_uuid": "${result.file_uuid}", "message": "File merged successfully"}')
}

// 获取上传状态
pub fn (manager ChunkUploadManager) get_upload_status(mut ctx hono.Context) http.Response {
	file_hash := ctx.query['file_hash'] or {
		ctx.status(400)
		return ctx.json('{"error": "Missing parameter: file_hash"}')
	}
	
	upload_status := manager.uploads[file_hash] or {
		return ctx.resource_not_found('upload', file_hash)
	}
	
	return ctx.json(json2.encode[FileUploadStatus](upload_status))
}


// 更新上传状态
pub fn (mut manager ChunkUploadManager) update_upload_status(file_hash string, filename string, chunk_index int, file_size int, chunk_size int) {
	now := int(time.now().unix())
	
	if file_hash !in manager.uploads {
		manager.uploads[file_hash] = FileUploadStatus{
			file_hash: file_hash
			filename: filename
			total_chunks: 0
			uploaded_chunks: []
			file_size: file_size
			chunk_size: chunk_size
			status: 'uploading'
			created_at: now
			updated_at: now
		}
	}
	
	if chunk_index !in manager.uploads[file_hash].uploaded_chunks {
		manager.uploads[file_hash].uploaded_chunks << chunk_index
	}
	
	manager.uploads[file_hash].updated_at = now
}

// 清理临时分片
fn (mut manager ChunkUploadManager) cleanup_chunks(file_hash string, chunk_size int) {
	chunk_dir := os.join_path(manager.config.temp_dir, file_hash.trim_space(), chunk_size.str())
	if os.exists(chunk_dir) {
		manager.cleanup_chunk_size_record(file_hash, chunk_size)
		os.rmdir_all(chunk_dir) or {}
	}
}

// 公共清理方法
pub fn (mut manager ChunkUploadManager) cleanup_chunks_public(file_hash string, chunk_size int) {
	manager.cleanup_chunks(file_hash, chunk_size)
}

// 更新分片大小记录
pub fn (mut manager ChunkUploadManager) update_chunk_size_record(file_hash string, chunk_size int, current_chunk_size int) {
	chunk_dir := os.join_path(manager.config.temp_dir, file_hash.trim_space(), chunk_size.str())
	size_record_path := os.join_path(chunk_dir, 'total_size.record')
	
	os.mkdir_all(chunk_dir) or { return }
	
	mut total_size := u64(0)
	if os.exists(size_record_path) {
		size_data := os.read_file(size_record_path) or { '0' }
		total_size = size_data.u64()
	}
	
	total_size += u64(current_chunk_size)
	os.write_file(size_record_path, total_size.str()) or {}
}

// 获取分片大小记录
pub fn (manager ChunkUploadManager) get_chunk_size_record(file_hash string, chunk_size int) u64 {
	chunk_dir := os.join_path(manager.config.temp_dir, file_hash.trim_space(), chunk_size.str())
	size_record_path := os.join_path(chunk_dir, 'total_size.record')
	
	if os.exists(size_record_path) {
		size_data := os.read_file(size_record_path) or { '0' }
		return size_data.u64()
	}
	return u64(0)
}

// 清理分片大小记录
pub fn (mut manager ChunkUploadManager) cleanup_chunk_size_record(file_hash string, chunk_size int) {
	chunk_dir := os.join_path(manager.config.temp_dir, file_hash.trim_space(), chunk_size.str())
	size_record_path := os.join_path(chunk_dir, 'total_size.record')
	
	if os.exists(size_record_path) {
		os.rm(size_record_path) or {}
	}
}

// 清理文件上传状态
pub fn (mut manager ChunkUploadManager) cleanup_upload_status(file_hash string) {
	if file_hash in manager.uploads {
		manager.uploads.delete(file_hash)
	}
}

// 生成文件哈希
pub fn generate_file_hash(data string) string {
	return md5.sum(data.bytes()).hex()
}

// 验证文件完整性
pub fn verify_file_integrity(file_path string, expected_hash string) bool {
	file_data := os.read_file(file_path) or { return false }
	actual_hash := generate_file_hash(file_data)
	return actual_hash == expected_hash
}

// 获取文件扩展名
fn get_file_extension(filename string) string {
	parts := filename.split('.')
	if parts.len > 1 {
		return '.${parts.last()}'
	}
	return ''
}

// 根据扩展名推断 content_type
fn infer_content_type(ext string) string {
	match ext.to_lower() {
		'.html', '.htm' { return 'text/html' }
		'.css' { return 'text/css' }
		'.js' { return 'application/javascript' }
		'.json' { return 'application/json' }
		'.xml' { return 'application/xml' }
		'.txt' { return 'text/plain' }
		'.png' { return 'image/png' }
		'.jpg', '.jpeg' { return 'image/jpeg' }
		'.gif' { return 'image/gif' }
		'.svg' { return 'image/svg+xml' }
		'.webp' { return 'image/webp' }
		'.pdf' { return 'application/pdf' }
		'.zip' { return 'application/zip' }
		'.mp3' { return 'audio/mpeg' }
		'.mp4' { return 'video/mp4' }
		else { return 'application/octet-stream' }
	}
}

// 关闭管理器（释放 FileService 资源）
pub fn (mut manager ChunkUploadManager) close() {
	if manager.file_service != unsafe { nil } {
		manager.file_service.close()
	}
}
