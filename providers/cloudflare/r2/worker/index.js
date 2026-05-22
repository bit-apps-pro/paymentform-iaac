export default {
  async fetch(request, env) {
    return handleRequest(request, env);
  }
};

async function handleRequest(request, env) {
  const url = new URL(request.url);
  const path = url.pathname.slice(1);

  if (request.method === 'OPTIONS') {
    return handleCorsPreflight();
  }

  if (request.method !== 'GET' && request.method !== 'HEAD') {
    return new Response('Method not allowed', {
      status: 405,
      headers: getCorsHeaders(),
    });
  }

  if (!isPublicPath(path)) {
    return new Response('Not found', {
      status: 404,
      headers: getCorsHeaders(),
    });
  }

  try {
    const headObject = await env.R2_BUCKET.head(path);

    if (!headObject) {
      return new Response('File not found', {
        status: 404,
        headers: getCorsHeaders(),
      });
    }

    // Conditional request: serve 304 when the client already has current bytes.
    // Saves a full R2 read + response body on every browser revalidation against
    // the long max-age cache.
    const notModified = isNotModified(request, headObject);
    if (notModified) {
      return new Response(null, {
        status: 304,
        headers: buildResponseHeaders(headObject, path, { includeContentLength: false }),
      });
    }

    const rangeHeader = request.headers.get('Range');
    const rangeSpec = rangeHeader ? parseRange(rangeHeader, headObject.size) : null;

    if (rangeHeader && !rangeSpec) {
      return new Response('Range not satisfiable', {
        status: 416,
        headers: {
          ...getCorsHeaders(),
          'Content-Range': `bytes */${headObject.size}`,
        },
      });
    }

    const getOptions = rangeSpec
      ? { range: { offset: rangeSpec.start, length: rangeSpec.end - rangeSpec.start + 1 } }
      : undefined;
    const object = await env.R2_BUCKET.get(path, getOptions);

    if (!object) {
      return new Response('File not found', {
        status: 404,
        headers: getCorsHeaders(),
      });
    }

    const headers = buildResponseHeaders(object, path, { includeContentLength: true });

    if (rangeSpec) {
      headers.set('Content-Range', `bytes ${rangeSpec.start}-${rangeSpec.end}/${headObject.size}`);
      headers.set('Content-Length', String(rangeSpec.end - rangeSpec.start + 1));
      return new Response(object.body, { status: 206, headers });
    }

    return new Response(object.body, { status: 200, headers });
  } catch (error) {
    console.error('Error fetching from R2:', error);
    return new Response('Internal server error', {
      status: 500,
      headers: getCorsHeaders(),
    });
  }
}

function buildResponseHeaders(object, path, { includeContentLength }) {
  const headers = new Headers(getCorsHeaders());
  headers.set('Content-Type', object.httpMetadata?.contentType || getContentType(path));
  headers.set('Cache-Control', 'public, max-age=31536000, immutable');
  headers.set('ETag', object.httpEtag);
  headers.set('Last-Modified', object.uploaded.toUTCString());
  headers.set('Accept-Ranges', 'bytes');
  if (includeContentLength && object.size != null) {
    headers.set('Content-Length', String(object.size));
  }
  return headers;
}

function isNotModified(request, object) {
  const ifNoneMatch = request.headers.get('If-None-Match');
  if (ifNoneMatch) {
    const tags = ifNoneMatch.split(',').map(t => t.trim());
    if (tags.includes(object.httpEtag) || tags.includes('*')) {
      return true;
    }
  }

  const ifModifiedSince = request.headers.get('If-Modified-Since');
  if (ifModifiedSince) {
    const since = Date.parse(ifModifiedSince);
    if (!Number.isNaN(since) && object.uploaded.getTime() <= since) {
      return true;
    }
  }

  return false;
}

// Parse RFC 7233 `Range: bytes=...`. Returns null when unsatisfiable or
// malformed. Supports a single byte range plus the suffix form `bytes=-N`.
function parseRange(rangeHeader, size) {
  if (!size) return null;

  const match = rangeHeader.match(/^bytes=(\d*)-(\d*)$/);
  if (!match) return null;

  const startRaw = match[1];
  const endRaw = match[2];

  let start;
  let end;

  if (startRaw === '' && endRaw === '') {
    return null;
  }

  if (startRaw === '') {
    const suffixLength = parseInt(endRaw, 10);
    if (suffixLength <= 0) return null;
    start = Math.max(0, size - suffixLength);
    end = size - 1;
  } else {
    start = parseInt(startRaw, 10);
    end = endRaw === '' ? size - 1 : parseInt(endRaw, 10);
  }

  if (Number.isNaN(start) || Number.isNaN(end)) return null;
  if (start > end || start >= size) return null;

  return { start, end: Math.min(end, size - 1) };
}

function handleCorsPreflight() {
  return new Response(null, {
    status: 204,
    headers: {
      ...getCorsHeaders(),
      'Access-Control-Allow-Methods': 'GET, HEAD, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type, Authorization, Range, If-None-Match, If-Modified-Since',
      'Access-Control-Max-Age': '86400',
    },
  });
}

function isPublicPath(path) {
  const parts = path.split('/');
  return parts.length >= 4 && parts[1] === 'public';
}

function getCorsHeaders() {
  return {
    'Access-Control-Allow-Origin': '*',
  };
}

function getContentType(path) {
  const ext = path.split('.').pop()?.toLowerCase();
  const contentTypes = {
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'gif': 'image/gif',
    'svg': 'image/svg+xml',
    'webp': 'image/webp',
    'pdf': 'application/pdf',
    'txt': 'text/plain',
    'json': 'application/json',
    'js': 'application/javascript',
    'css': 'text/css',
    'html': 'text/html',
    'mp4': 'video/mp4',
    'webm': 'video/webm',
    'mp3': 'audio/mpeg',
    'wav': 'audio/wav',
    'zip': 'application/zip',
    'doc': 'application/msword',
    'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'xls': 'application/vnd.ms-excel',
    'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  };

  return contentTypes[ext] || 'application/octet-stream';
}
