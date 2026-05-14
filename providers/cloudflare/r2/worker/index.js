export default {
  async fetch(request, env, ctx) {
    return handleRequest(request, env, ctx);
  }
};

async function handleRequest(request, env, ctx) {
  const url = new URL(request.url);
  const path = url.pathname.slice(1);

  if (request.method === 'OPTIONS') {
    return handleCorsPreflight(request, env);
  }

  if (request.method !== 'GET' && request.method !== 'HEAD') {
    return new Response('Method not allowed', {
      status: 405,
      headers: getCorsHeaders(request, env)
    });
  }

  if (!isPublicPath(path)) {
    return new Response('Not found', {
      status: 404,
      headers: getCorsHeaders(request, env)
    });
  }

  try {
    const object = await env.R2_BUCKET.get(path);

    if (!object) {
      return new Response('File not found', {
        status: 404,
        headers: getCorsHeaders(request, env)
      });
    }

    const headers = new Headers({
      ...getCorsHeaders(request, env),
      'Content-Type': object.httpMetadata?.contentType || getContentType(path),
      'Cache-Control': 'public, max-age=31536000, immutable',
      'ETag': object.httpEtag,
      'Last-Modified': object.uploaded.toUTCString(),
    });

    if (object.size) {
      headers.set('Content-Length', object.size.toString());
    }

    if (request.headers.has('Range')) {
      return await handleRangeRequest(request, object, headers);
    }

    return new Response(object.body, {
      status: 200,
      headers,
    });

  } catch (error) {
    console.error('Error fetching from R2:', error);
    return new Response('Internal server error', {
      status: 500,
      headers: getCorsHeaders(request, env)
    });
  }
}

function handleCorsPreflight(request, env) {
  const headers = getCorsHeaders(request, env);

  return new Response(null, {
    status: 204,
    headers: {
      ...headers,
      'Access-Control-Allow-Methods': 'GET, HEAD, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type, Authorization, Range',
      'Access-Control-Max-Age': '86400',
    },
  });
}

function isPublicPath(path) {
  const parts = path.split('/');
  return parts.length >= 4 && parts[1] === 'public';
}

function getCorsHeaders(request, env) {
  const headers = {
    'Access-Control-Allow-Origin': '*',
  };

  return headers;
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

async function handleRangeRequest(request, object, headers) {
  const range = request.headers.get('Range');
  const size = object.size;

  if (!range || !size) {
    return new Response(object.body, { status: 200, headers });
  }

  const matches = range.match(/bytes=(\d+)-(\d*)/);
  if (!matches) {
    return new Response('Invalid range', {
      status: 416,
      headers: { ...headers, 'Content-Range': `bytes */${size}` }
    });
  }

  const start = parseInt(matches[1], 10);
  const end = matches[2] ? parseInt(matches[2], 10) : size - 1;
  const clampedEnd = Math.min(end, size - 1);

  if (start >= size || start > clampedEnd) {
    return new Response('Range not satisfiable', {
      status: 416,
      headers: { ...headers, 'Content-Range': `bytes */${size}` }
    });
  }

  const rangedObject = await env.R2_BUCKET.get(object.key, {
    range: { offset: start, length: clampedEnd - start + 1 },
  });

  if (!rangedObject) {
    return new Response('Range not satisfiable', {
      status: 416,
      headers: { ...headers, 'Content-Range': `bytes */${size}` }
    });
  }

  headers.set('Content-Range', `bytes ${start}-${clampedEnd}/${size}`);
  headers.set('Content-Length', (clampedEnd - start + 1).toString());

  return new Response(rangedObject.body, {
    status: 206,
    headers,
  });
}
