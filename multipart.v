module hono_upload

// Multipart 表单数据项
pub struct MultipartItem {
pub:
	name     string
	filename string
	content  string
	content_type string
}

// Multipart 解析器
pub struct MultipartParser {
pub:
	boundary string
	data     string
}

// 创建 Multipart 解析器
pub fn new_multipart_parser(content_type string, data string) !MultipartParser {
	// 从 Content-Type 中提取 boundary
	boundary := extract_boundary(content_type) or {
		return error('Failed to extract boundary')
	}
	
	return MultipartParser{
		boundary: boundary
		data: data
	}
}

// 解析 multipart 数据
pub fn (parser MultipartParser) parse() ![]MultipartItem {
	mut items := []MultipartItem{}
	// 更健壮的分割方式，兼容不同换行
	parts := parser.data.split('--${parser.boundary}')
	for _, part in parts {
		if part.trim_space() == '' || part.trim_space() == '--' || part.trim_space().starts_with('--') {
			continue
		}
		item := parser.parse_part(part) or { 
			continue 
		}
		items << item
	}
	return items
}

// 解析单个部分
fn (parser MultipartParser) parse_part(part string) !MultipartItem {
	// 分离头部和内容
	header_content := part.split('\r\n\r\n')
	if header_content.len < 2 {
		return error('Invalid part format')
	}
	
	header := header_content[0]
	content := header_content[1..].join('\r\n\r\n')
	
	// 解析头部
	name := extract_header_value(header, 'name') or {
		return error('Missing name')
	}
	filename := extract_header_value(header, 'filename') or { '' }
	
	// Content-Type 可能是单独的头部行
	mut content_type := 'text/plain'
	for line in header.split('\r\n') {
		if line.starts_with('Content-Type:') {
			content_type = line[13..].trim_space()
			break
		}
	}
	
	return MultipartItem{
		name: name
		filename: filename
		content: content
		content_type: content_type
	}
}

// 从 Content-Type 中提取 boundary
fn extract_boundary(content_type string) !string {
	if !content_type.starts_with('multipart/form-data') {
		return error('Not multipart/form-data')
	}
	
	boundary_start := content_type.index('boundary=') or {
		return error('No boundary found')
	}
	mut boundary := content_type[boundary_start + 9..]
	
	// 移除引号
	if boundary.starts_with('"') && boundary.ends_with('"') {
		boundary = boundary[1..boundary.len - 1]
	}
	
	return boundary
}

// 从头部中提取值
fn extract_header_value(header string, key string) !string {
    // 先找 Content-Disposition 行
    for line in header.split('\r\n') {
        if line.starts_with('Content-Disposition:') {
            // 查找 key="value"
            key_eq := '${key}="'
            idx := line.index(key_eq) or { continue }
            start := idx + key_eq.len
            end := line.index_after('"', start) or { line.len }
            return line[start..end]
        }
    }
    return error('Key not found: $key')
}
