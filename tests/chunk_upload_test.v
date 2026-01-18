module main

import hono_upload

// 测试：分片上传配置
fn test_chunk_upload_config() {
	config := hono_upload.ChunkUploadConfig{
		chunk_size: 2 * 1024 * 1024  // 2MB
		max_file_size: 500 * 1024 * 1024  // 500MB
		max_chunk_size: 10 * 1024 * 1024  // 10MB
		temp_dir: './test_chunks'
		cleanup_delay: 1800
		clear_chunks_on_complete: true
		merge_buffer_size: 4096
	}
	
	assert config.chunk_size == 2 * 1024 * 1024
	assert config.max_file_size == 500 * 1024 * 1024
	assert config.max_chunk_size == 10 * 1024 * 1024
	assert config.temp_dir == './test_chunks'
	assert config.cleanup_delay == 1800
	assert config.clear_chunks_on_complete == true
	assert config.merge_buffer_size == 4096
}

// 测试：分片信息结构
fn test_chunk_info() {
	info := hono_upload.ChunkInfo{
		file_hash: 'abc123'
		chunk_index: 0
		total_chunks: 5
		filename: 'large_file.dat'
		file_size: 5 * 1024 * 1024
		chunk_size: 1024 * 1024
		upload_time: 1234567890
	}
	
	assert info.file_hash == 'abc123'
	assert info.chunk_index == 0
	assert info.total_chunks == 5
	assert info.filename == 'large_file.dat'
	assert info.file_size == 5 * 1024 * 1024
	assert info.chunk_size == 1024 * 1024
	assert info.upload_time == 1234567890
}

// 测试：文件上传状态
fn test_file_upload_status() {
	mut status := hono_upload.FileUploadStatus{
		file_hash: 'hash789'
		filename: 'video.mp4'
		total_chunks: 10
		file_size: 10 * 1024 * 1024
		chunk_size: 1024 * 1024
		created_at: 1234567890
		uploaded_chunks: []
		status: 'uploading'
		updated_at: 1234567890
	}
	
	assert status.file_hash == 'hash789'
	assert status.filename == 'video.mp4'
	assert status.total_chunks == 10
	assert status.file_size == 10 * 1024 * 1024
	assert status.chunk_size == 1024 * 1024
	assert status.created_at == 1234567890
	assert status.uploaded_chunks.len == 0
	assert status.status == 'uploading'
	
	// 添加已上传分片
	status.uploaded_chunks << 0
	status.uploaded_chunks << 1
	status.uploaded_chunks << 2
	
	assert status.uploaded_chunks.len == 3
	assert 0 in status.uploaded_chunks
	assert 1 in status.uploaded_chunks
	assert 2 in status.uploaded_chunks
}

// 测试：计算上传进度
fn test_upload_progress() {
	mut status := hono_upload.FileUploadStatus{
		file_hash: 'progress_test'
		filename: 'file.bin'
		total_chunks: 10
		file_size: 10 * 1024 * 1024
		chunk_size: 1024 * 1024
		created_at: 1234567890
		uploaded_chunks: [0, 1, 2, 3, 4]
		status: 'uploading'
		updated_at: 1234567890
	}
	
	// 已上传 5/10 分片
	progress := (status.uploaded_chunks.len * 100) / status.total_chunks
	assert progress == 50
	
	// 添加更多分片
	status.uploaded_chunks << 5
	status.uploaded_chunks << 6
	status.uploaded_chunks << 7
	
	// 已上传 8/10 分片
	progress2 := (status.uploaded_chunks.len * 100) / status.total_chunks
	assert progress2 == 80
}

// 测试：检查上传完成
fn test_check_upload_complete() {
	mut status := hono_upload.FileUploadStatus{
		file_hash: 'complete_test'
		filename: 'complete.dat'
		total_chunks: 5
		file_size: 5 * 1024 * 1024
		chunk_size: 1024 * 1024
		created_at: 1234567890
		uploaded_chunks: []
		status: 'uploading'
		updated_at: 1234567890
	}
	
	// 未完成
	is_complete := status.uploaded_chunks.len == status.total_chunks
	assert is_complete == false
	
	// 逐步上传所有分片
	for i in 0 .. status.total_chunks {
		status.uploaded_chunks << i
	}
	
	// 完成
	is_complete2 := status.uploaded_chunks.len == status.total_chunks
	assert is_complete2 == true
}

// 测试：检测缺失的分片
fn test_find_missing_chunks() {
	status := hono_upload.FileUploadStatus{
		file_hash: 'missing_test'
		filename: 'file.bin'
		total_chunks: 10
		file_size: 10 * 1024 * 1024
		chunk_size: 1024 * 1024
		created_at: 1234567890
		uploaded_chunks: [0, 1, 3, 5, 7, 9]  // 缺少 2, 4, 6, 8
		status: 'uploading'
		updated_at: 1234567890
	}
	
	// 查找缺失的分片
	mut missing := []int{}
	for i in 0 .. status.total_chunks {
		if i !in status.uploaded_chunks {
			missing << i
		}
	}
	
	assert missing.len == 4
	assert 2 in missing
	assert 4 in missing
	assert 6 in missing
	assert 8 in missing
}

// 测试：验证分片索引范围
fn test_validate_chunk_index() {
	total_chunks := 10
	
	// 有效的分片索引
	valid_indices := [0, 1, 5, 9]
	for index in valid_indices {
		assert index >= 0 && index < total_chunks
	}
	
	// 无效的分片索引
	invalid_indices := [-1, 10, 100]
	for index in invalid_indices {
		assert !(index >= 0 && index < total_chunks)
	}
}

// 测试：计算预期的分片大小
fn test_calculate_expected_chunk_size() {
	file_size := 10 * 1024 * 1024  // 10MB
	chunk_size := 3 * 1024 * 1024  // 3MB
	
	// 总共需要 4 个分片（3MB + 3MB + 3MB + 1MB）
	expected_total_chunks := (file_size + chunk_size - 1) / chunk_size
	assert expected_total_chunks == 4
	
	// 最后一个分片的大小
	mut last_chunk_size := file_size % chunk_size
	if last_chunk_size == 0 {
		last_chunk_size = chunk_size
	}
	assert last_chunk_size == 1 * 1024 * 1024  // 1MB
}

// 测试：分片上传时间顺序
fn test_chunk_upload_order() {
	mut chunks := []hono_upload.ChunkInfo{}
	
	// 模拟乱序上传
	chunks << hono_upload.ChunkInfo{
		file_hash: 'order_test'
		chunk_index: 2
		total_chunks: 5
		filename: 'file.dat'
		file_size: 5 * 1024 * 1024
		chunk_size: 1024 * 1024
		upload_time: 1000
	}
	
	chunks << hono_upload.ChunkInfo{
		file_hash: 'order_test'
		chunk_index: 0
		total_chunks: 5
		filename: 'file.dat'
		file_size: 5 * 1024 * 1024
		chunk_size: 1024 * 1024
		upload_time: 2000
	}
	
	chunks << hono_upload.ChunkInfo{
		file_hash: 'order_test'
		chunk_index: 1
		total_chunks: 5
		filename: 'file.dat'
		file_size: 5 * 1024 * 1024
		chunk_size: 1024 * 1024
		upload_time: 1500
	}
	
	// 按 chunk_index 排序
	chunks.sort(a.chunk_index < b.chunk_index)
	
	assert chunks[0].chunk_index == 0
	assert chunks[1].chunk_index == 1
	assert chunks[2].chunk_index == 2
}

// 测试：默认配置值
fn test_default_chunk_upload_config() {
	config := hono_upload.ChunkUploadConfig{}
	
	// 验证默认值
	assert config.chunk_size == 1024 * 1024  // 1MB
	assert config.max_file_size == 1024 * 1024 * 1024  // 1GB
	assert config.max_chunk_size == 10 * 1024 * 1024  // 10MB
	assert config.temp_dir == './uploads/chunks'
	assert config.cleanup_delay == 3600
	assert config.clear_chunks_on_complete == false
	assert config.merge_buffer_size == 8192
}

// 测试：生成文件哈希
fn test_generate_file_hash() {
	hash1 := hono_upload.generate_file_hash('Hello, World!')
	hash2 := hono_upload.generate_file_hash('Hello, World!')
	hash3 := hono_upload.generate_file_hash('Different content')
	
	// 相同内容应该产生相同哈希
	assert hash1 == hash2
	// 不同内容应该产生不同哈希
	assert hash1 != hash3
	// MD5 哈希应该是 32 个字符
	assert hash1.len == 32
}
