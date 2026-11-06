<?php
// Reset the front-page image effect.
//
// Restores the top-of-page HTML saved by rickroll.php and removes the image
// from the web root. It does not touch the site name or additionalhtmlhead.
//
//   cp labs/examples/reset-rickroll.php loot/reset-rickroll.php
//   printf 'php /loot/reset-rickroll.php\n' > loot/c
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

    $saved = $pdo->query("SELECT value FROM mdl_config WHERE name='lab_rickroll_prev_top_saved'")->fetchColumn();
    if ($saved === false) {
        $current = $pdo->query("SELECT value FROM mdl_config WHERE name='additionalhtmltopofbody'")->fetchColumn();
        $fileleft = file_exists('/var/www/html/good-hacker.webp');
        $linkleft = is_string($current) && strpos($current, 'good-hacker.webp') !== false;
        if (!$fileleft && !$linkleft) {
            $proof = 'rickroll-reset=ok image=absent link=absent top=already-baseline db=verified' . "\n";
            file_put_contents('/loot/p1', $proof);
            echo $proof;
            exit(0);
        }
        throw new RuntimeException('no saved top-of-page HTML, but the image/link is still present');
    }
    $previous = $pdo->query("SELECT value FROM mdl_config WHERE name='lab_rickroll_prev_top'")->fetchColumn();
    $previous = $previous === false ? '' : (string) $previous;
    $stmt = $pdo->prepare(
        "INSERT INTO mdl_config (name, value) VALUES ('additionalhtmltopofbody', :v)
         ON DUPLICATE KEY UPDATE value = VALUES(value)"
    );
    $stmt->execute([':v' => $previous]);
    $pdo->exec("DELETE FROM mdl_config WHERE name IN ('lab_rickroll_prev_top', 'lab_rickroll_prev_top_saved')");
    @unlink('/var/www/html/good-hacker.webp');
    passthru('php -d memory_limit=256M /var/www/html/admin/cli/purge_caches.php >/dev/null 2>&1');

    $check = $pdo->query("SELECT value FROM mdl_config WHERE name='additionalhtmltopofbody'")->fetchColumn();
    $fileleft = file_exists('/var/www/html/good-hacker.webp');
    $linkleft = is_string($check) && strpos($check, 'good-hacker.webp') !== false;
    if ($fileleft || $linkleft) {
        $failed = sprintf(
            'rickroll-reset=failed image=%s link=%s',
            $fileleft ? 'present' : 'absent',
            $linkleft ? 'present' : 'absent'
        );
        fwrite(STDERR, $failed . "\n");
        file_put_contents('/loot/p1', $failed . "\n");
        exit(1);
    }

    $proof = 'rickroll-reset=ok image=absent link=absent top=restored db=verified' . "\n";
    file_put_contents('/loot/p1', $proof);
    echo $proof;
} catch (Throwable $e) {
    $failed = 'rickroll-reset=failed reason=' . preg_replace('/\s+/', ' ', $e->getMessage());
    fwrite(STDERR, $failed . "\n");
    file_put_contents('/loot/p1', $failed . "\n");
    exit(1);
}
