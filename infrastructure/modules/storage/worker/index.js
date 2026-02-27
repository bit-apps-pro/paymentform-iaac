/**
 * Cloudflare Worker for serving files from R2 bucket
 * 
 * Routes:
 * - GET /{tenant}/{path} - Serve file from R2
 * - GET /{tenant}/{path} - CORS preflight handling
 * 
 * Environment bindings:
 * - R2_BUCKET: R2 bucket binding
 * - ENVIRONMENT: Environment name (dev, sandbox, prod)
 * - CORS_ORIGINS: Comma-separated list of allowed origins
 */

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    const path = url.pathname.slice(1); // Remove leading /

    // Handle CORS preflight requests
    if (request.method === 'OPTIONS') {
      return handleCorsPreflight(request, env);
    }

    // Only allow GET and HEAD requests for public file serving
    if (request.method !== 'GET' && request.method !== 'HEAD') {
      return new Response('Method not allowed', { 
        status: 405,
        headers: getCorsHeaders(request, env)
      });
    }

    // Validate path - must have at least tenant/file structure
    if (!path || path.split('/').length < 2) {
      return new Response('Not found', { 
        status: 404,
        headers: getCorsHeaders(request, env)
      });
    }

    try {
      // Fetch object from R2 bucket
      const object = await env.R2_BUCKET.get(path);

      if (!object) {
        return new Response('File not found', { 
          status: 404,
          headers: getCorsHeaders(request, env)
        });
      }

      // Build response headers
      const headers = new Headers({
        ...getCorsHeaders(request, env),
        'Content-Type': object.httpMetadata?.contentType || getContentType(path),
        'Cache-Control': 'public, max-age=31536000, immutable',
        'ETag': object.httpEtag,
        'Last-Modified': object.uploaded.toUTCString(),
      });

      // Add content length if available
      if (object.size) {
        headers.set('Content-Length', object.size.toString());
      }

      // Handle range requests for large files
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
  },
};

/**
 * Handle CORS preflight requests
 */
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

/**
 * Get CORS headers based on configuration
 */
function getCorsHeaders(request, env) {
  const origin = request.headers.get('Origin');
  const allowedOrigins = env.CORS_ORIGINS ? env.CORS_ORIGINS.split(',') : ['*'];
  
  const headers = {
    'Access-Control-Allow-Origin': allowedOrigins.includes('*') ? '*' : (allowedOrigins.includes(origin) ? origin : 'null'),
  };

  return headers;
}

/**
 * Get content type based on file extension
 */
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

/**
 * Handle HTTP range requests for large files
 */
async function handleRangeRequest(request, object, headers) {
  const range = request.headers.get('Range');
  const size = object.size;

  if (!range || !size) {
    return new Response(object.body, { status: 200, headers });
  }

  // Parse range header (e.g., "bytes=0-499")
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

  // Get the ranged data from R2
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
