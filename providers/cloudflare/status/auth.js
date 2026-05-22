/**
 * Validate a Bearer token against an env-stored secret.
 *
 * @param {Request} request  inbound request
 * @param {object}  env      worker env (must hold the named secret)
 * @param {string}  [secretName="ADMIN_TOKEN"]  name of the env property to match against
 * @returns {Response|null}  401 Response when validation fails, null when OK
 */
export async function requireBearer(request, env, secretName = "ADMIN_TOKEN") {
  const header = request.headers.get("Authorization") || "";
  const presented = header.startsWith("Bearer ") ? header.slice(7) : "";

  const expectedToken = env[secretName] || "";

  if (!expectedToken) {
    return new Response("Unauthorized", { status: 401 });
  }

  const encoder = new TextEncoder();
  const presentedBytes = encoder.encode(presented);
  const expectedBytes = encoder.encode(expectedToken);

  // Constant-time comparison: folded XOR accumulator
  let mismatch = presentedBytes.length !== expectedBytes.length ? 1 : 0;
  const maxLen = Math.max(presentedBytes.length, expectedBytes.length);

  for (let i = 0; i < maxLen; i++) {
    const a = presentedBytes[i] || 0;
    const b = expectedBytes[i] || 0;
    mismatch |= a ^ b;
  }

  if (mismatch !== 0) {
    return new Response("Unauthorized", { status: 401 });
  }

  return null;
}
