<?php
// Reset the homepage-name example.
//
// Restores the baseline site name and removes the web-root impact file.
// The Rickroll example uses a separate page HTML field, so resetting one
// effect does not cancel the other.
//
//   cp labs/examples/reset-homepage.php loot/reset-homepage.php
//   printf 'php /loot/reset-homepage.php\n' > loot/c
//   ... -c 'sh</loot/c'

$src = @file_get_contents('/var/www/config/config.php');
if ($src === false) {
    fwrite(STDERR, "cannot read /var/www/config/config.php\n");
    exit(1);
}
$cfg = [];
foreach (['dbhost', 'dbname', 'dbuser', 'dbpass'] as $key) {
    if (preg_match('/\$CFG->' . $key . '\s*=\s*\'([^\']*)\'/', $src, $m)) {
        $cfg[$key] = $m[1];
    }
}

try {
    $pdo = new PDO(
        "mysql:host={$cfg['dbhost']};dbname={$cfg['dbname']};charset=utf8mb4",
        $cfg['dbuser'],
        $cfg['dbpass'],
        [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]
    );

    $pdo->exec("UPDATE mdl_course SET fullname='NCKU Moodle', shortname='NCKU Moodle' WHERE id=1");
    $row = $pdo->query('SELECT fullname, shortname FROM mdl_course WHERE id = 1')->fetch(PDO::FETCH_ASSOC);

    @unlink('/var/www/html/impact.txt');
    passthru('php -d memory_limit=256M /var/www/html/admin/cli/purge_caches.php >/dev/null 2>&1');

    $fileleft = file_exists('/var/www/html/impact.txt');
    $ok = $row
        && $row['fullname'] === 'NCKU Moodle'
        && $row['shortname'] === 'NCKU Moodle'
        && !$fileleft;

    if (!$ok) {
        $failed = sprintf(
            'homepage-reset=failed fullname=%s shortname=%s impact=%s',
            $row['fullname'] ?? 'missing',
            $row['shortname'] ?? 'missing',
            $fileleft ? 'present' : 'absent'
        );
        fwrite(STDERR, $failed . "\n");
        file_put_contents('/loot/p1', $failed . "\n");
        exit(1);
    }

    $proof = "homepage-reset=ok fullname=NCKU Moodle shortname=NCKU Moodle impact=absent db=verified\n";
    file_put_contents('/loot/p1', $proof);
    echo $proof;
} catch (Throwable $e) {
    $failed = 'homepage-reset=failed reason=' . preg_replace('/\s+/', ' ', $e->getMessage());
    fwrite(STDERR, $failed . "\n");
    file_put_contents('/loot/p1', $failed . "\n");
    exit(1);
}
