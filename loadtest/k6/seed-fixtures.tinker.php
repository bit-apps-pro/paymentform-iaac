<?php
// Tinker snippet to seed N test users across M tenants and emit fixtures.json.
//
// Usage (from inside a backend container, or anywhere `php artisan tinker` works):
//   SEED_COUNT=20 SEED_TENANTS=5 \
//     API_BASE=https://api.dev.paymentform.io \
//     TENANT_API_TEMPLATE='https://%s.api.dev.paymentform.io' \
//     php artisan tinker --execute="$(cat iaac/loadtest/k6/seed-fixtures.tinker.php)"
//
// Writes fixtures to ./iaac/loadtest/k6/fixtures.json. Idempotent — re-running
// creates fresh tokens for the same accounts. Adapt User/Tenant fields to
// match your local models if your schema diverges from this template.
//
// SAFETY: only run against staging / dev. This creates real DB rows.

use App\Models\Tenant;
use App\Models\User;

$count    = (int) (getenv('SEED_COUNT') ?: 20);
$tenants  = max(2, (int) (getenv('SEED_TENANTS') ?: 5));
$apiBase  = rtrim(getenv('API_BASE') ?: 'http://localhost', '/');
$tenTpl   = getenv('TENANT_API_TEMPLATE') ?: 'http://%s.localhost';
$out      = getenv('OUT') ?: getcwd().'/iaac/loadtest/k6/fixtures.json';

$fixtures = [];

for ($i = 0; $i < $count; $i++) {
    $tenantSlug = sprintf('pollute-test-%03d', $i % $tenants);
    $email      = "pollute-test-{$i}@example.test";

    $tenant = Tenant::firstOrCreate(['id' => $tenantSlug]);

    $user = User::firstOrCreate(
        ['email' => $email],
        [
            'name'              => "Pollute Test #{$i}",
            'password'          => bcrypt('test-password-123'),
            'email_verified_at' => now(),
            'active_tenant'     => $tenantSlug,
        ]
    );

    // If active_tenant is column not in `fillable`, set explicitly:
    if (! $user->active_tenant) {
        $user->active_tenant = $tenantSlug;
        $user->save();
    }

    $token = $user->createToken('pollution-test-fixture')->plainTextToken;

    $fixtures[] = [
        'user_id'         => $user->uuid ?? (string) $user->id,
        'tenant_id'       => $tenantSlug,
        'token'           => $token,
        'api_base_url'    => $apiBase,
        'tenant_base_url' => sprintf($tenTpl, $tenantSlug),
    ];
}

file_put_contents($out, json_encode($fixtures, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES)."\n");
echo "Wrote ".count($fixtures)." fixtures to {$out}\n";
