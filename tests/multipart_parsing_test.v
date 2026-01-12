module main

import hono_upload
// 测试：提取 boundary
fn test_extract_boundary() {
	// 标准格式
	content_type1 := 'multipart/form-data; boundary=----WebKitFormBoundary7MA4YWxkTrZu0gW'
	parser1 := hono_upload.new_multipart_parser(content_type1, '') or {
		assert false, 'Should not fail: ${err}'
		return
	}
	assert parser1.boundary == '----WebKitFormBoundary7MA4YWxkTrZu0gW'
	
	// 带引号的 boundary
	content_type2 := 'multipart/form-data; boundary="----WebKitFormBoundary7MA4YWxkTrZu0gW"'
	parser2 := hono_upload.new_multipart_parser(content_type2, '') or {
		assert false, 'Should not fail: ${err}'
		return
	}
	assert parser2.boundary == '----WebKitFormBoundary7MA4YWxkTrZu0gW'
	
	// 无效的 Content-Type
	content_type3 := 'application/json'
	_ := hono_upload.new_multipart_parser(content_type3, '') or {
		assert err.msg().contains('boundary')
		return
	}
	assert false, 'Should fail for non-multipart content type'
}

// 测试：解析简单的 multipart 数据
fn test_parse_simple_multipart() {
	boundary := '----WebKitFormBoundary7MA4YWxkTrZu0gW'
	content_type := 'multipart/form-data; boundary=${boundary}'
	
	// 构建简单的 multipart 数据
	data := '------WebKitFormBoundary7MA4YWxkTrZu0gW\r\n' +
		'Content-Disposition: form-data; name="field1"\r\n\r\n' +
		'value1\r\n' +
		'------WebKitFormBoundary7MA4YWxkTrZu0gW\r\n' +
		'Content-Disposition: form-data; name="field2"\r\n\r\n' +
		'value2\r\n' +
		'------WebKitFormBoundary7MA4YWxkTrZu0gW--\r\n'
	
	parser := hono_upload.new_multipart_parser(content_type, data) or {
		assert false, 'Failed to create parser: ${err}'
		return
	}
	
	items := parser.parse() or {
		assert false, 'Failed to parse: ${err}'
		return
	}
	
	assert items.len == 2
	assert items[0].name == 'field1'
	assert items[0].content.trim_space() == 'value1'
	assert items[1].name == 'field2'
	assert items[1].content.trim_space() == 'value2'
}

// 测试：解析带文件的 multipart 数据
fn test_parse_multipart_with_file() {
	boundary := '----WebKitFormBoundary7MA4YWxkTrZu0gW'
	content_type := 'multipart/form-data; boundary=${boundary}'
	
	// 构建包含文件的 multipart 数据
	data := '------WebKitFormBoundary7MA4YWxkTrZu0gW\r\n' +
		'Content-Disposition: form-data; name="file"; filename="test.txt"\r\n' +
		'Content-Type: text/plain\r\n\r\n' +
		'Hello, World!\r\n' +
		'------WebKitFormBoundary7MA4YWxkTrZu0gW--\r\n'
	
	parser := hono_upload.new_multipart_parser(content_type, data) or {
		assert false, 'Failed to create parser: ${err}'
		return
	}
	
	items := parser.parse() or {
		assert false, 'Failed to parse: ${err}'
		return
	}
	
	assert items.len == 1
	assert items[0].name == 'file'
	assert items[0].filename == 'test.txt'
	assert items[0].content_type == 'text/plain'
	assert items[0].content.trim_space() == 'Hello, World!'
}

// 测试：解析空 multipart 数据
fn test_parse_empty_multipart() {
	boundary := '----WebKitFormBoundary7MA4YWxkTrZu0gW'
	content_type := 'multipart/form-data; boundary=${boundary}'
	
	data := '------WebKitFormBoundary7MA4YWxkTrZu0gW--\r\n'
	
	parser := hono_upload.new_multipart_parser(content_type, data) or {
		assert false, 'Failed to create parser: ${err}'
		return
	}
	
	items := parser.parse() or {
		assert false, 'Failed to parse: ${err}'
		return
	}
	
	assert items.len == 0
}

// 测试：解析多个文件的 multipart 数据
fn test_parse_multipart_with_multiple_files() {
	boundary := '----WebKitFormBoundary7MA4YWxkTrZu0gW'
	content_type := 'multipart/form-data; boundary=${boundary}'
	
	data := '------WebKitFormBoundary7MA4YWxkTrZu0gW\r\n' +
		'Content-Disposition: form-data; name="file1"; filename="test1.txt"\r\n' +
		'Content-Type: text/plain\r\n\r\n' +
		'Content of file 1\r\n' +
		'------WebKitFormBoundary7MA4YWxkTrZu0gW\r\n' +
		'Content-Disposition: form-data; name="file2"; filename="test2.txt"\r\n' +
		'Content-Type: text/plain\r\n\r\n' +
		'Content of file 2\r\n' +
		'------WebKitFormBoundary7MA4YWxkTrZu0gW--\r\n'
	
	parser := hono_upload.new_multipart_parser(content_type, data) or {
		assert false, 'Failed to create parser: ${err}'
		return
	}
	
	items := parser.parse() or {
		assert false, 'Failed to parse: ${err}'
		return
	}
	
	assert items.len == 2
	assert items[0].name == 'file1'
	assert items[0].filename == 'test1.txt'
	assert items[0].content.trim_space() == 'Content of file 1'
	assert items[1].name == 'file2'
	assert items[1].filename == 'test2.txt'
	assert items[1].content.trim_space() == 'Content of file 2'
}

// 测试：解析混合字段和文件的 multipart 数据
fn test_parse_multipart_mixed_fields_and_files() {
	boundary := '----WebKitFormBoundary7MA4YWxkTrZu0gW'
	content_type := 'multipart/form-data; boundary=${boundary}'
	
	data := '------WebKitFormBoundary7MA4YWxkTrZu0gW\r\n' +
		'Content-Disposition: form-data; name="username"\r\n\r\n' +
		'testuser\r\n' +
		'------WebKitFormBoundary7MA4YWxkTrZu0gW\r\n' +
		'Content-Disposition: form-data; name="avatar"; filename="avatar.png"\r\n' +
		'Content-Type: image/png\r\n\r\n' +
		'<binary data>\r\n' +
		'------WebKitFormBoundary7MA4YWxkTrZu0gW\r\n' +
		'Content-Disposition: form-data; name="email"\r\n\r\n' +
		'user@example.com\r\n' +
		'------WebKitFormBoundary7MA4YWxkTrZu0gW--\r\n'
	
	parser := hono_upload.new_multipart_parser(content_type, data) or {
		assert false, 'Failed to create parser: ${err}'
		return
	}
	
	items := parser.parse() or {
		assert false, 'Failed to parse: ${err}'
		return
	}
	
	assert items.len == 3
	assert items[0].name == 'username'
	assert items[0].filename == ''
	assert items[0].content.trim_space() == 'testuser'
	
	assert items[1].name == 'avatar'
	assert items[1].filename == 'avatar.png'
	assert items[1].content_type == 'image/png'
	
	assert items[2].name == 'email'
	assert items[2].filename == ''
	assert items[2].content.trim_space() == 'user@example.com'
}
