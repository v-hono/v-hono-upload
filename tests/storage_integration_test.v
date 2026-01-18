module main

import hono_upload
import v_hono_storage
import os

// 测试目录
const test_temp_dir = './test_upload_chunks'
const test_storage_dir = './test_storage'
const test_db_path = './test_upload.db'

// 清理测试目录
fn cleanup_test_dirs() {
	os.rmdir_all(test_temp_dir) or {}
	os.rmdir_all(test_storage_dir) or {}
	os.rm(test_db_path) or {}
}

// 测试：创建带本地存储的 ChunkUploadManager
fn test_create_chunk_upload_manager() {
	cleanup_test_dirs()
	defer { cleanup_test_dirs() }
	
	config := hono_upload.ChunkUploadConfig{
		chunk_size: 1024 * 1024
		max_file_size: 100 * 1024 * 1024
		temp_dir: test_temp_dir
		clear_chunks_on_complete: true
	}
	
	mut manager := hono_upload.new_chunk_upload_manager(config, test_storage_dir, test_db_path) or {
		assert false, 'Failed to create manager: ${err}'
		return
	}
	defer { manager.close() }
	
	// 验证临时目录已创建
	assert os.exists(test_temp_dir)
}

// 测试：创建带现有 FileService 的 ChunkUploadManager
fn test_create_chunk_upload_manager_with_storage() {
	cleanup_test_dirs()
	defer { cleanup_test_dirs() }
	
	// 先创建 FileService
	mut file_service := v_hono_storage.new_local_file_service(test_storage_dir, test_db_path) or {
		assert false, 'Failed to create file service: ${err}'
		return
	}
	
	config := hono_upload.ChunkUploadConfig{
		chunk_size: 1024 * 1024
		temp_dir: test_temp_dir
	}
	
	mut manager := hono_upload.new_chunk_upload_manager_with_storage(config, mut file_service)
	
	// 验证临时目录已创建
	assert os.exists(test_temp_dir)
	
	// 注意：使用 with_storage 时，FileService 的生命周期由调用者管理
	file_service.close()
}

// 测试：更新上传状态
fn test_update_upload_status() {
	cleanup_test_dirs()
	defer { cleanup_test_dirs() }
	
	config := hono_upload.ChunkUploadConfig{
		temp_dir: test_temp_dir
	}
	
	mut manager := hono_upload.new_chunk_upload_manager(config, test_storage_dir, test_db_path) or {
		assert false, 'Failed to create manager: ${err}'
		return
	}
	defer { manager.close() }
	
	file_hash := 'a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4'
	
	// 更新状态
	manager.update_upload_status(file_hash, 'test.txt', 0, 1024 * 1024, 256 * 1024)
	manager.update_upload_status(file_hash, 'test.txt', 1, 1024 * 1024, 256 * 1024)
	manager.update_upload_status(file_hash, 'test.txt', 2, 1024 * 1024, 256 * 1024)
	
	// 验证状态
	status := manager.uploads[file_hash] or {
		assert false, 'Status not found'
		return
	}
	
	assert status.file_hash == file_hash
	assert status.filename == 'test.txt'
	assert status.uploaded_chunks.len == 3
	assert 0 in status.uploaded_chunks
	assert 1 in status.uploaded_chunks
	assert 2 in status.uploaded_chunks
	assert status.status == 'uploading'
}

// 测试：分片大小记录
fn test_chunk_size_record() {
	cleanup_test_dirs()
	defer { cleanup_test_dirs() }
	
	config := hono_upload.ChunkUploadConfig{
		temp_dir: test_temp_dir
	}
	
	mut manager := hono_upload.new_chunk_upload_manager(config, test_storage_dir, test_db_path) or {
		assert false, 'Failed to create manager: ${err}'
		return
	}
	defer { manager.close() }
	
	file_hash := 'b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5'
	chunk_size := 256 * 1024
	
	// 更新分片大小记录
	manager.update_chunk_size_record(file_hash, chunk_size, 100 * 1024)
	manager.update_chunk_size_record(file_hash, chunk_size, 100 * 1024)
	manager.update_chunk_size_record(file_hash, chunk_size, 56 * 1024)
	
	// 获取记录
	total := manager.get_chunk_size_record(file_hash, chunk_size)
	assert total == u64(256 * 1024)
	
	// 清理记录
	manager.cleanup_chunk_size_record(file_hash, chunk_size)
	total2 := manager.get_chunk_size_record(file_hash, chunk_size)
	assert total2 == u64(0)
}

// 测试：清理上传状态
fn test_cleanup_upload_status() {
	cleanup_test_dirs()
	defer { cleanup_test_dirs() }
	
	config := hono_upload.ChunkUploadConfig{
		temp_dir: test_temp_dir
	}
	
	mut manager := hono_upload.new_chunk_upload_manager(config, test_storage_dir, test_db_path) or {
		assert false, 'Failed to create manager: ${err}'
		return
	}
	defer { manager.close() }
	
	file_hash := 'c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6'
	
	// 添加状态
	manager.update_upload_status(file_hash, 'test.txt', 0, 1024, 512)
	assert file_hash in manager.uploads
	
	// 清理状态
	manager.cleanup_upload_status(file_hash)
	assert file_hash !in manager.uploads
}

// 测试：验证文件完整性
fn test_verify_file_integrity() {
	cleanup_test_dirs()
	defer { cleanup_test_dirs() }
	
	// 创建测试文件
	os.mkdir_all(test_temp_dir) or {}
	test_file := os.join_path(test_temp_dir, 'integrity_test.txt')
	test_content := 'Hello, World!'
	os.write_file(test_file, test_content) or {
		assert false, 'Failed to write test file'
		return
	}
	
	// 计算预期哈希
	expected_hash := hono_upload.generate_file_hash(test_content)
	
	// 验证完整性
	assert hono_upload.verify_file_integrity(test_file, expected_hash) == true
	assert hono_upload.verify_file_integrity(test_file, 'wrong_hash') == false
}

// 测试：完整的分片上传流程（模拟）
fn test_full_chunk_upload_flow() {
	cleanup_test_dirs()
	defer { cleanup_test_dirs() }
	
	config := hono_upload.ChunkUploadConfig{
		chunk_size: 100  // 小分片便于测试
		temp_dir: test_temp_dir
		clear_chunks_on_complete: true
	}
	
	mut manager := hono_upload.new_chunk_upload_manager(config, test_storage_dir, test_db_path) or {
		assert false, 'Failed to create manager: ${err}'
		return
	}
	defer { manager.close() }
	
	// 模拟文件数据
	file_content := 'This is a test file content for chunked upload testing.'
	file_hash := hono_upload.generate_file_hash(file_content)
	filename := 'test_upload.txt'
	file_size := file_content.len
	chunk_size := 20
	
	// 计算分片数量
	total_chunks := (file_size + chunk_size - 1) / chunk_size
	
	// 创建分片目录
	chunk_dir := os.join_path(test_temp_dir, file_hash, chunk_size.str())
	os.mkdir_all(chunk_dir) or {
		assert false, 'Failed to create chunk dir'
		return
	}
	
	// 模拟分片上传
	for i in 0 .. total_chunks {
		start := i * chunk_size
		end := if (i + 1) * chunk_size > file_size { file_size } else { (i + 1) * chunk_size }
		chunk_data := file_content[start..end]
		
		// 保存分片
		chunk_path := os.join_path(chunk_dir, 'chunk_${i}.part')
		os.write_file(chunk_path, chunk_data) or {
			assert false, 'Failed to write chunk ${i}'
			return
		}
		
		// 更新状态
		manager.update_upload_status(file_hash, filename, i, file_size, chunk_size)
		manager.update_chunk_size_record(file_hash, chunk_size, chunk_data.len)
	}
	
	// 验证所有分片已上传
	status := manager.uploads[file_hash] or {
		assert false, 'Status not found'
		return
	}
	
	assert status.uploaded_chunks.len == total_chunks
	
	// 验证分片大小记录
	total_recorded := manager.get_chunk_size_record(file_hash, chunk_size)
	assert total_recorded >= u64(file_size)
}
