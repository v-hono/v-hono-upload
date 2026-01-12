module main

import hono_upload
import os

// 测试：生成文件 UUID
fn test_generate_file_uuid() {
	uuid1 := hono_upload.generate_file_uuid()
	uuid2 := hono_upload.generate_file_uuid()
	
	// UUID 应该不为空
	assert uuid1 != ''
	assert uuid2 != ''
	
	// UUID 应该不同
	assert uuid1 != uuid2
	
	// UUID 应该有正确的格式（带连字符）
	assert uuid1.count('-') == 4
	assert uuid2.count('-') == 4
	
	// UUID 长度应该正确（32个十六进制字符 + 4个连字符）
	assert uuid1.len == 36
	assert uuid2.len == 36
}

// 测试：创建数据库管理器
fn test_create_database_manager() {
	db_path := './test_files.db'
	
	// 清理旧的测试数据库
	os.rm(db_path) or {}
	
	// 创建数据库管理器
	mut db := hono_upload.new_database_manager(db_path) or {
		assert false, 'Failed to create database manager: ${err}'
		return
	}
	
	// 验证数据库文件已创建
	assert os.exists(db_path)
	
	// 清理
	os.rm(db_path) or {}
}

// 测试：插入文件信息
fn test_insert_file_info() {
	db_path := './test_insert_files.db'
	os.rm(db_path) or {}
	
	mut db := hono_upload.new_database_manager(db_path) or {
		assert false, 'Failed to create database: ${err}'
		return
	}
	
	// 插入文件信息
	file_info := db.insert_or_update_file('hash123', 'test.txt', 1024, 'text/plain') or {
		assert false, 'Failed to insert file: ${err}'
		return
	}
	
	// 验证文件信息
	assert file_info.file_uuid != ''
	assert file_info.file_hash == 'hash123'
	assert file_info.file_name == 'test.txt'
	assert file_info.file_size == 1024
	assert file_info.file_type == 'text/plain'
	assert file_info.created_at > 0
	assert file_info.updated_at > 0
	
	// 清理
	os.rm(db_path) or {}
}

// 测试：通过哈希获取文件
fn test_get_file_by_hash() {
	db_path := './test_get_by_hash.db'
	os.rm(db_path) or {}
	
	mut db := hono_upload.new_database_manager(db_path) or {
		assert false, 'Failed to create database: ${err}'
		return
	}
	
	// 插入文件
	inserted := db.insert_or_update_file('hash456', 'document.pdf', 2048, 'application/pdf') or {
		assert false, 'Failed to insert file: ${err}'
		return
	}
	
	// 通过哈希获取文件
	retrieved := db.get_file_by_hash('hash456') or {
		assert false, 'Failed to get file by hash: ${err}'
		return
	}
	
	// 验证信息匹配
	assert retrieved.file_uuid == inserted.file_uuid
	assert retrieved.file_hash == 'hash456'
	assert retrieved.file_name == 'document.pdf'
	assert retrieved.file_size == 2048
	assert retrieved.file_type == 'application/pdf'
	
	// 清理
	os.rm(db_path) or {}
}

// 测试：通过 UUID 获取文件
fn test_get_file_by_uuid() {
	db_path := './test_get_by_uuid.db'
	os.rm(db_path) or {}
	
	mut db := hono_upload.new_database_manager(db_path) or {
		assert false, 'Failed to create database: ${err}'
		return
	}
	
	// 插入文件
	inserted := db.insert_or_update_file('hash789', 'image.png', 4096, 'image/png') or {
		assert false, 'Failed to insert file: ${err}'
		return
	}
	
	// 通过 UUID 获取文件
	retrieved := db.get_file_by_uuid(inserted.file_uuid) or {
		assert false, 'Failed to get file by uuid: ${err}'
		return
	}
	
	// 验证信息匹配
	assert retrieved.file_uuid == inserted.file_uuid
	assert retrieved.file_hash == 'hash789'
	assert retrieved.file_name == 'image.png'
	assert retrieved.file_size == 4096
	assert retrieved.file_type == 'image/png'
	
	// 清理
	os.rm(db_path) or {}
}

// 测试：相同哈希不同文件名
fn test_same_hash_different_filename() {
	db_path := './test_same_hash.db'
	os.rm(db_path) or {}
	
	mut db := hono_upload.new_database_manager(db_path) or {
		assert false, 'Failed to create database: ${err}'
		return
	}
	
	// 插入相同哈希的文件，但文件名不同
	file1 := db.insert_or_update_file('hash_same', 'file1.txt', 1024, 'text/plain') or {
		assert false, 'Failed to insert file1: ${err}'
		return
	}
	
	file2 := db.insert_or_update_file('hash_same', 'file2.txt', 1024, 'text/plain') or {
		assert false, 'Failed to insert file2: ${err}'
		return
	}
	
	// UUID 应该不同
	assert file1.file_uuid != file2.file_uuid
	
	// 文件哈希相同
	assert file1.file_hash == file2.file_hash
	
	// 文件名不同
	assert file1.file_name == 'file1.txt'
	assert file2.file_name == 'file2.txt'
	
	// 清理
	os.rm(db_path) or {}
}

// 测试：相同哈希和文件名（更新）
fn test_same_hash_same_filename() {
	db_path := './test_same_hash_name.db'
	os.rm(db_path) or {}
	
	mut db := hono_upload.new_database_manager(db_path) or {
		assert false, 'Failed to create database: ${err}'
		return
	}
	
	// 第一次插入
	file1 := db.insert_or_update_file('hash_update', 'file.txt', 1024, 'text/plain') or {
		assert false, 'Failed to insert file1: ${err}'
		return
	}
	
	// 再次插入相同哈希和文件名（应该更新）
	file2 := db.insert_or_update_file('hash_update', 'file.txt', 1024, 'text/plain') or {
		assert false, 'Failed to insert file2: ${err}'
		return
	}
	
	// UUID 应该相同（更新而不是新建）
	assert file1.file_uuid == file2.file_uuid
	
	// 更新时间应该被更新
	assert file2.updated_at >= file1.updated_at
	
	// 清理
	os.rm(db_path) or {}
}

// 测试：获取不存在的文件
fn test_get_nonexistent_file() {
	db_path := './test_nonexistent.db'
	os.rm(db_path) or {}
	
	mut db := hono_upload.new_database_manager(db_path) or {
		assert false, 'Failed to create database: ${err}'
		return
	}
	
	// 尝试获取不存在的文件（by hash）
	_ := db.get_file_by_hash('nonexistent_hash') or {
		// 应该失败
		assert err.msg().len > 0
		
		// 清理
		os.rm(db_path) or {}
		return
	}
	
	assert false, 'Should not find nonexistent file'
}
